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
import gzip

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
    # MISSING = arquivo ausente (v2 vazio: tudo automático); INVALID = ilegível (segura tudo)
    try:
        with open(os.path.join(CONTESTS, c, "auto-verdicts.json")) as f:
            rules = json.load(f)
    except FileNotFoundError:
        rules = MISSING
    except Exception:
        rules = INVALID
    _conf[c] = (manual, rules)
    return _conf[c]


# ---- o que vai para revisão: ESPELHO de lib/review-rules.sh (rr_hold) — mexeu lá, mexa aqui ----
# (smoke-review-rules.sh compara os dois caso a caso). Na dúvida este lado SEGURA: segurar aqui só
# deixa o item no spool para o bash tratar; liberar o que o bash seguraria vazaria o veredicto.
MISSING = object()
INVALID = object()
CLASSES = ("Accepted", "Wrong Answer", "Time Limit Exceeded", "Memory Limit Exceeded",
           "Runtime Error", "Compilation Error")


def _alt(v, d):  # o `//` do jq: null/false caem no default
    return d if v is None or v is False else v


def _lang(l):
    l = str(l).lower()
    return "py" if l in ("py2", "py3") else ("cpp" if l in ("cc", "cxx", "c++", "hpp") else ("c" if l == "h" else l))


def _is_v2(r):
    v = _alt(r.get("version"), 1)
    if isinstance(v, bool):
        return False
    try:
        return float(v) >= 2
    except (TypeError, ValueError):
        return False


def rules_hold(r, cid, lang, v):
    """True = vai para REVISÃO."""
    if r is MISSING:
        return v not in CLASSES
    if r is INVALID or not isinstance(r, dict):
        return True
    c2 = cid.replace("/", "#")
    if _is_v2(r):
        if v not in CLASSES:
            return True
        langs = _alt(r.get("langs"), [])
        langs = list(langs.values()) if isinstance(langs, dict) else (langs if isinstance(langs, list) else [])
        l = _lang(lang)
        m = []
        for x in langs:
            if not isinstance(x, dict):
                continue
            vs = _alt(x.get("verdicts"), [])
            if not isinstance(vs, list) or v not in vs:
                continue
            if _lang(_alt(x.get("lang"), "")) != l:
                continue
            if _alt(x.get("problem"), "*") not in (cid, c2, "*"):
                continue
            m.append(x)
        sp = [x for x in m if _alt(x.get("problem"), "*") != "*"]
        w = sp or m
        if w:
            return any(_alt(x.get("to"), "review") != "auto" for x in w)
        rv = _alt(r.get("review"), {})
        if not isinstance(rv, dict):
            return True
        lst = _alt(rv.get(cid), None)
        if lst is None:
            lst = _alt(rv.get(c2), [])
        return isinstance(lst, list) and v in lst
    # v1 (opt-in): o que NÃO está listado vai para revisão
    m = _alt(r.get(cid), None)
    if m is None:
        m = _alt(r.get(c2), {})
    if not isinstance(m, dict):
        return True
    a, b = _alt(m.get(lang.lower()), []), _alt(m.get("*"), [])
    if not isinstance(a, list) or not isinstance(b, list):
        return True
    return v not in (a + b)


def should_hold(c, login, prob, lang, verdict, vcanon):
    manual, rules = contest_cfg(c)
    if not manual:
        return False
    if login.endswith(ROLE_SUFFIX):
        return False
    if verdict in TRANSIENT:
        return False
    return rules_hold(rules, prob, lang, vcanon)




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
            # mojlog em repouso e GZIP (espelho do write_report_gz do bash, 2026-09-16)
            with gzip.open(mt, "wb", compresslevel=6) as o:
                o.write(raw)
            os.replace(mt, os.path.join(mdir, "%s.html.gz" % sid))
        except Exception:
            pass               # espelho do bash: report ruim não bloqueia o veredicto
    res = {k: v for k, v in j.items() if k != "report_html_b64"}
    res.setdefault("login", login)
    res.setdefault("problem_id", prob)
    res["report_html"] = "mojlog/%s.html.gz" % sid
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
    # done/ sem o report_html_b64 (o mojlog ja esta no store): grava o `res` enxuto e remove o gordo
    dt = os.path.join(DONE, "." + os.path.basename(base) + ".tmp")
    try:
        with open(dt, "w") as o:
            o.write(json.dumps(res, separators=(",", ":")))
        os.replace(dt, os.path.join(DONE, os.path.basename(base)))
        os.unlink(path)
    except OSError:
        os.replace(path, os.path.join(DONE, os.path.basename(base)))
    return ("ok", c, login)


def main():
    dirty = set()
    affected = set()
    ok = skip = 0
    t0 = time.time()
    while True:
        names = [n for n in spool_names()
                 if os.path.basename(n).split(":")[4:5] == ["result"]]
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
