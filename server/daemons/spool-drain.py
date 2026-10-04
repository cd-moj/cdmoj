#!/usr/bin/env python3
# spool-drain.py — drenador PARALELO de SUBMITS do spool (nascido na prova da Maratona,
# 29/08/2026, com 2.200 submissões represadas e a esteira serial do judged no limite).
#
# Espelha process_spool_file(submit em modo queue) → intake_enqueue → q_enqueue +
# archive_source do judged.sh, em Python (zero forks; a esteira bash custava ~0,8 s/arquivo
# só de execs). SÓ trata cmd=submit: ZERO escritas de history — o escritor único do history
# segue sendo o daemon (results/rejulgar/setverdict/synctreino ficam com ele).
#
# Convivência com o daemon vivo:
#   - claim ATÔMICO por rename p/ DOTFILE (.pydrain-*): o next_spool_file do bash ignora
#     dotfiles, então um arquivo reivindicado some do mundo dele;
#   - FIFO com ZONA DE BUFFER: os N mais velhos ficam p/ o bash (é nele que o bash está
#     trabalhando agora) — colisão real exigiria o bash atravessar N arquivos dentro da
#     janela de microssegundos do rename;
#   - qualquer coisa fora do caso feliz (JSON ruim, campo faltando, contest inválido) =
#     rename de VOLTA ao nome original — o bash trata do jeito canônico dele (Judge Error
#     auditado etc.). Este drenador NUNCA descarta nem fabrica veredicto.
#
# Uso (dentro do container do judged, que tem os volumes):
#   podman exec -d systemd-moj-judged python3 /data/run/spool-drain.py
# Sai sozinho após IDLE_EXIT_S sem submit elegível (não é serviço; é bomba de porão).
import json
import os
import re
import sys
import time
import base64

RUNDIR = os.environ.get("RUNDIR", "/data/run")
CONTESTS = os.environ.get("CONTESTSDIR", "/data/contests")
SPOOL = os.path.join(RUNDIR, "spool/submissions")
DONE = os.path.join(RUNDIR, "spool/submissions-done")
QUEUE = os.environ.get("QUEUEDIR", os.path.join(RUNDIR, "queue"))
# sched_band_of (sched-lib.sh) — desconhecido cai em lista-publica, como no bash
BANDS = {"super": "000-super", "prova": "020-prova",
         "lista-privada": "040-lista-privada", "rejulgar": "060-rejulgar"}
VALID = re.compile(r"^[A-Za-z0-9._-]+$")
PENDING = re.compile(r":(Not Answered Yet|On queue|on queue|Running|running):")


def _env_int(name, dflt):
    v = re.sub(r"[^0-9]", "", os.environ.get(name, ""))
    return int(v) if v else dflt


# menos prioridade p/ o time da prova com muitas pendentes — espelho do deprio_delay do judged.sh
DEPRIO_PENDING = _env_int("SUBMIT_DEPRIO_PENDING", 5)
DEPRIO_DELAY = _env_int("SUBMIT_DEPRIO_DELAY", 120)
BUFFER_OLDEST = 5
IDLE_EXIT_S = 120

_conf_cache = {}


def q_unescape(v):
    """Desfaz o escape do `printf %q` (`\\X` -> `X`), como o conf_value do bash (lib/common.sh)."""
    if "\\" not in v or v.startswith("$"):
        return v
    out, i = [], 0
    while i < len(v):
        c = v[i]
        if c == "\\":
            i += 1
            c = v[i] if i < len(v) else ""
        out.append(c)
        i += 1
    return "".join(out)


def conf(contest):
    if contest in _conf_cache:
        return _conf_cache[contest]
    prio, judges = "lista-publica", ""
    try:
        with open(os.path.join(CONTESTS, contest, "conf"), encoding="utf-8", errors="replace") as f:
            for ln in f:
                s = ln.strip()
                if s.startswith("CONTEST_PRIORITY="):
                    prio = s.split("=", 1)[1].strip().strip("'\"") or prio
                elif s.startswith("CONTEST_JUDGES="):
                    # o conf é gravado com %q: `j1\\ j2` — sem desfazer o escape só o último host julgava
                    # (o judged.sh usa `source` e acertava; auditoria 03/10/2026)
                    judges = q_unescape(s.split("=", 1)[1].strip().replace("'", "").replace('"', ""))
    except OSError:
        pass
    pj = {}
    try:
        with open(os.path.join(CONTESTS, contest, "problem-judges.json")) as f:
            pj = json.load(f)
    except Exception:
        pj = {}
    _conf_cache[contest] = (prio, judges, pj)
    return _conf_cache[contest]


def allowed_hosts(pj, judges, problem):
    # intake_enqueue: tenta p, p com #→/, p com /→# no problem-judges.json; senão CONTEST_JUDGES
    for k in dict.fromkeys([problem, problem.replace("#", "/"), problem.replace("/", "#")]):
        v = pj.get(k)
        if v is not None:
            return v if isinstance(v, list) else []
    if judges:
        return [w for w in judges.split() if w]
    return []


def give_back(claim, orig):
    try:
        os.rename(claim, orig)
    except OSError:
        pass




def spool_names():
    """nomes RELATIVOS ao SPOOL, raiz + shards s<k>/ (JUDGED_SHARDS>1 particiona o spool
    em subdiretorios por hash(login) — ver lib/spool-shard.sh; drain com daemon parado
    precisa varrer TUDO)."""
    out = []
    subs = [""]
    try:
        subs += sorted(d for d in os.listdir(SPOOL)
                       if d.startswith("s") and d[1:].isdigit()
                       and os.path.isdir(os.path.join(SPOOL, d)))
    except OSError:
        pass
    for sub in subs:
        root = os.path.join(SPOOL, sub) if sub else SPOOL
        try:
            ns = os.listdir(root)
        except OSError:
            continue
        for n in ns:
            if n.startswith(".") or n.endswith(".tmp"):
                continue
            out.append(os.path.join(sub, n) if sub else n)
    return out


