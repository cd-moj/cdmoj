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


def _score_freshness_or_decline(contest, f, floor_s=8):
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
    if not cache_fresh(cf, 20, inputs):
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
    if not cache_fresh(cf, 20, inputs):
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
    if not cache_fresh(cf, 30, inputs):
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
    if not cache_fresh(cf, 900, inputs):
        raise Decline("problems-cache frio")   # o bash serve (e regenera destacado se for o caso)
    return serve_file_maybe_gz(cf, params, ctype="application/json; charset=utf-8")


ROUTES = {
    "/contest/score": r_score,
    "/contest/basic": r_basic,
    "/contest/navbuttons": r_navbuttons,
    "/contest/rounds": r_rounds,
    "/contest/balloons": r_balloons,
    "/contest/problems": r_problems,
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
