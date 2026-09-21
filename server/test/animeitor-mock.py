#!/usr/bin/env python3
"""animeitor-mock.py <dir> <portfile> — mock ESTRITO da API interna do Animeitor 2.1.0.

Escrito a partir do OpenAPI do serviço (https://animeitor.naquadah.com.br/internal/openapi.json,
lido em 21/09/2026) e conferido contra o servidor real num evento de teste. Lição do nutellaboot:
mock que aceita qualquer coisa esconde bug — este recusa o que o serviço recusa:

  · sem HTTP Basic (usuário:token de AN_MOCK_USER/AN_MOCK_TOKEN)      → 401 + WWW-Authenticate
  · POST de recurso que já existe                                      → 409 conflict
  · filho sem pai (contest sem evento, site sem contest)               → 404 not_found
  · PUT é SUBSTITUIÇÃO TOTAL: campo opcional omitido volta ao default  (salt → null!)
  · PATCH vazio ou com campo desconhecido, ou null em campo obrigatório → 400
  · regex inválida em `codes`                                          → 400 invalid_regex
  · runs: time desconhecido = IGNORADO com warning unknown_team; problema desconhecido de time
    conhecido = 400 invalid_value no lote INTEIRO; reenvio idêntico não conta em `updated`
  · remover time/problema com runs → 409 (time: ?keep_runs=true passa)
  · nome do corpo ≠ nome do caminho → 400

Envelope: {"data":…[, "warnings":[…]]} | {"errors":[{code,message}]}. 204 sem corpo.
Estado em <dir>/state.json (regravado a cada escrita); <dir>/requests.log = uma linha JSON por
requisição (método, caminho, query, corpo) — é por ele que o smoke conta requests e prova que a
credencial e o PUT não aparecem. Rotas públicas mínimas: /api/events e …/contests/{c}/contest.
"""
import base64, json, os, re, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, unquote

FIX, PORTFILE = sys.argv[1], sys.argv[2]
USER = os.environ.get("AN_MOCK_USER", "moj")
TOKEN = os.environ.get("AN_MOCK_TOKEN", "tok-mock-123")
LOCK = threading.Lock()
STATE = {"events": {}}          # events[e] = {state, contests:{c:{config, sites:{s:config}}}, runs:{id:run}}


def _save():
    with open(os.path.join(FIX, "state.json"), "w") as f:
        json.dump(STATE, f)


def _log(entry):
    with open(os.path.join(FIX, "requests.log"), "a") as f:
        f.write(json.dumps(entry) + "\n")


class Err(Exception):
    def __init__(self, status, code, msg):
        self.status, self.code, self.msg = status, code, msg


def _regexes(codes):
    if not isinstance(codes, list) or not all(isinstance(c, str) for c in codes):
        raise Err(400, "invalid_value", "codes deve ser lista de strings")
    for c in codes:
        # dialeto Rust: sem lookaround nem backreference
        if re.search(r"\(\?[=!<]|\\[1-9]", c):
            raise Err(400, "invalid_regex", f"regex inválida: {c}")
        try:
            re.compile(c)
        except re.error:
            raise Err(400, "invalid_regex", f"regex inválida: {c}")


EVENT_REQ = ["name", "problems", "teams", "score_freeze_time_seconds", "penalty_seconds"]
EVENT_FIELDS = EVENT_REQ + ["salt", "time_seconds"]
CONTEST_FIELDS = ["name", "codes", "ouro", "prata", "bronze", "style", "photo_url_format", "sound_url_format", "salt"]
CONTEST_DEF = {"ouro": 1, "prata": 2, "bronze": 3, "style": None, "photo_url_format": None, "sound_url_format": None, "salt": None}
SITE_FIELDS = ["name", "codes", "salt"]
NULLABLE = {"salt", "style", "photo_url_format", "sound_url_format"}


def _check_teams(teams):
    if not isinstance(teams, list):
        raise Err(400, "invalid_value", "teams")
    seen = set()
    for t in teams:
        if not isinstance(t, dict) or set(t) != {"login", "escola", "nome"} or not t["login"]:
            raise Err(400, "invalid_value", "team precisa de login, escola, nome")
        if t["login"] in seen:
            raise Err(400, "invalid_value", "login repetido")
        seen.add(t["login"])


