#!/usr/bin/env python3
"""moj-porteiro — o caminho RÁPIDO das rotas quentes de leitura da API.

Fala FastCGI com o nginx (mesmo socket-esquema do fcgiwrap/molde) e serve, em ~1-3 ms e sem
fork nenhum, as rotas cujo corpo JÁ ESTÁ MATERIALIZADO em disco pelo bash:
    /contest/score  /contest/basic  /contest/navbuttons  /contest/rounds
    /contest/balloons  /contest/problems

A REGRA QUE GOVERNA TUDO (decidida com o Ribas, 28/08/2026): o porteiro é um LEITOR PURO.
Ele nunca regenera cache, nunca escreve, nunca inventa resposta de erro. Qualquer coisa fora
do caso feliz — cache velho/ausente, sessão esquisita, variante que não reconhece, POST,
rota de recorte (scope=mine) — ele DECLINA: fecha a conexão sem responder, o nginx vê 502 e o
`error_page 502 = @moj_fcgiwrap` entrega a requisição ao bash de sempre, que responde E
regenera o cache (que o porteiro volta a servir na próxima). O bash continua dono de toda a
verdade; o porteiro é só o atalho do caso comum. Corolário importante: como o porteiro só
serve cache FRESCO, a preguiça de regeneração do bash continua exercitada — a classe de
requisição que exige trabalho é exatamente a que cai para ele.

⚠ As regras de VARIANTE espelhadas aqui são REGRAS DE SEGURANÇA (papel da nav, coorte do
placar, autor da lista de problemas). Fonte da verdade: os handlers bash + libs (score.sh,
basic.sh, navbuttons.sh, rounds.sh, balloons.sh, problems.sh, lib/auth.sh, lib/cohorts.sh,
lib/contest-gate.sh). Mexeu na regra lá ⇒ mexa AQUI e rode o diferencial
(server/test/molde-diff.sh) — é o teste que impede as duas implementações de divergirem.

Uso: moj-porteiro.py -s <socket> [-c workers] [-b backlog]
     moj-porteiro.py --selftest        (fixture própria; roda no build da imagem)
"""
import json
import os
import re
import signal
import socket
import struct
import sys
import time

CONTESTSDIR = os.environ.get("CONTESTSDIR", "/data/contests")
RUNDIR = os.environ.get("RUNDIR", "/data/run")
SESSIONDIR = os.environ.get("SESSIONDIR", os.path.join(RUNDIR, "sessions"))
MOJ_HOME = os.environ.get("MOJ_HOME", "/opt/moj/cdmoj")

def _env_int(name, dflt):
    v = os.environ.get(name, "")
    return int(v) if v.isdigit() else dflt

# Orçamentos de frescor — MESMOS envs (e defaults) dos handlers bash. Alargá-los via env
# (entrypoint) reduz os DECLINES p/ o bash; entrada mais nova que o cache SEMPRE invalida,
# então edição de admin propaga na hora independente do TTL.
SCORE_FLOOR = _env_int("SCORE_SERVE_FLOOR_S", 8)
TTL_BASIC = _env_int("BASIC_CACHE_TTL", 20)
TTL_NAV = _env_int("NAV_CACHE_TTL", 20)
TTL_ROUNDS = _env_int("ROUNDS_CACHE_TTL", 30)
TTL_PROBLEMS = _env_int("PROBLEMS_CACHE_TTL", 900)
HANDLERS = os.path.join(MOJ_HOME, "server/api/v1/handlers")

VALID_ID = re.compile(r"^[A-Za-z0-9._@#+-]+$")
ROLE_SUFFIX = re.compile(r"\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$")
CH_ID_OK = re.compile(r"^[a-z0-9][a-z0-9_-]{0,23}$")


class Decline(Exception):
    """Fora do caso feliz: a conexão fecha sem resposta e o bash assume (502→fallback)."""


# ---------------------------------------------------------------- utilidades de arquivo
def valid_id(s):
    return bool(s) and bool(VALID_ID.match(s)) and ".." not in s


def mtime_ns(path):
    try:
        return os.stat(path).st_mtime_ns
    except OSError:
        return None


def cache_fresh(cf, ttl, inputs):
    """Espelho do resp_cache_fresh (lib/common.sh): entradas por -nt + teto de idade."""
    try:
        st = os.stat(cf)
    except OSError:
        return False
    if st.st_size <= 0:
        return False
    for inp in inputs:
        m = mtime_ns(inp)
        if m is not None and m > st.st_mtime_ns:
            return False
    if ttl > 0 and (time.time() - st.st_mtime) > ttl:
        return False
    return True