def queue_pending(contest, login, upto=""):
    """user_queue_pending (lib/users.sh): pendentes do history menos os segurados em review/<id>.json,
    contando só até a linha do envio `upto` (ordem do history = ordem de envio)."""
    hf = os.path.join(CONTESTS, contest, "users", login, "history")
    rd = os.path.join(CONTESTS, contest, "review")
    has_rd = os.path.isdir(rd)
    n = 0
    try:
        with open(hf, encoding="utf-8", errors="replace") as f:
            for ln in f:
                if not PENDING.search(ln):
                    continue
                sid = ln.rstrip("\n").rsplit(":", 1)[-1]
                if not (has_rd and sid and os.path.isfile(os.path.join(rd, sid + ".json"))):
                    n += 1
                if upto and sid == upto:
                    break
    except OSError:
        return 0
    return n


def deprio_delay(contest, sid, login, prio):
    """deprio_delay (judged.sh): prova/super com mais de DEPRIO_PENDING esperando => nome adiantado."""
    if prio not in ("prova", "super") or DEPRIO_PENDING <= 0 or DEPRIO_DELAY <= 0:
        return 0
    n = queue_pending(contest, login, sid)
    if n > DEPRIO_PENDING:
        print("spool-drain: deprio id=%s contest=%s login=%s pendentes=%d atraso=%ds"
              % (sid, contest, login, n, DEPRIO_DELAY), flush=True)
        try:
            d = os.path.join(CONTESTS, contest, "var")
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, "admin-audit.log"), "a") as o:
                o.write("%d\tjudged\tenvio-deprio\tid=%s login=%s pendentes=%d atraso=%ds\n"
                        % (int(time.time()), sid, login, n, DEPRIO_DELAY))
        except OSError:
            pass
        return DEPRIO_DELAY
    return 0


def process(base):
    orig = os.path.join(SPOOL, base)
    claim = os.path.join(SPOOL, os.path.dirname(base), ".pydrain-" + os.path.basename(base))
    try:
        os.rename(orig, claim)
    except OSError:
        return False  # o bash levou primeiro — ok
    try:
        with open(claim, "rb") as f:
            j = json.load(f)
        contest = j.get("contest") or ""
        login = j.get("login") or ""
        problem = j.get("problem_id") or ""
        lang = j.get("lang") or ""
        filename = j.get("filename") or "solution"
        code_b64 = j.get("code_b64") or ""
        sid = j.get("id") or ""
        if not (VALID.match(contest) and ".." not in contest
                and VALID.match(login) and sid and problem):
            give_back(claim, orig)
            return False
        prio, judges, pj = conf(contest)
        if code_b64:  # archive_source: decodifica p/ users/<login>/submissions/<id>.<lang>
            try:
                raw = base64.b64decode(code_b64)
                d = os.path.join(CONTESTS, contest, "users", login, "submissions")
                os.makedirs(d, exist_ok=True)
                dest = os.path.join(d, "%s.%s" % (sid, (lang or "txt").lower()))
                tmp = dest + ".tmp.py"
                with open(tmp, "wb") as o:
                    o.write(raw)
                os.replace(tmp, dest)
            except Exception:
                pass  # espelho do bash: decodificação ruim não arquiva, mas segue enfileirando
        ah = allowed_hosts(pj, judges, problem)
        job = {"id": sid, "contest": contest, "problem_id": problem, "login": login,
               "lang": lang, "filename": filename, "code_b64": code_b64,
               "priority": prio, "enqueued_at": int(time.time())}
        if ah:
            job["allowed_hosts"] = ah
        band = BANDS.get(prio, "080-lista-publica")
        bdir = os.path.join(QUEUE, band)
        os.makedirs(bdir, exist_ok=True)
        # atraso = nome adiantado na MESMA banda (q_enqueue do sched-lib.sh); enqueued_at segue real
        qbase = "%d_%s.json" % (int(time.time()) + deprio_delay(contest, sid, login, prio), sid)
        qtmp = os.path.join(bdir, "." + qbase + ".tmp")
        with open(qtmp, "w") as o:
            o.write(json.dumps(job, separators=(",", ":")))
        os.replace(qtmp, os.path.join(bdir, qbase))
        os.replace(claim, os.path.join(DONE, base))
        return True
    except Exception:
        give_back(claim, orig)
        return False


def main():
    done = 0
    idle_since = time.time()
    while True:
        try:
            names = spool_names()
        except OSError:
            time.sleep(1)
            continue
        subs = []
        for n in names:
            p = os.path.basename(n).split(":")
            if len(p) >= 7 and p[4] == "submit":
                subs.append(n)
        subs.sort()
        batch = subs[BUFFER_OLDEST:]
        if not batch:
            if time.time() - idle_since > IDLE_EXIT_S:
                print("spool-drain: ocioso %ds — saindo (drenados=%d)" % (IDLE_EXIT_S, done), flush=True)
                return
            time.sleep(0.5)
            continue
        idle_since = time.time()
        for n in batch:
            if process(n):
                done += 1
        print("spool-drain: %d drenados; %d elegíveis na volta" % (done, len(batch)), flush=True)
        time.sleep(0.2)


if __name__ == "__main__":
    main()
