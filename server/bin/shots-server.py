#!/usr/bin/env python3
"""shots-server.py — servidor de CAPTURA das screenshots dos tutoriais (usado por shots-ajuda.sh).

Serve a árvore web/ estática e, para /api/v1/*, EXECUTA o router.sh de verdade (CGI) com
CONTESTSDIR apontando p/ o contest fictício — as telas saem com resposta REAL da API sobre
dados inventados. Nunca toca em dado de produção: só lê o que shots-ajuda.sh montou no temp.

Dois ajustes só-na-captura (o repo não muda):
  • /shared/api.js é servido com o token fixado (o headless não tem localStorage);
  • todo HTML ganha um <img src="/__delay"> que segura o evento `load` até o app renderizar
    (o firefox --screenshot fotografa no load; as páginas buscam os dados depois dele).
A sessão (= o papel logado) vem do parâmetro `sess=` da URL da página e é gravada num cookie,
para que as chamadas de API seguintes saibam quem está logado.
"""
import os, re, subprocess, time, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.environ["SHOT_ROOT"]
FIX = os.environ["SHOT_FIX"]
RUN = os.environ["SHOT_RUN"]
SESSDIR = os.environ["SHOT_SESS"]
DELAY_MS = int(os.environ.get("SHOT_DELAY_MS", "2500"))
PORT = int(os.environ["SHOT_PORT"])
WEB = os.path.join(ROOT, "web")
ROUTER = os.path.join(ROOT, "server", "api", "v1", "router.sh")

MIME = {".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
        ".css": "text/css; charset=utf-8", ".json": "application/json",
        ".svg": "image/svg+xml", ".png": "image/png", ".webp": "image/webp",
        ".mp3": "audio/mpeg", ".gif": "image/gif", ".ico": "image/x-icon"}

# o app injeta o token no localStorage; aqui ele é fixado direto no módulo servido
API_TOKEN_PATCH = ("export const getToken   = (c) => "
                   "(localStorage.getItem(tkey(c)) || window.__SHOT_TOKEN || '');")


def run_router(path, qs, method, token, body=b""):
    env = dict(os.environ)
    env.update({
        "PATH_INFO": path, "QUERY_STRING": qs, "REQUEST_METHOD": method,
        "HTTP_AUTHORIZATION": f"Bearer {token}" if token else "",
        "CONTESTSDIR": FIX, "SESSIONDIR": SESSDIR, "RUNDIR": RUN,
        "TL_STORE_DIR": os.path.join(RUN, "tl"),
        "MOJ_PROBLEMS_DIR": os.path.join(RUN, "problems"),
        "SPOOLDIR": os.path.join(RUN, "spool", "submissions"),
        "SPOOLDONEDIR": os.path.join(RUN, "spool", "submissions-done"),
        "CONTENT_LENGTH": str(len(body)),
    })
    try:
        p = subprocess.run(["bash", ROUTER], input=body, env=env,
                           capture_output=True, timeout=30)
        return p.stdout
    except Exception as e:                                     # noqa: BLE001
        return b"Status: 500\r\nContent-Type: text/plain\r\n\r\n" + str(e).encode()


