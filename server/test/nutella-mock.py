#!/usr/bin/env python3
"""Mock do NutellaBoot 3 p/ os smokes do MOJ (stdlib pura).

É ESTRITO DE PROPÓSITO. O mock antigo respondia `200 {"ok":true}` a QUALQUER POST/PUT, e por
isso escondeu dois comandos quebrados do MOJ por semanas: o por-máquina ia a uma rota que não
existe (405) e o de frota ia sem `targets` (400). Aqui cada rota responde como o serviço real
respondeu em 21/09/2026 (conferido na imagem de teste 26tete, com chave admin e de serviço).

Credenciais (env):
  NB_MOCK_KEY      chave de ADMINISTRAÇÃO (default nb3a_mock) — faz tudo
  NB_MOCK_SKEY     chave de SERVIÇO (default nb3s_mock) — NÃO entra nas rotas de console
                   (/whoami, listar /site-images, POST /commands, webhooks → 401) nem em
                   GET /site-images/{i} (403); fora do glob de imagens → 403
  NB_MOCK_SIMAGES  globs de imagem da chave de serviço, separados por vírgula (default "*")
  NB_MOCK_NOLOTE   "1" (ou o arquivo <fixdir>/nolote) = o lote de samples não existe (404) —
                   exercita o fallback por máquina

Uso: nutella-mock.py <fixdir> <portfile>   (escuta em 127.0.0.1:0 e grava a porta)
Fixtures em <fixdir>:
  images.json                 GET /api/v1/site-images
  roster.<img>.json           GET|PUT …/site-images/<img>/roster            (o PUT regrava)
  machines.<img>.json         GET …/site-images/<img>/machines[?active_since=]
  samples.<img>.<mac>.json    GET …/machines/<mac>/samples  e, 1 por linha, no LOTE …/<img>/samples
  commands.json               GET …/site-images/<img>/commands (catálogo {allowed, blocked})
  bindings.<img>.json         estado dos vínculos (PUT/DELETE …/machines/<mac>/binding)
  webhooks.<img>.json         GET|PUT …/site-images/<img>/webhooks
Registros: posts.log (todo POST/PUT/DELETE ACEITO: {method,path,body}), rejected.log (os
recusados, com o status) e gets.log (GETs de samples/machines COM a query).
"""
import fnmatch, json, os, re, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

FIX = sys.argv[1]
PORTFILE = sys.argv[2]
KEY = os.environ.get("NB_MOCK_KEY", "nb3a_mock")
SKEY = os.environ.get("NB_MOCK_SKEY", "nb3s_mock")
SIMAGES = [g for g in os.environ.get("NB_MOCK_SIMAGES", "*").split(",") if g]
NOLOTE = os.environ.get("NB_MOCK_NOLOTE", "") == "1"
IMG = r"([\w.-]+)"
MAC = r"([\w:-]+)"


def _load(name, default=None):
    p = os.path.join(FIX, name)
    if not os.path.isfile(p):
        return default
    with open(p) as f:
        return json.load(f)


def _save(name, obj):
    with open(os.path.join(FIX, name), "w") as f:
        json.dump(obj, f)


