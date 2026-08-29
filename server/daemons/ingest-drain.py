#!/usr/bin/env python3
# ingest-drain.py — ingestor de EMERGÊNCIA de results do spool (prova da Maratona 29/08:
# 2.300+ veredictos JULGADOS esperando a esteira serial do bash; times sem resposta).
#
# REGRA DE OURO: só roda com o daemon bash PARADO (systemctl --user stop moj-judged) — aí
# este processo é o ÚNICO escritor de history e não existe corrida nenhuma. Depois do dreno:
# recompute em massa de metrics (o caminho do deploy: .metrics-stamp velho + build.sh, ~46 s
# p/ 2.134 contas) substitui os milhares de recomputes individuais, e o daemon bash volta.
#
# Espelha ingest_result SÓ no caso feliz: result de contest válido, com linha no history,
# veredicto pleno e NÃO-segurável (should_hold==false). Tudo fora disso — _testrun, segurado
# p/ revisão, verdict transiente, history sem a linha — FICA NO SPOOL para o bash tratar
# canonicamente ao voltar. Este script NUNCA descarta, segura ou fabrica veredicto.
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
ASSIGNED = os.path.join(RUNDIR, "assigned")
RESULTS = os.path.join(RUNDIR, "results")
VALID = re.compile(r"^[A-Za-z0-9._-]+$")
ROLE_SUFFIX = (".admin", ".judge", ".cjudge", ".staff", ".cstaff", ".mon", ".animeitor")
TRANSIENT = {"Not Answered Yet", "On queue", "Running", ""}

_conf = {}


def contest_cfg(c):
    if c in _conf:
        return _conf[c]
    manual = False
    try:
        with open(os.path.join(CONTESTS, c, "conf"), encoding="utf-8", errors="replace") as f:
            for ln in f:
                s = ln.strip()
                if s.startswith("MANUAL_VERDICT="):
                    manual = s.split("=", 1)[1].strip().strip("'\"") == "1"
    except OSError:
        pass
    matrix = {}
    try:
        with open(os.path.join(CONTESTS, c, "auto-verdicts.json")) as f:
            matrix = json.load(f)
    except Exception:
        matrix = {}
    _conf[c] = (manual, matrix)
    return _conf[c]


def auto_allows(matrix, prob, lang, vcanon):
    m = matrix.get(prob) or matrix.get(prob.replace("/", "#")) or {}
    allowed = (m.get(lang.lower()) or []) + (m.get("*") or [])
    return vcanon in allowed


def should_hold(c, login, prob, lang, verdict, vcanon):
    manual, matrix = contest_cfg(c)
    if not manual:
        return False
    if login.endswith(ROLE_SUFFIX):
        return False
    if verdict in TRANSIENT:
        return False
    return not auto_allows(matrix, prob, lang, vcanon)


def process(base):
    path = os.path.join(SPOOL, base)
    try:
        with open(path, "rb") as f:
            j = json.load(f)
    except Exception:
        return "skip"          # JSON ruim: o bash tem o caminho canônico (Judge Error auditado)
    c = j.get("contest") or ""
    sid = j.get("id") or ""
    verdict = j.get("verdict") or "Judge Error"
    vcanon = j.get("verdict_canon") or verdict.split(",")[0]
    login = j.get("login") or ""
    host = j.get("host") or ""
    if c == "_testrun" or not (VALID.match(c) and ".." not in c and sid):
        return "skip"
    udir = os.path.join(CONTESTS, c, "users", login)
    hf = os.path.join(udir, "history")
    try:
        with open(hf, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return "skip"          # sem history local (login vazio/estranho): bash decide
    suffix = ":" + sid
    idx = None
    for i, ln in enumerate(lines):
        if ln.endswith(suffix):
            idx = i
            break
    if idx is None:
        return "skip"          # linha não está aqui (fallbacks do bash cobrem)
    parts = lines[idx].split(":")
    if len(parts) < 6:
        return "skip"
    tempo, prob, lang = parts[0], parts[1], parts[2]
    sub_epoch = parts[-2]
    if should_hold(c, login, prob, lang, verdict, vcanon):
        return "skip"          # segurável p/ revisão: fluxo do bash (write_review_item)
    # ---- caso feliz: history replace + mojlog + results + q_done -----------------
    lines[idx] = "%s:%s:%s:%s:%s:%s" % (tempo, prob, lang, verdict, sub_epoch, sid)
    tmp = hf + ".tmp.pying"
    with open(tmp, "w", encoding="utf-8") as o:
        o.write("\n".join(lines) + "\n")
    os.replace(tmp, hf)
    hb = j.get("report_html_b64")
    mdir = os.path.join(udir, "mojlog")
    if hb:
        try:
            os.makedirs(mdir, exist_ok=True)
            raw = base64.b64decode(hb)
            mt = os.path.join(mdir, ".%s.tmp" % sid)
            with open(mt, "wb") as o:
                o.write(raw)
            os.replace(mt, os.path.join(mdir, "%s.html" % sid))
        except Exception:
            pass               # espelho do bash: report ruim não bloqueia o veredicto
    res = {k: v for k, v in j.items() if k != "report_html_b64"}
    res.setdefault("login", login)
    res.setdefault("problem_id", prob)
    res["report_html"] = "mojlog/%s.html" % sid
    res["finalized_at"] = int(time.time())
    rdir = os.path.join(udir, "results")
    os.makedirs(rdir, exist_ok=True)
    rt = os.path.join(rdir, ".%s.tmp" % sid)
    with open(rt, "w") as o:
        o.write(json.dumps(res, separators=(",", ":")))
    os.replace(rt, os.path.join(rdir, "%s.json" % sid))
    try:
        os.makedirs(RESULTS, exist_ok=True)
        with open(os.path.join(RESULTS, "%s.json" % sid), "w") as o:
            o.write(json.dumps(res, separators=(",", ":")))
    except OSError:
        pass
    if host and VALID.match(host):
        adir = os.path.join(ASSIGNED, host)
        try:
            for n in os.listdir(adir):
                if n.endswith("_%s.json" % sid):
                    try:
                        os.unlink(os.path.join(adir, n))
                    except OSError:
                        pass
        except OSError:
            pass
    os.replace(path, os.path.join(DONE, base))
    return ("ok", c, login)


def main():
    dirty = set()
    affected = set()
    ok = skip = 0
    t0 = time.time()
    while True:
        names = [n for n in os.listdir(SPOOL)
                 if not n.startswith(".") and not n.endswith(".tmp")
                 and n.split(":")[4:5] == ["result"]]
        names.sort()
        todo = [n for n in names if n not in main.seen]
        if not todo:
            break
        for n in todo:
            main.seen.add(n)
            r = process(n)
            if isinstance(r, tuple):
                ok += 1
                dirty.add(r[1])
                affected.add((r[1], r[2]))
            else:
                skip += 1
            if (ok + skip) % 200 == 0:
                print("ingest-drain: ok=%d skip=%d (%.0fs)" % (ok, skip, time.time() - t0), flush=True)
    for c in dirty:
        try:
            with open(os.path.join(CONTESTS, c, "var", ".score-dirty"), "w"):
                pass
        except OSError:
            pass
    try:
        with open(os.path.join(RUNDIR, "ingest-affected.txt"), "w") as o:
            for c, u in sorted(affected):
                o.write("%s\t%s\n" % (c, u))
    except OSError:
        pass
    print("ingest-drain: FIM ok=%d skip=%d em %.0fs; contests sujos: %s"
          % (ok, skip, time.time() - t0, ",".join(sorted(dirty))), flush=True)


main.seen = set()

if __name__ == "__main__":
    main()