def _full(body, fields, req, defaults, name):
    if not isinstance(body, dict):
        raise Err(400, "invalid_json", "esperava objeto")
    for k in body:
        if k not in fields:
            raise Err(400, "invalid_value", f"campo desconhecido: {k}")
    for k in req:
        if k not in body or body[k] is None:
            raise Err(400, "missing_field", k)
    if body.get("name") not in (name, "") or (body.get("name") == "" and "codes" not in req):
        raise Err(400, "invalid_value", "name tem de ser igual ao do caminho")
    out = dict(defaults)
    out.update(body)
    out["name"] = name
    return out


def _patch(cur, body, fields, req):
    if not isinstance(body, dict) or not body:
        raise Err(400, "invalid_value", "patch vazio")
    for k, v in body.items():
        if k not in fields:
            raise Err(400, "invalid_value", f"campo desconhecido: {k}")
        if v is None and k not in NULLABLE:
            raise Err(400, "invalid_value", f"{k} não aceita null")
    if "name" in body and body["name"] != cur["name"]:
        raise Err(400, "invalid_value", "name é imutável")
    out = dict(cur)
    out.update(body)
    return out


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, status, obj=None, extra=None):
        body = b"" if obj is None else json.dumps(obj).encode()
        self.send_response(status)
        if obj is not None:
            self.send_header("Content-Type", "application/json")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _auth(self):
        h = self.headers.get("Authorization", "")
        if h.startswith("Basic "):
            try:
                u, _, t = base64.b64decode(h[6:]).decode().partition(":")
                return u == USER and t == TOKEN
            except Exception:
                return False
        return False

    def _handle(self):
        u = urlparse(self.path)
        parts = [unquote(p) for p in u.path.split("/") if p]
        q = parse_qs(u.query)
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        _log({"m": self.command, "path": u.path, "q": u.query, "body": raw.decode("utf-8", "replace")[:400], "len": n})
        if parts[:1] == ["api"]:
            return self._public(parts[1:])
        if parts[:1] != ["internal"]:
            return self._send(404, {"errors": [{"code": "not_found", "message": "rota"}]})
        if not self._auth():
            return self._send(401, {"errors": [{"code": "unauthorized", "message": "credencial"}]}, {"WWW-Authenticate": "Basic"})
        body = None
        if raw:
            try:
                body = json.loads(raw)
            except ValueError:
                return self._send(400, {"errors": [{"code": "invalid_json", "message": "json"}]})
        try:
            with LOCK:
                r = self._internal(parts[1:], q, body)
                _save()
        except Err as e:
            return self._send(e.status, {"errors": [{"code": e.code, "message": e.msg}]})
        status, data, warnings = r
        if status == 204:
            return self._send(204)
        env = {"data": data}
        if warnings:
            env["warnings"] = warnings
        self._send(status, env)

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = _handle

    # ---------------------------------------------------------------- público (mínimo) ----------
    def _public(self, p):
        ev = STATE["events"]
        if p == ["events"]:
            return self._send(200, {"data": sorted(ev)})
        if len(p) == 5 and p[0] == "events" and p[2] == "contests" and p[4] == "contest":
            e = ev.get(p[1])
            if not e or p[3] not in e["contests"]:
                return self._send(404, {"errors": [{"code": "not_found", "message": "x"}]})
            if e["state"].get("time_seconds", 0) < 0:
                return self._send(403, {"errors": [{"code": "not_started", "message": "x"}]})
            codes = e["contests"][p[3]]["config"]["codes"]
            teams = [t for t in e["state"]["teams"] if any(re.search(c, t["login"]) for c in codes)]
            return self._send(200, {"data": {"event": p[1], "contest": p[3], "problems": e["state"]["problems"], "teams": teams,
                                             "time_seconds": e["state"].get("time_seconds", 0)}})
        return self._send(404, {"errors": [{"code": "not_found", "message": "rota"}]})

    # ---------------------------------------------------------------- interno -------------------
    def _internal(self, p, q, body):
        ev = STATE["events"]
        m = self.command

        def event(name):
            if name not in ev:
                raise Err(404, "not_found", f"evento {name}")
            return ev[name]

        if p == ["events"] and m == "GET":
            return 200, sorted(ev), None
        if len(p) == 2 and p[0] == "events":
            name = p[1]
            if m == "POST":
                if name in ev:
                    raise Err(409, "conflict", "evento já existe")
                st = _full(body, EVENT_FIELDS, EVENT_REQ, {"salt": None, "time_seconds": 0}, name)
                _check_teams(st["teams"])
                ev[name] = {"state": st, "contests": {}, "runs": {}}
                return 201, st, None
            e = event(name)
            if m == "GET":
                return 200, e["state"], None
            if m == "PUT":
                st = _full(body, EVENT_FIELDS, EVENT_REQ, {"salt": None, "time_seconds": 0}, name)
                _check_teams(st["teams"])
                e["state"] = st
                return 200, st, None
            if m == "PATCH":
                st = _patch(e["state"], body, EVENT_FIELDS, EVENT_REQ)
                if "teams" in body:
                    _check_teams(st["teams"])
                    gone = {t["login"] for t in e["state"]["teams"]} - {t["login"] for t in st["teams"]}
                    if any(r["team_login"] in gone for r in e["runs"].values()) and q.get("keep_runs") != ["true"]:
                        raise Err(409, "conflict", "time com runs (use keep_runs=true)")
                if "problems" in body:
                    if len(set(st["problems"])) != len(st["problems"]):
                        raise Err(400, "invalid_value", "problema repetido")
                    if any(r["prob"] not in st["problems"] for r in e["runs"].values()):
                        raise Err(409, "conflict", "problema com runs")
                e["state"] = st
                return 200, st, None
            if m == "DELETE":
                del ev[name]
                return 204, None, None
        if len(p) == 3 and p[0] == "events":
            e = event(p[1])
            if p[2] == "contests" and m == "GET":
                return 200, [c["config"] for c in e["contests"].values()], None
            if p[2] == "time" and m == "PATCH":
                if not isinstance(body, dict) or set(body) != {"time_seconds"} or not isinstance(body["time_seconds"], int):
                    raise Err(400, "invalid_value", "time_seconds inteiro")
                e["state"]["time_seconds"] = body["time_seconds"]
                return 200, {"time_seconds": body["time_seconds"]}, None
            if p[2] == "revelation_urls" and m == "GET":
                out = []
                for cn in sorted(e["contests"]):
                    for sn in sorted(e["contests"][cn]["sites"]):
                        salt = "|".join(str(x) for x in (e["state"].get("salt"), e["contests"][cn]["config"].get("salt"),
                                                         e["contests"][cn]["sites"][sn].get("salt")))
                        key = base64.urlsafe_b64encode(f"{p[1]}/{cn}/{sn}/{salt}".encode()).decode().rstrip("=")
                        out.append({"contest": cn, "site": sn, "url": f"https://telao.exemplo/animeitor/{p[1]}/{cn}/?secret={key}&sede={sn}"})
                return 200, out, None
            if p[2] == "runs" and m == "DELETE":
                e["runs"] = {}
                return 204, None, None
            if p[2] == "runs" and m == "POST":
                if not isinstance(body, dict) or set(body) != {"runs"} or not isinstance(body["runs"], list):
                    raise Err(400, "missing_field", "runs")
                logins = {t["login"] for t in e["state"]["teams"]}
                warn, ok = [], []
                for r in body["runs"]:
                    if not isinstance(r, dict) or set(r) != {"id", "team_login", "prob", "time_seconds", "answer"}:
                        raise Err(400, "invalid_value", "run malformada")
                    if not isinstance(r["id"], int) or not isinstance(r["time_seconds"], int) or r["answer"] not in ("Y", "N", "?", "X"):
                        raise Err(400, "invalid_value", "run: tipos")
                    if r["team_login"] not in logins:
                        warn.append({"code": "unknown_team", "message": f"run {r['id']} do time {r['team_login']} ignorada: o time não pertence ao evento"})
                        continue
                    if r["prob"] not in e["state"]["problems"]:
                        raise Err(400, "invalid_value", f"problema desconhecido: {r['prob']}")
                    ok.append(r)
                added = updated = 0
                for r in sorted(ok, key=lambda x: (x["time_seconds"], x["id"])):
                    k = str(r["id"])
                    if k not in e["runs"]:
                        added += 1
                    elif e["runs"][k] != r:
                        updated += 1
                    e["runs"][k] = r
                return 200, {"added": added, "updated": updated}, warn
        if len(p) == 5 and p[0] == "events" and p[2] == "contests" and p[4] == "sites" and m == "GET":
            e = event(p[1])
            if p[3] not in e["contests"]:
                raise Err(404, "not_found", "contest")
            return 200, list(e["contests"][p[3]]["sites"].values()), None
        if len(p) == 3 and p[0] == "contests":
            e = event(p[1])
            cn = p[2]
            if m == "POST":
                if cn in e["contests"]:
                    raise Err(409, "conflict", "contest já existe")
                cfg = _full(body, CONTEST_FIELDS, ["name", "codes"], CONTEST_DEF, cn)
                _regexes(cfg["codes"])
                e["contests"][cn] = {"config": cfg, "sites": {}}
                return 201, cfg, None
            if cn not in e["contests"]:
                raise Err(404, "not_found", "contest")
            c = e["contests"][cn]
            if m == "GET":
                return 200, c["config"], None
            if m == "PUT":
                cfg = _full(body, CONTEST_FIELDS, ["name", "codes"], CONTEST_DEF, cn)
                _regexes(cfg["codes"])
                c["config"] = cfg
                return 200, cfg, None
            if m == "PATCH":
                cfg = _patch(c["config"], body, CONTEST_FIELDS, ["name", "codes"])
                _regexes(cfg["codes"])
                c["config"] = cfg
                return 200, cfg, None
            if m == "DELETE":
                del e["contests"][cn]
                return 204, None, None
        if len(p) == 4 and p[0] == "sites":
            e = event(p[1])
            if p[2] not in e["contests"]:
                raise Err(404, "not_found", "contest")
            sites, sn = e["contests"][p[2]]["sites"], p[3]
            if m == "POST":
                if sn in sites:
                    raise Err(409, "conflict", "site já existe")
                cfg = _full(body, SITE_FIELDS, ["name", "codes"], {"salt": None}, sn)
                _regexes(cfg["codes"])
                sites[sn] = cfg
                return 201, cfg, None
            if sn not in sites:
                raise Err(404, "not_found", "site")
            if m == "GET":
                return 200, sites[sn], None
            if m == "PUT":
                cfg = _full(body, SITE_FIELDS, ["name", "codes"], {"salt": None}, sn)
                _regexes(cfg["codes"])
                sites[sn] = cfg
                return 200, cfg, None
            if m == "PATCH":
                cfg = _patch(sites[sn], body, SITE_FIELDS, ["name", "codes"])
                _regexes(cfg["codes"])
                sites[sn] = cfg
                return 200, cfg, None
            if m == "DELETE":
                del sites[sn]
                return 204, None, None
        if len(p) == 4 and p[0] in ("contests", "sites") or (len(p) == 5 and p[0] == "sites"):
            # …/salt: gera quando o corpo não traz um
            if p[-1] == "salt" and m == "POST":
                e = event(p[1])
                tgt = e["contests"][p[2]]["config"] if p[0] == "contests" else e["contests"][p[2]]["sites"][p[3]]
                tgt["salt"] = (body or {}).get("salt") or "gerado-pelo-mock"
                return 200, {"salt": tgt["salt"]}, None
        raise Err(404, "not_found", "rota")


srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
with open(PORTFILE, "w") as f:
    f.write(str(srv.server_address[1]))
srv.serve_forever()