def _log(name, obj):
    with open(os.path.join(FIX, name), "a") as f:
        f.write(json.dumps(obj) + "\n")


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, obj=None, ctype="application/json", raw=None):
        body = raw if raw is not None else (b"" if obj is None else json.dumps(obj).encode())
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    # -> "admin" | "service" | None (já respondeu 401)
    def _who(self):
        a = self.headers.get("Authorization", "")
        if a == "Bearer " + KEY:
            return "admin"
        if a == "Bearer " + SKEY:
            return "service"
        self._send(401, {"detail": "credencial ausente ou inválida"})
        return None

    def _console(self, who):
        """Rotas de console: a chave de serviço leva 401 (foi o que o serviço real respondeu)."""
        if who != "admin":
            self._send(401, {"detail": "credencial ausente ou inválida"})
            return False
        return True

    def _image_ok(self, who, img):
        if who == "service" and not any(fnmatch.fnmatch(img, g) for g in SIMAGES):
            self._send(403, {"detail": "chave de serviço sem acesso a esta imagem"})
            return False
        return True

    def _body(self):
        n = int(self.headers.get("Content-Length", "0") or 0)
        return self.rfile.read(n).decode("utf-8", "replace") if n else ""

    def _reject(self, code, detail, body=""):
        _log("rejected.log", {"method": self.command, "path": self.path.split("?")[0],
                              "status": code, "body": body})
        self._send(code, {"detail": detail})

    @staticmethod
    def _janela(d, since, until, limit):
        pts = [p for p in d.get("points", [])
               if (not since or p.get("t", 0) >= since) and (not until or p.get("t", 0) <= until)]
        nat = len(pts)
        if nat > limit:
            pts = [pts[round(i * (nat - 1) / (limit - 1))] for i in range(limit)] if limit > 1 else pts[-1:]
        dts = sorted(b["t"] - a["t"] for a, b in zip(d.get("points", []), d.get("points", [])[1:]))
        out = {"mac": d.get("mac"), "points": pts, "native_points": nat,
               "resampled": len(pts) < nat, "interval_s": (dts[len(dts) // 2] if dts else None),
               "since": since, "until": until, "truncated": bool(d.get("truncated", False))}
        return out

    def do_GET(self):
        who = self._who()
        if not who:
            return
        path, _, query = self.path.partition("?")
        q = dict(kv.split("=", 1) for kv in query.split("&") if "=" in kv)
        num = lambda k, d=0: float(q.get(k, d) or d)

        if path == "/api/v1/whoami":
            return self._console(who) and self._send(200, {"kind": "admin", "label": "mock"})
        if path == "/api/v1/site-images":
            return self._console(who) and self._send(200, _load("images.json", {"images": []}))
        m = re.fullmatch(rf"/api/v1/site-images/{IMG}", path)
        if m:
            if who == "service":      # a rota não tem escopo de serviço: 403
                return self._send(403, {"detail": "sem escopo"})
            img = next((i for i in _load("images.json", {"images": []})["images"] if i["id"] == m.group(1)), None)
            return self._send(200, img) if img else self._send(404, {"detail": "Not Found"})
        m = re.fullmatch(rf"/api/v1/site-images/{IMG}/roster", path)
        if m:
            if not self._image_ok(who, m.group(1)):
                return
            return self._send(200, _load(f"roster.{m.group(1)}.json", {"roster": []}))
        m = re.fullmatch(rf"/api/v1/site-images/{IMG}/machines", path)
        if m:
            if not self._image_ok(who, m.group(1)):
                return
            _log("gets.log", {"method": "GET", "path": self.path})
            d = _load(f"machines.{m.group(1)}.json")
            if d is None:
                return self._send(404, {"detail": "Not Found"})
            act = num("active_since")
            binds = _load(f"bindings.{m.group(1)}.json", {})
            ms = []
            for x in d.get("machines", []):
                if act and (x.get("last_seen") or 0) < act:
                    continue
                x = dict(x)
                if x.get("mac") in binds:
                    x["binding"] = binds[x["mac"]]
                ms.append(x)
            return self._send(200, {"machines": ms})
        m = re.fullmatch(rf"/api/v1/site-images/{IMG}/machines/{MAC}/samples", path)
        if m:
            if not self._image_ok(who, m.group(1)):
                return
            _log("gets.log", {"method": "GET", "path": self.path})
            d = _load(f"samples.{m.group(1)}.{m.group(2)}.json")
            if d is None:
                return self._send(404, {"detail": "Not Found"})
            return self._send(200, self._janela(d, num("since"), num("until"), int(num("limit", 400))))
        m = re.fullmatch(rf"/api/v1/site-images/{IMG}/samples", path)
        if m:
            if not self._image_ok(who, m.group(1)):
                return
            _log("gets.log", {"method": "GET", "path": self.path})
            if NOLOTE or os.path.exists(os.path.join(FIX, "nolote")):   # arquivo = liga/desliga sem reiniciar
                return self._send(404, {"detail": "Not Found"})
            img, act = m.group(1), num("active_since")
            seen = {x.get("mac"): (x.get("last_seen") or 0)
                    for x in (_load(f"machines.{img}.json", {}) or {}).get("machines", [])}
            linhas = []
            for fn in sorted(os.listdir(FIX)):
                mm = re.fullmatch(rf"samples\.{re.escape(img)}\.{MAC}\.json", fn)
                if not mm or (act and seen.get(mm.group(1), 0) < act):
                    continue
                linhas.append(json.dumps(self._janela(_load(fn), num("since"), num("until"),
                                                      int(num("limit", 400))), separators=(",", ":")))
            return self._send(200, ctype="application/x-ndjson",
                              raw=("\n".join(linhas) + ("\n" if linhas else "")).encode())
        m = re.fullmatch(rf"/api/v1/site-images/{IMG}/commands", path)
        if m:
            if not self._image_ok(who, m.group(1)):
                return
            return self._send(200, _load("commands.json", {"allowed": [], "blocked": {}}))
        m = re.fullmatch(rf"/api/v1/site-images/{IMG}/bindings", path)
        if m:
            if not self._image_ok(who, m.group(1)):
                return
            b = _load(f"bindings.{m.group(1)}.json", {})
            return self._send(200, {"bindings": [dict(v, mac=k) for k, v in b.items()]})
        m = re.fullmatch(rf"/api/v1/site-images/{IMG}/webhooks", path)
        if m:
            if not self._console(who):
                return
            w = _load(f"webhooks.{m.group(1)}.json", {"webhooks": []})
            return self._send(200, {"webhooks": [dict(x, secret="***") for x in w["webhooks"]]})
        # o caminho do long-poll da MÁQUINA: só chave de máquina entra (aqui, ninguém)
        if re.fullmatch(rf"/api/v1/site-images/{IMG}/machines/{MAC}/commands", path):
            return self._send(401, {"detail": "credencial ausente ou inválida"})
        self._send(404, {"detail": "Not Found"})

    def _write(self):
        who = self._who()
        if not who:
            return
        path = self.path.split("?")[0]
        body = self._body()
        try:
            j = json.loads(body) if body else {}
        except ValueError:
            return self._reject(400, "JSON inválido", body)
        ok = lambda obj, code=200: (_log("posts.log", {"method": self.command, "path": path, "body": body}),
                                    self._send(code, obj))

        # ⚠ NÃO EXISTE POST de comando por máquina: o caminho só tem o GET do long-poll
        if re.fullmatch(rf"/api/v1/site-images/{IMG}/machines/{MAC}/commands", path):
            return self._reject(405, "Method Not Allowed", body)
        if path == "/api/v1/commands" and self.command == "POST":
            if who != "admin":
                return self._reject(401, "credencial ausente ou inválida", body)
            if not isinstance(j.get("targets"), dict) or not j["targets"]:
                return self._reject(400, "esperava targets: {sede: 'all' | [macs]}", body)
            return ok({"command": j.get("command"), "results": {k: {"machines": 1} for k in j["targets"]}})
        m = re.fullmatch(rf"/api/v1/site-images/{IMG}/commands", path)
        if m and self.command == "POST":
            img = m.group(1)
            if not self._image_ok(who, img):
                return
            cat = _load("commands.json", {"allowed": [], "blocked": {}})
            cmd = j.get("command", "")
            if cmd not in cat.get("allowed", []):
                return self._reject(400, f"comando não permitido: {cmd}", body)
            if cmd in cat.get("blocked", {}):
                return self._reject(403, f"{cmd}: {cat['blocked'][cmd]} está bloqueado pela organização da maratona", body)
            macs = [x.get("mac") for x in (_load(f"machines.{img}.json", {}) or {}).get("machines", [])]
            alvo = j.get("target", "all")
            alvo = macs if alvo == "all" else [str(x).lower().replace(":", "-") for x in (alvo or [])]
            if not alvo:
                return self._reject(400, "nenhuma máquina alvo", body)
            return ok({"command_id": "mock%06d" % (int(time.time()) % 1000000), "machines": len(alvo)})
        m = re.fullmatch(rf"/api/v1/site-images/{IMG}/roster", path)
        if m and self.command == "PUT":
            if not self._image_ok(who, m.group(1)):
                return
            r = j.get("roster")
            if not isinstance(r, list):
                return self._reject(400, "esperava roster: [...]", body)
            _save(f"roster.{m.group(1)}.json", {"roster": r})
            return ok({"ok": True, "entries": len(r)})
        m = re.fullmatch(rf"/api/v1/site-images/{IMG}/machines/{MAC}/binding", path)
        if m:
            img, mac = m.group(1), m.group(2).lower().replace(":", "-")
            if not self._image_ok(who, img):
                return
            b = _load(f"bindings.{img}.json", {})
            if self.command == "DELETE":
                b.pop(mac, None)
                _save(f"bindings.{img}.json", b)
                return ok(None, 204)
            uid = j.get("user_id")
            ros = [e.get("user_id") for e in _load(f"roster.{img}.json", {"roster": []})["roster"]]
            if uid and uid not in ros:
                return self._reject(404, f"user_id {uid} não está no roster desta imagem", body)
            v = {"bound_at": time.time(), "by": who, "source": j.get("source") or ("service:mock" if who == "service" else "console"),
                 "user_id": uid, "seat": j.get("seat", "")}
            if j.get("at") is not None:
                v["client_at"] = float(j["at"])
            if j.get("boot_id"):
                v["boot_id"] = str(j["boot_id"])
            b[mac] = v
            _save(f"bindings.{img}.json", b)
            return ok(v)
        m = re.fullmatch(rf"/api/v1/site-images/{IMG}/webhooks", path)
        if m and self.command == "PUT":
            if who != "admin":
                return self._reject(401, "credencial ausente ou inválida", body)
            w = j.get("webhooks")
            if not isinstance(w, list):
                return self._reject(400, "esperava webhooks: [...]", body)
            _save(f"webhooks.{m.group(1)}.json", {"webhooks": w})
            return ok({"ok": True, "webhooks": [dict(x, secret="***") for x in w]})
        self._reject(404, "Not Found", body)

    do_POST = _write
    do_PUT = _write
    do_DELETE = _write


srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
with open(PORTFILE, "w") as f:
    f.write(str(srv.server_address[1]))
srv.serve_forever()
