#!/usr/bin/env python3
"""Mock do nutellaboot p/ o smoke-contest-nutella.sh (stdlib pura).

Serve fixtures de um diretório e REGISTRA todo POST/PUT em <dir>/posts.log
(uma linha JSON: {method, path, body}) — é assim que o smoke prova que o
comando/roster chegou com o shape certo. O GET de samples vai a <dir>/gets.log COM a
query string (prova do since/until da janela). Exige `Authorization: Bearer $NB_MOCK_KEY`
(401 sem ela — cobre o caminho de chave inválida).

Uso: nutella-mock.py <fixdir> <portfile>   (escuta em 127.0.0.1:0 e grava a porta)
Fixtures em <fixdir>:
  images.json                      -> GET /api/v1/site-images
  roster.<img>.json                -> GET /api/v1/site-images/<img>/roster
  machines.<img>.json              -> GET /api/v1/site-images/<img>/machines
  samples.<img>.<mac>.json         -> GET .../machines/<mac>/samples
  commands.json                    -> GET /api/v1/site-images/<img>/commands (catálogo)
"""
import json, os, re, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

FIX = sys.argv[1]
PORTFILE = sys.argv[2]
KEY = os.environ.get("NB_MOCK_KEY", "nb3a_mock")


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _auth(self):
        if self.headers.get("Authorization", "") != "Bearer " + KEY:
            self._send(401, {"detail": "credencial ausente ou inválida"})
            return False
        return True

    def _file(self, name):
        p = os.path.join(FIX, name)
        if not os.path.isfile(p):
            self._send(404, {"detail": "Not Found"})
            return
        with open(p) as f:
            data = json.load(f)
        self._send(200, data)

    def do_GET(self):
        if not self._auth():
            return
        path = self.path.split("?")[0]
        m = re.fullmatch(r"/api/v1/site-images", path)
        if m:
            return self._file("images.json")
        m = re.fullmatch(r"/api/v1/site-images/([\w.-]+)/roster", path)
        if m:
            return self._file(f"roster.{m.group(1)}.json")
        m = re.fullmatch(r"/api/v1/site-images/([\w.-]+)/machines", path)
        if m:
            return self._file(f"machines.{m.group(1)}.json")
        m = re.fullmatch(r"/api/v1/site-images/([\w.-]+)/machines/([\w:-]+)/samples", path)
        if m:
            # o smoke prova que o coletor pede a JANELA (since/until): o GET vai ao log com a query
            with open(os.path.join(FIX, "gets.log"), "a") as f:
                f.write(json.dumps({"method": "GET", "path": self.path}) + "\n")
            return self._file(f"samples.{m.group(1)}.{m.group(2)}.json")
        m = re.fullmatch(r"/api/v1/site-images/([\w.-]+)/commands", path)
        if m:
            return self._file("commands.json")
        self._send(404, {"detail": "Not Found"})

    def _record(self):
        if not self._auth():
            return
        n = int(self.headers.get("Content-Length", "0") or 0)
        body = self.rfile.read(n).decode("utf-8", "replace") if n else ""
        with open(os.path.join(FIX, "posts.log"), "a") as f:
            f.write(json.dumps({"method": self.command, "path": self.path.split("?")[0],
                                "body": body}) + "\n")
        self._send(200, {"ok": True})

    do_POST = _record
    do_PUT = _record


srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
with open(PORTFILE, "w") as f:
    f.write(str(srv.server_address[1]))
srv.serve_forever()
