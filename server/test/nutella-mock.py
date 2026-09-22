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
  legacy                      (arquivo vazio) emula o serviço ANTERIOR a 21/09/2026: sem `code` nos erros,
                              401 p/ chave de serviço em /whoami e na lista, sem webhooks por entrada, sem
                              roster/{id}, sem bindings em lote, sem commands/{id}. Sem o arquivo = protocolo
                              NOVO (fase 1 — o que está em produção), conferido no serviço real em 21/09.
  bind503                     (arquivo vazio) faz o PUT do binding responder 503 — teste do retry
  bindslow                    (arquivo com N) atrasa o PUT do binding em N segundos — o login não pode esperar
  webhooks.<img>.json         GET|PUT …/site-images/<img>/webhooks
Registros: posts.log (todo POST/PUT/DELETE ACEITO: {method,path,body}), rejected.log (os
recusados, com o status) e gets.log (GETs de samples/machines COM a query).
"""
import fnmatch, json, os, re, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

FIX = sys.argv[1]
PORTFILE = sys.argv[2]
SSCOPES = os.environ.get("NB_MOCK_SSCOPES", "machines:read commands:write bindings:write roster:read roster:write webhooks:write alerts:write").split()
LEGACY = lambda: os.path.exists(os.path.join(FIX, "legacy"))
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

    def _send(self, code, obj=None, ctype="application/json", raw=None, headers=None):
        body = raw if raw is not None else (b"" if obj is None else json.dumps(obj).encode())
        self.send_response(code)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
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
        """Rotas de console: chave de serviço leva 403 console_only (antes de 21/09: 401 sem code)."""
        if who != "admin":
            if LEGACY():
                self._send(401, {"detail": "credencial ausente ou inválida"})
            else:
                self._send(403, {"detail": "esta rota é do console; chave de serviço não entra", "code": "console_only"})
            return False
        return True

    def _image_ok(self, who, img):
        if who == "service" and not any(fnmatch.fnmatch(img, g) for g in SIMAGES):
            self._send(403, {"detail": "sem acesso a esta imagem", "code": "image_out_of_scope"})
            return False
        return True

    def _body(self):
        n = int(self.headers.get("Content-Length", "0") or 0)
        return self.rfile.read(n).decode("utf-8", "replace") if n else ""

    def _reject(self, code, detail, body="", ecode=None, headers=None):
        _log("rejected.log", {"method": self.command, "path": self.path.split("?")[0],
                              "status": code, "body": body})
        obj = {"detail": detail}
        if ecode and not LEGACY():
            obj["code"] = ecode
        self._send(code, obj, headers=headers)

    def _bind_one(self, who, img, mac, j):
        """um vínculo; {ok, binding} ou {ok:false, code, detail}. `create_roster_entry` (protocolo novo) cria a
        entrada marcada source:"binding" quando o time não está no roster."""
        b = _load(f"bindings.{img}.json", {})
        uid = j.get("user_id")
        if not re.fullmatch(r"[0-9a-f]{2}(-[0-9a-f]{2}){5}", mac) or mac == "ff-ff-ff-ff-ff-ff":   # ff… = MAC reservado (teste)
            return {"ok": False, "code": "invalid_mac", "detail": "mac malformado"}
        rj = _load(f"roster.{img}.json", {"roster": []})
        ros = [e.get("user_id") for e in rj["roster"]]
        created = False
        if uid and uid not in ros:
            cre = j.get("create_roster_entry") if not LEGACY() else None
            if not cre:
                return {"ok": False, "code": "user_not_in_roster", "detail": f"user_id {uid} não está no roster desta imagem"}
            e = {"user_id": uid, "source": "binding", "seat": ""}
            if isinstance(cre, dict):
                e.update({k: cre.get(k, "") for k in ("name", "display_name", "organization", "country")})
            rj["roster"].append(e)
            _save(f"roster.{img}.json", rj)
            created = True
        v = {"bound_at": int(time.time()), "by": who, "source": j.get("source") or ("service:mock" if who == "service" else "console"),
             "user_id": uid, "seat": j.get("seat", "")}
        if j.get("at") is not None:
            v["client_at"] = int(float(j["at"]))
        if j.get("boot_id"):
            v["boot_id"] = str(j["boot_id"])
        if created:
            v["roster_entry_created"] = True
        b[mac] = v
        _save(f"bindings.{img}.json", b)
        return {"ok": True, "binding": v}

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
            if who == "service" and not LEGACY():
                imgs = [i["id"] for i in _load("images.json", {"images": []})["images"] if any(fnmatch.fnmatch(i["id"], g) for g in SIMAGES)]
                return self._send(200, {"kind": "service", "name": "mock-svc", "label": "mock-svc", "scopes": SSCOPES, "image_globs": SIMAGES, "images": imgs})
            return self._console(who) and self._send(200, {"kind": "admin", "label": "mock"})
        if path == "/api/v1/site-images":
            if who == "service" and not LEGACY():
                imgs = [dict(i, machines_total=len(_load(f"machines.{i['id']}.json", {"machines": []})["machines"]))
                        for i in _load("images.json", {"images": []})["images"] if any(fnmatch.fnmatch(i["id"], g) for g in SIMAGES)]
                return self._send(200, {"images": imgs})
            return self._console(who) and self._send(200, _load("images.json", {"images": []}))
        if path == "/api/v1/events/types" and not LEGACY():
            return self._send(200, {"events": ["machine.first_seen", "machine.rebooted", "machine.online", "machine.offline", "machine.status", "machine.locked", "machine.unlocked", "machine.bound", "machine.unbound", "command.sent", "command.acked", "command.expired", "config.updated", "alert.raised", "alert.dismissed", "webhook.test"], "error_codes": ["console_only", "insufficient_scope", "image_out_of_scope", "user_not_in_roster", "invalid_mac", "image_not_found", "rate_limited"]})
        m = re.fullmatch(rf"/api/v1/site-images/{IMG}/commands/([A-Za-z0-9_-]+)", path)
        if m and not LEGACY():
            if not self._image_ok(who, m.group(1)):
                return
            cmds = _load(f"cmdstatus.{m.group(1)}.json", {})
            c = cmds.get(m.group(2))
            if not c:
                return self._reject(404, "comando desconhecido", ecode="command_not_found")
            return self._send(200, c)
        m = re.fullmatch(rf"/api/v1/site-images/{IMG}", path)
        if m:
            if who == "service":
                if LEGACY():      # antes de 21/09 a rota não tinha escopo de serviço: 403
                    return self._send(403, {"detail": "sem escopo"})
                if not self._image_ok(who, m.group(1)):
                    return
                img = next((i for i in _load("images.json", {"images": []})["images"] if i["id"] == m.group(1)), None)
                return self._send(200, dict(img or {"id": m.group(1)}, machines_total=len(_load(f"machines.{m.group(1)}.json", {"machines": []})["machines"])))
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
            _log("gets.log", {"method": "GET", "path": self.path, "accept_encoding": self.headers.get("Accept-Encoding", "")})
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
            _log("gets.log", {"method": "GET", "path": self.path, "accept_encoding": self.headers.get("Accept-Encoding", "")})
            d = _load(f"samples.{m.group(1)}.{m.group(2)}.json")
            if d is None:
                return self._send(404, {"detail": "Not Found"})
            return self._send(200, self._janela(d, num("since"), num("until"), int(num("limit", 400))))
        m = re.fullmatch(rf"/api/v1/site-images/{IMG}/samples", path)
        if m:
            if not self._image_ok(who, m.group(1)):
                return
            _log("gets.log", {"method": "GET", "path": self.path, "accept_encoding": self.headers.get("Accept-Encoding", "")})
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
            cid = "mock%06d" % (int(time.time() * 1000) % 1000000)
            if not LEGACY():   # status do comando (GET …/commands/{id}): 1ª máquina executou, o resto pendente
                cs = _load(f"cmdstatus.{img}.json", {})
                cs[cid] = {"command_id": cid, "command": cmd, "by": who, "created_at": int(time.time()), "expires_at": int(time.time()) + 600,
                           "machines": len(alvo), "summary": {"acked": 1 if alvo else 0, "pending": max(len(alvo) - 1, 0), "expired": 0},
                           "targets": [{"mac": mm, "state": ("acked" if i == 0 else "pending")} for i, mm in enumerate(alvo)]}
                _save(f"cmdstatus.{img}.json", cs)
            return ok({"command_id": cid, "machines": len(alvo)})
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
            slow = os.path.join(FIX, "bindslow")                  # serviço LENTO: o arquivo traz os segundos
            if os.path.exists(slow):
                try:
                    time.sleep(float(open(slow).read().strip() or 0))
                except ValueError:
                    pass
            if os.path.exists(os.path.join(FIX, "bind503")):     # serviço fora do ar (p/ o teste do retry)
                return self._reject(503, "indisponível", body)
            if os.path.exists(os.path.join(FIX, "bind429")):     # rate limit com Retry-After (protocolo novo)
                os.remove(os.path.join(FIX, "bind429"))
                return self._reject(429, "devagar", body, ecode="rate_limited", headers={"Retry-After": "1"})
            b = _load(f"bindings.{img}.json", {})
            if self.command == "DELETE":
                b.pop(mac, None)
                _save(f"bindings.{img}.json", b)
                return ok(None, 204)
            r = self._bind_one(who, img, mac, j)
            if r.get("ok"):
                return ok(r["binding"])
            return self._reject(404, r["detail"], body, ecode=r["code"])
        # ---- protocolo NOVO (≥ 21/09/2026) ----------------------------------------------------------
        if not LEGACY():
            m = re.fullmatch(rf"/api/v1/site-images/{IMG}/webhooks", path)
            if m and self.command == "POST":
                img = m.group(1)
                if not self._image_ok(who, img):
                    return
                if who == "service" and "webhooks:write" not in SSCOPES:
                    return self._reject(403, "falta escopo", body, ecode="insufficient_scope")
                url, sec, ev = j.get("url", ""), j.get("secret", ""), j.get("events", [])
                if not url.startswith(("https://", "http://")):
                    return self._reject(400, "url", body, ecode="invalid_url")
                if len(sec) < 16:
                    return self._reject(400, "segredo curto", body, ecode="invalid_secret")
                owner = "service:mock-svc" if who == "service" else "console"
                w = _load(f"webhooks.{img}.json", {"webhooks": []})
                mine = [x for x in w["webhooks"] if x.get("owner") == owner and x.get("url") == url]
                if mine:
                    mine[0].update({"secret": sec, "events": ev})
                    _save(f"webhooks.{img}.json", w)
                    return ok(dict(mine[0], secret="***", created=False), 200)
                if who == "service" and len([x for x in w["webhooks"] if x.get("owner") == owner]) >= 5:
                    return self._reject(400, "limite", body, ecode="webhook_limit")
                e = {"id": "wh_" + os.urandom(6).hex(), "url": url, "secret": sec, "events": ev, "owner": owner, "created_at": int(time.time())}
                w["webhooks"].append(e)
                _save(f"webhooks.{img}.json", w)
                return ok(dict(e, secret="***", created=True), 201)
            m = re.fullmatch(rf"/api/v1/site-images/{IMG}/webhooks/(wh_[0-9a-f]+)", path)
            if m and self.command in ("DELETE", "PUT"):
                img, wid = m.group(1), m.group(2)
                if not self._image_ok(who, img):
                    return
                owner = "service:mock-svc" if who == "service" else "console"
                w = _load(f"webhooks.{img}.json", {"webhooks": []})
                mine = [x for x in w["webhooks"] if x.get("id") == wid and (who == "admin" or x.get("owner") == owner)]
                if not mine:
                    return self._reject(404, "webhook", body, ecode="webhook_not_found")
                if self.command == "DELETE":
                    w["webhooks"] = [x for x in w["webhooks"] if x.get("id") != wid]
                    _save(f"webhooks.{img}.json", w)
                    return ok(None, 204)
                mine[0].update({k: j[k] for k in ("secret", "events", "url") if k in j})
                _save(f"webhooks.{img}.json", w)
                return ok(dict(mine[0], secret="***"))
            m = re.fullmatch(rf"/api/v1/site-images/{IMG}/roster", path)
            if m and self.command == "POST":
                img = m.group(1)
                if not self._image_ok(who, img):
                    return
                if not j.get("user_id"):
                    return self._reject(400, "user_id", body, ecode="invalid_roster_entry")
                rj = _load(f"roster.{img}.json", {"roster": []})
                cur = [e for e in rj["roster"] if e.get("user_id") == j["user_id"]]
                e = {"user_id": j["user_id"], "name": j.get("name", ""), "display_name": j.get("display_name", ""),
                     "organization": j.get("organization", {}), "country": j.get("country", ""), "seat": j.get("seat", "")}
                if cur:
                    cur[0].update(e)
                else:
                    rj["roster"].append(e)
                _save(f"roster.{img}.json", rj)
                return ok({"ok": True, "created": not cur, "entry": e})
            m = re.fullmatch(rf"/api/v1/site-images/{IMG}/roster/([^/]+)", path)
            if m and self.command == "DELETE":
                img = m.group(1)
                if not self._image_ok(who, img):
                    return
                rj = _load(f"roster.{img}.json", {"roster": []})
                rj["roster"] = [e for e in rj["roster"] if e.get("user_id") != m.group(2)]
                _save(f"roster.{img}.json", rj)
                return ok(None, 204)
            m = re.fullmatch(rf"/api/v1/site-images/{IMG}/bindings", path)
            if m and self.command == "PUT":
                img = m.group(1)
                if not self._image_ok(who, img):
                    return
                lst = j.get("bindings")
                if not isinstance(lst, list) or len(lst) > 1000:
                    return self._reject(400, "bindings: lista de até 1000", body, ecode="bad_request")
                res = []
                for it in lst:
                    it = dict(it)
                    if "create_roster_entry" not in it and j.get("create_roster_entry"):
                        it["create_roster_entry"] = j["create_roster_entry"]
                    r = self._bind_one(who, img, str(it.get("mac", "")).lower().replace(":", "-"), it)
                    res.append(dict(mac=it.get("mac"), **r))
                return ok({"results": res, "bound": sum(1 for r in res if r["ok"]), "failed": sum(1 for r in res if not r["ok"])})
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