def conf_value(contest, key):
    """Espelho do conf_value: PRIMEIRA linha `KEY=...`, aspas removidas."""
    pref = key + "="
    try:
        with open(os.path.join(CONTESTSDIR, contest, "conf"), errors="replace") as f:
            for line in f:
                if line.startswith(pref):
                    return line[len(pref):].rstrip("\n").replace("'", "").replace('"', "")
    except OSError:
        pass
    return ""


def read_json(path):
    try:
        with open(path, "rb") as f:
            return json.loads(f.read())
    except (OSError, ValueError):
        return None


# ---------------------------------------------------------------- sessão / papéis
def load_session(params):
    """None = sem token (anônimo legítimo). (contest, login) = autenticado e vivo.
    Token PRESENTE que não resolve com certeza ⇒ Decline — nunca degradar p/ anônimo."""
    auth = params.get("HTTP_AUTHORIZATION", "")
    if not auth:
        return None
    if not auth.startswith("Bearer "):
        raise Decline("auth não-Bearer")
    tok = auth[7:]
    if not valid_id(tok):
        raise Decline("token esquisito")
    try:
        with open(os.path.join(SESSIONDIR, tok), errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        raise Decline("sessão ausente/ilegível")  # bash devolveria 401 — dele a palavra
    sess = {}
    for ln in lines:
        for k in ("CONTEST", "LOGIN"):
            if ln.startswith(k + "="):
                v = ln[len(k) + 1:]
                # printf %q não cita ids simples; QUALQUER citação/escape = fora do feliz
                if v and not VALID_ID.match(v):
                    raise Decline("sessão com escape")
                sess[k] = v
    contest, login = sess.get("CONTEST", ""), sess.get("LOGIN", "")
    if not login or not contest or not valid_id(contest) or not valid_id(login):
        raise Decline("sessão incompleta")
    # _session_account_alive: local OU fonte (USERS_FROM)
    if not os.path.isfile(os.path.join(CONTESTSDIR, contest, "users", login, "account.json")):
        src = conf_value(contest, "USERS_FROM")
        if not (src and valid_id(src) and src != contest and os.path.isfile(
                os.path.join(CONTESTSDIR, src, "users", login, "account.json"))):
            raise Decline("conta não-viva")
    return contest, login


def role_of(login):
    """A cadeia do navbuttons.sh, NA MESMA ORDEM."""
    for suf, role in ((".animeitor", "animeitor"), (".cstaff", "cstaff"), (".staff", "staff"),
                      (".admin", "admin"), (".cjudge", "chief"), (".judge", "judge"),
                      (".mon", "mon")):
        if login.endswith(suf):
            return role
    return "time"


def is_judge(login):    # .judge | .cjudge | .admin (lib/auth.sh)
    return login.endswith((".judge", ".cjudge", ".admin"))


def is_priv_rounds(login):  # rounds.sh: admin|judge|chief|staff|cstaff|mon
    return login.endswith((".admin", ".judge", ".cjudge", ".staff", ".cstaff", ".mon"))


# ---------------------------------------------------------------- gates de contest
def require_contest(contest):
    if not valid_id(contest):
        raise Decline("contest inválido")
    if not os.path.isfile(os.path.join(CONTESTSDIR, contest, "conf")):
        raise Decline("contest inexistente")


def secret_gate(contest, sess):
    if conf_value(contest, "SECRET") == "1":
        if not (sess and sess[0] == contest):
            raise Decline("secreto sem sessão")


def conf_int(contest, key):
    v = conf_value(contest, key)
    return int(v) if v.isdigit() else 0


def override_end(contest, login):
    """Espelho do time_override_end: PRIMEIRA entrada cujo regex casa o login."""
    data = read_json(os.path.join(CONTESTSDIR, contest, "time-overrides.json"))
    if not isinstance(data, list) or not login:
        return None
    for ent in data:
        if not isinstance(ent, dict):
            continue
        rr, e = ent.get("regex") or "", ent.get("end")
        if rr and isinstance(e, (int, float)) and not isinstance(e, bool):
            try:
                if re.search(rr, login):
                    return int(e)
            except re.error:
                continue  # jq: try..catch false — regex ruim = não casa
    return None


def end_effective(contest, login):
    end = conf_int(contest, "CONTEST_END")
    o = override_end(contest, login)
    if o is not None and end > 0 and o > end:
        end = o
    return end


def end_all(contest):
    end = conf_int(contest, "CONTEST_END")
    data = read_json(os.path.join(CONTESTSDIR, contest, "time-overrides.json"))
    if isinstance(data, list) and end > 0:
        ends = [int(e["end"]) for e in data if isinstance(e, dict) and (e.get("regex") or "")
                and isinstance(e.get("end"), (int, float)) and not isinstance(e.get("end"), bool)]
        if ends and max(ends) > end:
            end = max(ends)
    return end


def over_for_all(contest):
    e = end_all(contest)
    return e > 0 and time.time() > e


# ---------------------------------------------------------------- coortes (lib/cohorts.sh)
def ch_ctx(contest, login):
    """Espelho do jq de ch_ctx: (enabled, cohort_id, view)."""
    j = read_json(os.path.join(CONTESTSDIR, contest, "cohorts.json")) or {}
    cohorts = []
    for c in (j.get("cohorts") or []):
        if not isinstance(c, dict) or not (c.get("id") or ""):
            continue
        cohorts.append({"id": c["id"], "regex": c.get("regex") or "",
                        "public": c.get("public") is not False,
                        "ranking": c.get("ranking") is True,
                        "default": c.get("default") is True})
    enabled = any((not c["public"]) or c["ranking"] for c in cohorts)
    released = j.get("results_released") is True

    acc = read_json(os.path.join(CONTESTSDIR, contest, "users", login, "account.json")) or {}
    ex = ((acc.get("team") or {}).get("cohort") or "") if isinstance(acc, dict) else ""

    co = ""
    if ex and any(c["id"] == ex for c in cohorts):
        co = ex
    else:
        for c in cohorts:
            if c["regex"]:
                try:
                    if re.search(c["regex"], login, re.I):
                        co = c["id"]
                        break
                except re.error:
                    continue
        if not co:
            co = next((c["id"] for c in cohorts if c["default"]), cohorts[0]["id"] if cohorts else "")

    if not enabled:
        vw = "public"
    elif released:
        vw = "all"
    elif ROLE_SUFFIX.search(login):
        vw = "all"
    elif co and any(c["id"] == co and not c["public"] for c in cohorts):
        vw = co
    else:
        vw = "public"
    return enabled, co, vw


def ch_is_ranking_view(contest, view):
    j = read_json(os.path.join(CONTESTSDIR, contest, "cohorts.json")) or {}
    return any(isinstance(c, dict) and c.get("id") == view and c.get("public") is not False
               and c.get("ranking") is True for c in (j.get("cohorts") or []))


def ch_view_file(contest, view, full=False):
    sfx = "-full" if full else ""
    base = os.path.join(CONTESTSDIR, contest, "var")
    if view in ("public", ""):
        return os.path.join(base, f"placar{sfx}.txt")
    return os.path.join(base, f"placar-view-{view}{sfx}.txt")


# ---------------------------------------------------------------- resposta
def cgi(body, ctype="application/json; charset=utf-8", extra=b""):
    head = b"Status: 200 OK\r\nContent-Type: " + ctype.encode() + b"\r\n" + extra + b"\r\n"
    return head + body


def serve_file_maybe_gz(path, params, extra=b"", ctype="text/plain; charset=utf-8"):
    """Espelho do padrão .gz da casa: só serve o .gz quando NÃO é mais velho que o cru."""
    gz = path + ".gz"
    accept = "gzip" in params.get("HTTP_ACCEPT_ENCODING", "")
    mp, mg = mtime_ns(path), mtime_ns(gz)
    if accept and mg is not None and mp is not None and not (mp > mg) and os.path.getsize(gz) > 0:
        with open(gz, "rb") as f:
            return cgi(f.read(), ctype, extra + b"Content-Encoding: gzip\r\nVary: Accept-Encoding\r\n")
    if mp is None:
        raise Decline("arquivo ausente")
    with open(path, "rb") as f:
        return cgi(f.read(), ctype, extra)


# ---------------------------------------------------------------- as rotas
def r_score(contest, q, params):
    sess = load_session(params)
    secret_gate(contest, sess)
    slogin = sess[1] if (sess and sess[0] == contest) else ""
    var = os.path.join(CONTESTSDIR, contest, "var")

    if q.get("scope") == "mine":
        raise Decline("scope=mine é recorte do bash")

    start = conf_int(contest, "CONTEST_START")
    now = time.time()
    if start > 0 and now < start:                       # pré-início: vitrine
        if slogin and (is_judge(slogin) or slogin.endswith(".animeitor")):
            raise Decline("privilegiado no pré-início")
        pf = os.path.join(var, "placar-prestart.txt")
        _score_freshness_or_decline(contest, pf)
        return serve_file_maybe_gz(pf, params, b"X-MOJ-Frozen: 0\r\n")

    view = "public"
    ch_on = False
    if _nonempty(os.path.join(CONTESTSDIR, contest, "cohorts.json")):
        en, _co, _cv = ch_ctx(contest, slogin)
        ch_on = en
    if ch_on:
        vp = q.get("view", "")
        if vp == "oficial":
            view = "public"
        elif vp and ch_is_ranking_view(contest, vp):
            view = vp
        elif slogin:
            view = _cv
        if view != "public" and not CH_ID_OK.match(view) and view != "all":
            raise Decline("visão esquisita")

    f = ch_view_file(contest, view)
    _score_freshness_or_decline(contest, f)

    ff = ch_view_file(contest, view, full=True)
    if q.get("view") != "public" and os.path.isfile(ff) and slogin:
        priv = is_judge(slogin) or slogin.endswith(".animeitor")
        if not priv:
            allow = conf_value(contest, "SCORE_FULL_USERS").split()
            priv = slogin in allow
        if priv:
            f = ff

    frozen = b"0"
    fz = conf_int(contest, "FREEZE_TIME")
    if fz > 0 and now >= fz and f != ff:
        frozen = b"1"
    return serve_file_maybe_gz(f, params, b"X-MOJ-Frozen: " + frozen + b"\r\n")


def _nonempty(path):
    try:
        return os.path.getsize(path) > 0
    except OSError:
        return False


def _score_freshness_or_decline(contest, f, floor_s=None):
    if floor_s is None:
        floor_s = SCORE_FLOOR
    """Espelho do gatilho do score.sh: fontes mais novas + fora do piso ⇒ bash regenera."""
    mf = mtime_ns(f)
    if mf is None:
        raise Decline("placar ausente")
    for s in (os.path.join(CONTESTSDIR, contest, "var", ".score-dirty"),
              os.path.join(CONTESTSDIR, contest, "conf")):
        ms = mtime_ns(s)
        if ms is not None and ms > mf:
            if (time.time() * 1e9 - mf) > floor_s * 1e9:
                raise Decline("placar velho fora do piso")
            break


def r_basic(contest, q, params):
    sess = load_session(params)
    var = os.path.join(CONTESTSDIR, contest, "var")
    pessoal = bool(sess and sess[0] == contest)
    if pessoal:
        end = end_effective(contest, sess[1])
        co, cv = "", ""
        if _nonempty(os.path.join(CONTESTSDIR, contest, "cohorts.json")):
            _en, co, cv = ch_ctx(contest, sess[1])
        for x in (co, cv):
            if x and not CH_ID_OK.match(x):
                raise Decline("coorte fora do padrão")
        bcvar = f"u.{end or 0}.{co or '_'}.{cv or '_'}"
    else:
        bcvar = "anon"
    cf = os.path.join(var, f"basic-cache.{bcvar}.json")
    inputs = [os.path.join(CONTESTSDIR, contest, p) for p in
              ("conf", "rounds.json", "cohorts.json", "time-overrides.json")]
    if not cache_fresh(cf, TTL_BASIC, inputs):
        raise Decline("basic-cache frio")
    with open(cf, "rb") as f:
        return cgi(f.read())


def r_navbuttons(contest, q, params):
    sess = load_session(params)
    if not (sess and sess[0] == contest):
        raise Decline("nav exige sessão do contest")
    role = role_of(sess[1])
    cf = os.path.join(CONTESTSDIR, contest, "var", f"nav-cache.{role}.json")
    inputs = [os.path.join(CONTESTSDIR, contest, p) for p in
              ("conf", "users", "time-overrides.json")]
    if not cache_fresh(cf, TTL_NAV, inputs):
        raise Decline("nav-cache frio")
    with open(cf, "rb") as f:
        return cgi(f.read())


def r_rounds(contest, q, params):
    sess = load_session(params)
    if not (sess and sess[0] == contest):
        raise Decline("rounds exige sessão do contest")
    rvar = "priv" if is_priv_rounds(sess[1]) else "pub"
    cf = os.path.join(CONTESTSDIR, contest, "var", f"rounds-cache.{rvar}.json")
    inputs = [os.path.join(CONTESTSDIR, contest, p) for p in ("conf", "rounds.json")]
    if not cache_fresh(cf, TTL_ROUNDS, inputs):
        raise Decline("rounds-cache frio")
    with open(cf, "rb") as f:
        return cgi(f.read())


def r_balloons(contest, q, params):
    sess = load_session(params)
    secret_gate(contest, sess)
    cf = os.path.join(CONTESTSDIR, contest, "var", "balloons-cache.json")
    inputs = [os.path.join(CONTESTSDIR, contest, "balloons.json"),
              os.path.join(HANDLERS, "contest/balloons.sh")]   # a paleta default é CÓDIGO
    if not cache_fresh(cf, 0, inputs):
        raise Decline("balloons-cache frio")
    with open(cf, "rb") as f:
        return cgi(f.read())


def r_problems(contest, q, params):
    sess = load_session(params)
    if not (sess and sess[0] == contest):
        raise Decline("problems exige sessão do contest")
    login = sess[1]
    # can_see_problems: staff/cstaff/animeitor e pré-início são respostas do BASH (locked)
    if not is_judge(login):
        if login.endswith((".staff", ".cstaff", ".animeitor")):
            raise Decline("papel sem enunciado (locked é do bash)")
        start = conf_int(contest, "CONTEST_START")
        if start > 0 and time.time() < start:
            raise Decline("pré-início (locked é do bash)")
    show_author = over_for_all(contest) or is_judge(login)   # is_judge cobre admin/chief/judge
    cvar = "author" if show_author else "noauthor"
    cdir = os.path.join(CONTESTSDIR, contest, "var")
    cf = os.path.join(cdir, f"problems-cache.{cvar}.json")
    inputs = [os.path.join(CONTESTSDIR, contest, "conf"),
              os.path.join(CONTESTSDIR, contest, "problem-langs.json"),
              os.path.join(CONTESTSDIR, contest, "problem-judges.json"),
              os.path.join(CONTESTSDIR, contest, "enunciados"),
              os.path.join(RUNDIR, "tl"),
              os.path.join(cdir, ".problems-dirty")]
    if not cache_fresh(cf, TTL_PROBLEMS, inputs):
        raise Decline("problems-cache frio")   # o bash serve (e regenera destacado se for o caso)
    return serve_file_maybe_gz(cf, params, ctype="application/json; charset=utf-8")



def r_updates(contest, q, params):
    """Espelho COMPUTADO de handlers/contest/updates.sh — a 1ª rota que o porteiro gera
    inteira (leitura pura: news.json + clarifications/*.json + filtro por visibilidade).
    Clar com JSON inválido ⇒ Decline (o bash tem um comportamento peculiar — slurp vira [] —
    e a resposta canônica é dele)."""
    sess = load_session(params)
    if not (sess and sess[0] == contest):
        raise Decline("updates exige sessão do contest")
    login = sess[1]
    ns = q.get("news_since", "");  ns = int(ns) if ns.isdigit() else 0
    cs = q.get("clar_since", "");  cs = int(cs) if cs.isdigit() else 0

    def _num(x):
        return x if isinstance(x, (int, float)) and not isinstance(x, bool) else 0

    nf = os.path.join(CONTESTSDIR, contest, "news.json")
    news = {"last": 0, "count": 0, "unread": 0}
    if os.path.isfile(nf):
        data = read_json(nf)
        if isinstance(data, list):
            dates = [_num(n.get("date")) for n in data if isinstance(n, dict)]
            dates += [0] * (len(data) - len(dates))          # itens não-dict contam como date 0
            news = {"last": max(dates) if dates else 0, "count": len(data),
                    "unread": sum(1 for d in dates if d > ns)}
        # arquivo presente mas inválido: bash cai no zerado (jq -e falha) — igual aqui

    cdir = os.path.join(CONTESTSDIR, contest, "clarifications")
    priv = login.endswith((".admin", ".judge", ".cjudge", ".mon"))
    vis = []
    try:
        names = sorted(f for f in os.listdir(cdir) if f.endswith(".json"))
    except OSError:
        names = []
    for fn in names:
        c = read_json(os.path.join(cdir, fn))
        if c is None:
            raise Decline("clarification com JSON inválido")   # peculiaridade é do bash
        if not isinstance(c, dict):
            continue
        if not (priv or c.get("login") == login or c.get("public") is True):
            continue
        if not (c.get("answer") or ""):
            continue
        vis.append(_num(c.get("answered_at")))
    clar = {"last": max(vis) if vis else 0, "count": len(vis),
            "unread": sum(1 for a in vis if a > cs)}

    body = json.dumps({"success": True, "news": news, "clar": clar},
                      separators=(",", ":")) + "\n"
    return cgi(body.encode())



def r_staff_queue(contest, q, params):
    """Espelho de handlers/contest/staff/queue.sh — a LISTAGEM é computada aqui; o RECONCILE
    de balões é ESCRITA e fica no bash: quando ele está DEVIDO (mesmo gate do
    pr_reconcile_balloons: .score-dirty mais novo que .balloon-stamp, fora do piso de 10 s),
    a requisição DECLINA e o bash reconcilia + serve. Escopo do staff: só via .scope-cache
    FRESCO (senão decline — o bash o recomputa). Fidelidade: o find do bash lista TODO *.json
    do dir (staff-filters.json inclusive — a linha fantasma do admin é comportamento)."""
    sess = load_session(params)
    if not (sess and sess[0] == contest):
        raise Decline("queue exige sessão do contest")
    login = sess[1]
    if not login.endswith((".staff", ".cstaff", ".admin")):
        raise Decline("papel sem fila (403 é do bash)")
    pdir = os.path.join(CONTESTSDIR, contest, "print-requests")

    # gate do reconcile (mesma condição sob a qual o bash FARIA trabalho)
    dirty = mtime_ns(os.path.join(CONTESTSDIR, contest, "var", ".score-dirty"))
    stamp = mtime_ns(os.path.join(pdir, ".balloon-stamp"))
    if dirty is not None and (stamp is None or dirty > stamp):
        if stamp is None or (time.time() * 1e9 - stamp) > 10 * 1e9:
            raise Decline("reconcile de balões devido")

    admin = login.endswith(".admin")
    vis = None                                   # None = vê tudo (admin ou sem escopo)
    if not admin:
        ff = os.path.join(pdir, "staff-filters.json")
        filters = read_json(ff) if os.path.isfile(ff) else None
        if isinstance(filters, dict):
            ent = filters.get(login)
            if isinstance(ent, list) and len(ent) > 0:
                if not re.match(r"^[A-Za-z0-9._-]+$", login) or ".." in login:
                    raise Decline("login fora do padrão de cache")
                cf = os.path.join(pdir, ".scope-cache", login)
                mcf = mtime_ns(cf)
                mff = mtime_ns(ff)
                if (mcf is None or (mff is not None and mff > mcf)
                        or (time.time() * 1e9 - mcf) > 300 * 1e9):
                    raise Decline("scope-cache frio (bash recomputa)")
                with open(cf, errors="replace") as fh:
                    vis = {ln for ln in fh.read().split("\n") if ln}
        # filters inválido/sem entrada => vê tudo (mesmo rc!=0 do bash)

    rows = []
    try:
        names = sorted(f for f in os.listdir(pdir) if f.endswith(".json"))
    except OSError:
        names = []
    for fn in names:
        t = read_json(os.path.join(pdir, fn))
        if t is None:
            raise Decline("tarefa com JSON inválido")
        if not isinstance(t, dict):
            t = {}
        if vis is not None and (t.get("login") or "") not in vis:
            continue
        g = t.get
        kind = g("kind")
        rows.append({
            "id": g("id"), "seq": g("seq"), "login": g("login"), "fullname": g("fullname"),
            "team": g("team"), "univ": g("univ"),
            "kind": kind if kind not in (None, False) else "print",
            "short": g("short"), "color_hex": g("color_hex"), "color_name": g("color_name"),
            "first_site": g("first_site") is True,
            "filename": g("filename"), "mime": g("mime"), "size": g("size"), "time": g("time"),
            "status": g("status"), "pages": g("pages"), "build_ok": g("build_ok"),
            "claimed_by": g("claimed_by"), "claimed_at": g("claimed_at"),
            "processed_by": g("processed_by"), "processed_at": g("processed_at"),
            "delivered_by": g("delivered_by"), "delivered_at": g("delivered_at")})

    def _key(r):
        st = r["status"]
        rank = 0 if st == "pending" else (1 if st == "printed" else 2)
        sq = r["seq"]
        # ordem do sort_by do jq: null antes de número
        if isinstance(sq, bool) or not isinstance(sq, (int, float)):
            return (rank, 0, 0)
        return (rank, 1, sq)
    rows.sort(key=_key)

    bfz = 0
    if admin:
        fz = os.path.join(pdir, ".balloon-frozen")
        if os.path.isfile(fz):
            try:
                with open(fz, errors="replace") as fh:
                    bfz = sum(1 for ln in fh if '"id"' in ln)
            except OSError:
                bfz = 0
    body = json.dumps({"success": True, "requests": rows, "balloons_frozen": bfz},
                      separators=(",", ":")) + "\n"
    return cgi(body.encode())


def r_summary(contest, q, params):
    """/submission/summary de NÃO-JUIZ com log OCULTO (showlog_effective==0) responde SEMPRE
    '{}' — o gate `hidden` do handlers/submission/summary.sh corta antes de qualquer id. É o
    poll mais quente da prova (cada time com run pendente pola a cada poucos segundos) e sob
    SHOWLOG=0 queimava um bash inteiro para devolver objeto vazio (Maratona 29/08: router.sh
    a 25 cores). Espelho de showlog_effective (lib/verdict.sh): SHOWLOG explícito no conf
    decide (última ocorrência; 0=oculto, resto=visível); ausente = oculto SÓ em modo icpc
    (contest_score_mode: desconhecido/vazio TAMBÉM cai em icpc). Qualquer outra coisa —
    juiz/admin, showlog visível, sem ids — DECLINA para o bash."""
    if not q.get("ids"):
        raise Decline("sem ids (o 400 é do bash)")
    sess = load_session(params)
    if not (sess and sess[0] == contest):
        raise Decline("summary exige sessão do contest")
    if is_judge(sess[1]):
        raise Decline("juiz vê o resumo cheio — bash")
    showlog = None
    mode_raw = ""
    try:
        with open(os.path.join(CONTESTSDIR, contest, "conf"), "rb") as f:
            for ln in f:
                s = ln.decode("utf-8", "replace").strip()
                if s.startswith("SHOWLOG="):
                    showlog = s[8:].strip().strip('"').strip("'")
                elif s.startswith("CONTEST_TYPE="):
                    mode_raw = s[13:]
                elif s.startswith("SCORE_MODE="):
                    mode_raw = s[11:]
    except OSError:
        raise Decline("conf ilegível")
    if showlog is not None and showlog != "":
        hidden = (showlog == "0")
    else:
        m = mode_raw.strip().strip('"').strip("'").lower().replace(" ", "")
        visible = {"obi", "heuristic", "flia", "treino", "lista-publica",
                   "lista-privada", "lista", "outro", "custom"}
        hidden = m not in visible
    if not hidden:
        raise Decline("showlog visível — resumo real é do bash")
    return cgi(b"{}\n")


ROUTES = {
    "/contest/score": r_score,
    "/contest/updates": r_updates,
    "/contest/basic": r_basic,
    "/contest/navbuttons": r_navbuttons,
    "/contest/rounds": r_rounds,
    "/contest/balloons": r_balloons,
    "/contest/staff/queue": r_staff_queue,
    "/contest/problems": r_problems,
    "/submission/summary": r_summary,
}


def handle_request(params):
    if params.get("REQUEST_METHOD", "GET") != "GET":
        raise Decline("só GET")
    route = ROUTES.get(params.get("PATH_INFO", ""))
    if route is None:
        raise Decline("rota desconhecida")
    q = {}
    for pair in params.get("QUERY_STRING", "").split("&"):
        if "=" in pair:
            k, _, v = pair.partition("=")
            q[_urldecode(k)] = _urldecode(v)
        elif pair:
            q[_urldecode(pair)] = ""
    contest = q.get("contest", "")
    if not contest:
        raise Decline("sem contest")
    require_contest(contest)
    # isolamento por subdomínio (router.sh:57-64): rota de contest é permitida; só o mismatch cai
    ch = params.get("CONTEST_HOST", "")
    if ch and valid_id(ch) and q.get("contest") and q["contest"] != ch:
        raise Decline("contest_mismatch é do bash")
    return route(contest, q, params)


def _urldecode(s):
    if "%" not in s and "+" not in s:
        return s
    try:
        from urllib.parse import unquote_plus
        return unquote_plus(s)
    except Exception:
        return s


# ---------------------------------------------------------------- FastCGI (responder mínimo)
FCGI_BEGIN, FCGI_ABORT, FCGI_END, FCGI_PARAMS, FCGI_STDIN, FCGI_STDOUT = 1, 2, 3, 4, 5, 6


def _read_exact(conn, n):
    buf = b""
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            raise Decline("conexão fechou no meio")
        buf += chunk
    return buf


def _parse_nv(blob):
    """Pares nome-valor do FCGI (len 1 byte, ou 4 bytes com bit alto)."""
    out, i, n = {}, 0, len(blob)
    while i < n:
        ln = blob[i]
        if ln & 0x80:
            ln = struct.unpack(">I", blob[i:i + 4])[0] & 0x7FFFFFFF
            i += 4
        else:
            i += 1
        lv = blob[i]
        if lv & 0x80:
            lv = struct.unpack(">I", blob[i:i + 4])[0] & 0x7FFFFFFF
            i += 4
        else:
            i += 1
        name = blob[i:i + ln].decode("utf-8", "replace"); i += ln
        val = blob[i:i + lv].decode("utf-8", "replace"); i += lv
        out[name] = val
    return out


def fcgi_conn(conn):
    conn.settimeout(10)
    params_blob = b""
    req_id = 1
    params_done = stdin_done = False
    while not (params_done and stdin_done):
        ver, rtype, rid, clen, plen, _ = struct.unpack(">BBHHBB", _read_exact(conn, 8))
        content = _read_exact(conn, clen) if clen else b""
        if plen:
            _read_exact(conn, plen)
        if rtype == FCGI_BEGIN:
            req_id = rid
        elif rtype == FCGI_PARAMS:
            if clen == 0:
                params_done = True
            else:
                params_blob += content
        elif rtype == FCGI_STDIN:
            if clen == 0:
                stdin_done = True
        elif rtype == FCGI_ABORT:
            raise Decline("abortado")
    params = _parse_nv(params_blob)
    body = handle_request(params)          # Decline sobe e fecha sem resposta
    # resposta: STDOUT em blocos + STDOUT vazio + END_REQUEST
    for i in range(0, len(body), 32768):
        chunk = body[i:i + 32768]
        conn.sendall(struct.pack(">BBHHBB", 1, FCGI_STDOUT, req_id, len(chunk), 0, 0) + chunk)
    conn.sendall(struct.pack(">BBHHBB", 1, FCGI_STDOUT, req_id, 0, 0, 0))
    conn.sendall(struct.pack(">BBHHBB", 1, FCGI_END, req_id, 8, 0, 0) +
                 struct.pack(">IBBBB", 0, 0, 0, 0, 0))


def worker(lsock):
    while True:
        try:
            conn, _ = lsock.accept()
        except OSError:
            time.sleep(0.05)               # socket de escuta com soluço: nunca girar a seco
            continue
        try:
            fcgi_conn(conn)
        except Decline:
            pass                            # fecha sem resposta ⇒ nginx 502 ⇒ fallback bash
        except (BrokenPipeError, ConnectionResetError, TimeoutError):
            pass                            # nginx/cliente desistiu no meio (429/abort) — normal
        except Exception as e:              # qualquer bug nosso = mesma coisa, com registro
            print(f"moj-porteiro: erro inesperado: {e!r}", file=sys.stderr, flush=True)
        finally:
            try:
                conn.close()
            except OSError:
                pass


def master(sock_path, nworkers, backlog):
    try:
        os.unlink(sock_path)
    except OSError:
        pass
    lsock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    lsock.bind(sock_path)                   # perms: umask do entrypoint (007)
    lsock.listen(backlog)
    kids = {}

    def spawn():
        pid = os.fork()
        if pid == 0:
            worker(lsock)
            os._exit(0)
        kids[pid] = True

    for _ in range(nworkers):
        spawn()

    def term(_sig, _frm):
        for pid in kids:
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
        sys.exit(0)
    signal.signal(signal.SIGTERM, term)

    while True:
        try:
            pid, _st = os.wait()
        except InterruptedError:
            continue
        except ChildProcessError:
            time.sleep(1)
            continue
        if pid in kids:
            del kids[pid]
            print("moj-porteiro: worker morreu — respawn", file=sys.stderr, flush=True)
            spawn()


# ---------------------------------------------------------------- selftest (fixture própria)
def selftest():
    import tempfile
    global CONTESTSDIR, SESSIONDIR
    tmp = tempfile.mkdtemp(prefix="porteiro-st.")
    CONTESTSDIR = os.path.join(tmp, "contests")
    SESSIONDIR = os.path.join(tmp, "sessions")
    cdir = os.path.join(CONTESTSDIR, "st", "var")
    os.makedirs(cdir)
    os.makedirs(SESSIONDIR)
    with open(os.path.join(CONTESTSDIR, "st", "conf"), "w") as f:
        f.write("CONTEST_NAME=Selftest\nCONTEST_START=1\nCONTEST_END=99999999999\n")
    with open(os.path.join(cdir, "rounds-cache.pub.json"), "w") as f:
        f.write('{"success":true,"rounds":[]}')
    os.makedirs(os.path.join(CONTESTSDIR, "st", "users", "eq1"))
    with open(os.path.join(CONTESTSDIR, "st", "users", "eq1", "account.json"), "w") as f:
        f.write('{"login":"eq1"}')
    with open(os.path.join(SESSIONDIR, "tok1"), "w") as f:
        f.write("CONTEST=st\nLOGIN=eq1\n")
    with open(os.path.join(cdir, "placar.txt"), "w") as f:
        f.write("icpc\nlinha\n")

    def req(path, qs, auth=""):
        p = {"PATH_INFO": path, "REQUEST_METHOD": "GET", "QUERY_STRING": qs,
             "HTTP_AUTHORIZATION": auth}
        try:
            return handle_request(p)
        except Decline as d:
            return ("DECLINE %s" % d).encode()

    ok = True
    r = req("/contest/rounds", "contest=st", "Bearer tok1")
    ok &= b'"rounds"' in r or print("rounds FALHOU: %r" % r[:80]) is not None
    r = req("/contest/score", "contest=st", "")
    ok &= b"linha" in r or print("score FALHOU: %r" % r[:80]) is not None
    r = req("/contest/rounds", "contest=st", "Bearer NAOEXISTE")
    ok &= r.startswith(b"DECLINE") or print("decline FALHOU: %r" % r[:80]) is not None
    r = req("/contest/score", "contest=../etc", "")
    ok &= r.startswith(b"DECLINE") or print("traversal FALHOU: %r" % r[:80]) is not None
    import shutil
    shutil.rmtree(tmp)
    if not ok:
        return 1
    print("selftest ok")
    return 0


def main():
    args = sys.argv[1:]
    if "--selftest" in args:
        sys.exit(selftest())
    sock, nw, bl = None, 4, 16
    i = 0
    while i < len(args):
        a = args[i]
        if a == "-s":
            i += 1; sock = args[i]
        elif a == "-c":
            i += 1; nw = int(args[i])
        elif a == "-b":
            i += 1; bl = int(args[i])
        else:
            print(f"arg desconhecido: {a}", file=sys.stderr)
            sys.exit(2)
        i += 1
    if not sock:
        print("uso: moj-porteiro.py -s socket [-c workers] [-b backlog] | --selftest",
              file=sys.stderr)
        sys.exit(2)
    master(sock, nw, bl)


if __name__ == "__main__":
    main()