def split_cgi(out):
    """separa cabeçalhos CGI do corpo; devolve (status, headers, body)"""
    sep = out.find(b"\r\n\r\n")
    if sep < 0:
        sep = out.find(b"\n\n")
        head, body = (out[:sep], out[sep + 2:]) if sep >= 0 else (b"", out)
    else:
        head, body = out[:sep], out[sep + 4:]
    status, headers = 200, []
    for line in head.decode("utf-8", "replace").splitlines():
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        k, v = k.strip(), v.strip()
        if k.lower() == "status":
            status = int(v.split()[0])
        else:
            headers.append((k, v))
    return status, headers, body


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):          # silencia o log padrão
        pass

    def _send(self, status, ctype, body, extra=()):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in extra:
            self.send_header(k, v)
        self.end_headers()
        try:
            self.wfile.write(body)
        except BrokenPipeError:
            pass

    def _sess(self, qs):
        """papel logado: parâmetro ?sess= (página) ou o cookie que ele deixou (API)"""
        s = urllib.parse.parse_qs(qs).get("sess", [""])[0]
        if s:
            return s
        ck = self.headers.get("Cookie", "")
        m = re.search(r"shotsess=([A-Za-z0-9_]+)", ck)
        return m.group(1) if m else ""

    def do_GET(self):
        self._handle("GET")

    def do_POST(self):
        self._handle("POST")

    def _handle(self, method):
        u = urllib.parse.urlsplit(self.path)
        path, qs = urllib.parse.unquote(u.path), u.query

        if path == "/__ping":
            return self._send(200, "text/plain", b"ok")
        if path == "/__delay":                       # segura o evento `load` do firefox
            time.sleep(DELAY_MS / 1000.0)
            return self._send(200, "image/gif",
                              b"GIF89a\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\xff\xff\xff"
                              b"!\xf9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01"
                              b"\x00\x00\x02\x02D\x01\x00;")

        sess = self._sess(qs)

        if path.startswith("/api/v1/"):
            body = b""
            if method == "POST":
                n = int(self.headers.get("Content-Length") or 0)
                body = self.rfile.read(n) if n else b""
            out = run_router(path[len("/api/v1"):], qs, method, sess, body)
            status, headers, rbody = split_cgi(out)
            ctype = next((v for k, v in headers if k.lower() == "content-type"),
                         "application/json")
            # repassa os DEMAIS cabeçalhos da API: há tela que depende deles, e sem isso ela
            # aparece "desligada" na captura sem ninguém entender por quê — foi o caso do
            # `X-MOJ-Frozen` do /contest/score, que é quem acende o aviso de placar congelado.
            passa = [(k, v) for k, v in headers
                     if k.lower() not in ("content-type", "content-length", "status")]
            return self._send(status, ctype, rbody, passa)

        # ---- estático (árvore web/) ----
        fs = os.path.normpath(os.path.join(WEB, path.lstrip("/")))
        if not fs.startswith(WEB):
            return self._send(403, "text/plain", b"forbidden")
        if os.path.isdir(fs):
            fs = os.path.join(fs, "index.html")
        if not os.path.isfile(fs):
            return self._send(404, "text/plain", b"not found")

        ext = os.path.splitext(fs)[1]
        with open(fs, "rb") as f:
            data = f.read()
        extra = []

        if fs.endswith("/shared/api.js"):
            data = data.replace(
                b"export const getToken   = (c) => localStorage.getItem(tkey(c)) || '';",
                API_TOKEN_PATCH.encode())
        elif ext == ".html":
            txt = data.decode("utf-8")
            # token da sessão + o <img> que segura o `load` até o app terminar de pintar
            inject = (f'<script>window.__SHOT_TOKEN={sess!r};</script>'
                      f'<img src="/__delay" alt="" style="position:fixed;left:-9px;top:-9px;'
                      f'width:1px;height:1px;opacity:0">')
            # ?click=<seletor>&times=N : aperta um botão N vezes antes da foto. É como se
            # fotografa uma tela que só existe DEPOIS de interagir — a cerimônia de revelação
            # começa parada, e o que interessa no tutorial é ela no meio do caminho.
            q = urllib.parse.parse_qs(qs)
            # ?clickcss=<seletor CSS> : quando o alvo NÃO é botão/link. A sanfona do
            # competidor é um <span class="prob-left"> com listener de clique — por texto não
            # se acha, e por `div,span` acharia um ancestral gigante que contém o texto.
            clickcss = (q.get("clickcss") or [""])[0]
            if clickcss:
                n = int((q.get("times") or ["1"])[0])
                inject += (
                    '<script>(()=>{let i=0,done=0;const t=setInterval(()=>{'
                    f'const els=[...document.querySelectorAll({clickcss!r})];'
                    f'const b=els[done];'
                    f'if(b){{b.click();if(++done>={n})return clearInterval(t);}}'
                    f'if(++i>200)clearInterval(t);}},120);}})();</script>')
            # ?hide=<seletores CSS> : esconde seções para a foto sobrar justa. É melhor que
            # rolar a página — `scrollIntoView` briga com a topbar fixa e o firefox fotografa a
            # partir do topo do documento, então a tela sai remendada.
            hide = (q.get("hide") or [""])[0]
            if hide:
                inject += f'<style>{hide}{{display:none !important}}</style>'
                # o app dá `show()` nas seções ao renderizar; o !important do <style> vence o
                # style inline, mas a regra tem de existir ANTES — por isso vai no <head>… como
                # o inject vai no fim do body, o !important é o que garante.
            click = (q.get("click") or [""])[0]
            if click:
                n = int((q.get("times") or ["1"])[0])
                # ⚠ o clique roda IMEDIATAMENTE (não no `load`): o firefox fotografa NO load, e
                # um listener de load dispararia depois da foto. O <img> de delay segura o load,
                # então há tempo de sobra para o app pintar e para estes cliques acontecerem.
                inject += (
                    '<script>(()=>{let i=0,done=0;const t=setInterval(()=>{'
                    'const b=[...document.querySelectorAll("button,.btn,a,summary")]'
                    f'.find(e=>(e.textContent||"").includes({click!r}));'
                    f'if(b){{b.click();if(++done>={n})return clearInterval(t);}}'
                    f'if(++i>200)clearInterval(t);}},120);}})();</script>')
            txt = txt.replace("</body>", inject + "</body>", 1)
            data = txt.encode("utf-8")
            if sess:
                extra.append(("Set-Cookie", f"shotsess={sess}; Path=/"))

        return self._send(200, MIME.get(ext, "application/octet-stream"), data, extra)


ThreadingHTTPServer.allow_reuse_address = True
ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
