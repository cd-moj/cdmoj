#!/bin/bash
# install-nginx.sh — instala o vhost do MOJ no nginx do SISTEMA (root, 80/443). Idempotente.
#
#   sudo bash server/bin/install-nginx.sh --workroot /home/moj/moj \
#        --names "moj.naquadah.com.br" [--cert moj.naquadah.com.br]
#
#   --workroot DIR   raiz do workspace (o dir com cdmoj/ mojtools/ contests/ run/).   [obrigatório]
#   --names "a b"    hosts do site principal. Os subdomínios de contest (<id>.<host>) são
#                    derivados destes nomes automaticamente (regex + map).            [obrigatório]
#   --cert NOME      usa o cert de /etc/letsencrypt/live/NOME/ (80→443). SEM ele: vhost
#                    HTTP-only (bootstrap: dá p/ subir e validar a API antes do certificado).
#   --owner USER     dono do workspace/socket (default: dono de --workroot).
#   --router PATH    router.sh COMO O FCGIWRAP O VÊ. Default = caminho DENTRO da imagem podman
#                    (/opt/moj/cdmoj/server/api/v1/router.sh). Bare-metal: --bare-metal.
#   --bare-metal     atalho p/ --router <workroot>/cdmoj/server/api/v1/router.sh.
#   --nginx-user U   usuário dos workers (default: o `user` do /etc/nginx/nginx.conf).
#   -n, --dry-run    só mostra o que seria gerado.
#
# Gera, a partir dos templates de server/etc/nginx/:
#   /etc/nginx/snippets/moj-app.conf   corpo (root web/, /api/v1 via fcgiwrap, /docs/)
#   /etc/nginx/conf.d/moj.conf         map do contest + server blocks
# E resolve as duas armadilhas do nginx de sistema (que no dev não aparecem, porque lá o nginx
# roda como o MESMO usuário do MOJ):
#   (a) workers no grupo do dono  -> sem isso: 403 no estático e EACCES no socket (502 na API);
#   (b) default_server da distro desabilitado -> senão ele pode capturar o :80.
#
# O modelo DEV (nginx user-space em 8080/8443) não usa este script — ver docs/DEPLOY.md.
set -euo pipefail

SELF="$(readlink -f "$0")"; ROOT="$(cd "$(dirname "$SELF")/../.." && pwd)"   # .../cdmoj
TPLDIR="$ROOT/server/etc/nginx"
CONF_DIR="${CONF_DIR:-/etc/nginx/conf.d}"
SNIPPET_DIR="${SNIPPET_DIR:-/etc/nginx/snippets}"
SNIPPET="$SNIPPET_DIR/moj-app.conf"
WORKROOT=""; NAMES=""; CERTNAME=""; OWNER=""; ROUTER=""; NGINX_USER=""; DRYRUN=0; BARE=0

die(){ echo "install-nginx: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --workroot)   WORKROOT="${2:?}"; shift 2 ;;
    --names)      NAMES="${2:?}"; shift 2 ;;
    --cert)       CERTNAME="${2:?}"; shift 2 ;;
    --owner)      OWNER="${2:?}"; shift 2 ;;
    --router)     ROUTER="${2:?}"; shift 2 ;;
    --bare-metal) BARE=1; shift ;;
    --nginx-user) NGINX_USER="${2:?}"; shift 2 ;;
    -n|--dry-run) DRYRUN=1; shift ;;
    -h|--help)    sed -n '2,30p' "$SELF"; exit 0 ;;
    *) die "opção desconhecida: $1 (--help)" ;;
  esac
done

[ -n "$WORKROOT" ] || die "faltou --workroot"
[ -n "$NAMES" ]    || die "faltou --names"
WORKROOT="$(cd "$WORKROOT" && pwd)" || die "--workroot inválido"
[ -d "$WORKROOT/cdmoj/web" ] || die "$WORKROOT/cdmoj/web não existe (workspace errado?)"
[ -d "$WORKROOT/run" ] || echo "install-nginx: AVISO: $WORKROOT/run ainda não existe (o container o cria)." >&2
[ "$DRYRUN" = 1 ] || [ "$(id -u)" = 0 ] || die "rode como root (ou -n p/ dry-run)"

: "${OWNER:=$(stat -c %U "$WORKROOT")}"
if [ "$BARE" = 1 ]; then ROUTER="$WORKROOT/cdmoj/server/api/v1/router.sh"; fi
: "${ROUTER:=/opt/moj/cdmoj/server/api/v1/router.sh}"     # caminho DENTRO da imagem podman
: "${NGINX_USER:=$(awk '$1=="user"{sub(/;.*/,"",$2); print $2; exit}' /etc/nginx/nginx.conf 2>/dev/null)}"
: "${NGINX_USER:=www-data}"

# http2: a diretiva `http2 on;` só existe a partir do nginx 1.25.1 (o Ubuntu 24.04 traz o 1.24,
# que só entende `listen … ssl http2`). Escolhe a forma pela versão — usar a errada é [emerg].
NGXVER="$(nginx -v 2>&1 | sed -n 's|.*nginx/\([0-9][0-9.]*\).*|\1|p')"
if [ -n "$NGXVER" ] && [ "$(printf '%s\n1.25.1\n' "$NGXVER" | sort -V | head -1)" = "1.25.1" ]; then
  HTTP2_LISTEN=""; HTTP2_ON="    http2       on;"
else
  HTTP2_LISTEN=" http2"; HTTP2_ON=""
fi

# server_name: nomes exatos + regex dos subdomínios de contest (<id>.<host>), derivada dos nomes.
alt=""
for n in $NAMES; do alt="${alt:+$alt|}$(printf '%s' "$n" | sed 's/\./\\./g')"; done
SERVER_NAMES="$NAMES"
SERVER_NAMES_RE="~^[a-z0-9][a-z0-9._-]*\.(?:$alt)\$"
SUBDOMAIN_MAP="~^(?<cid>[a-z0-9][a-z0-9._-]*)\.(?:$alt)\$  \$cid;"

TPL="$TPLDIR/moj-prod-http.conf.in"; MODO="HTTP-only (sem TLS)"
if [ -n "$CERTNAME" ]; then
  TPL="$TPLDIR/moj-prod.conf.in"; MODO="TLS (/etc/letsencrypt/live/$CERTNAME/)"
  [ "$DRYRUN" = 1 ] || [ -s "/etc/letsencrypt/live/$CERTNAME/fullchain.pem" ] \
    || die "não achei /etc/letsencrypt/live/$CERTNAME/fullchain.pem — emita antes (server/bin/cert-setup.sh)"
fi

render() {  # render <template> — substitui os @PLACEHOLDERS@ (sem sed: os valores têm | e \)
  local c; c="$(cat "$1")"
  c="${c//@WORKROOT@/$WORKROOT}";               c="${c//@ROUTER@/$ROUTER}"
  c="${c//@SNIPPET@/$SNIPPET}";                 c="${c//@CERTNAME@/$CERTNAME}"
  c="${c//@SERVER_NAMES@/$SERVER_NAMES}";       c="${c//@SERVER_NAMES_RE@/$SERVER_NAMES_RE}"
  c="${c//@SUBDOMAIN_MAP@/$SUBDOMAIN_MAP}";     c="${c//@NGINX_USER@/$NGINX_USER}"
  c="${c//@OWNER@/$OWNER}";                     c="${c//@HTTP2_LISTEN@/$HTTP2_LISTEN}"
  c="${c//@HTTP2_ON@/$HTTP2_ON}"
  printf '%s\n' "$c"
}

echo ">> workspace=$WORKROOT  dono=$OWNER  nginx=$NGINX_USER  modo=$MODO"
echo ">> nomes=$SERVER_NAMES  (+ subdomínios de contest <id>.<host>)"
echo ">> router (visto pelo fcgiwrap)=$ROUTER"

if [ "$DRYRUN" = 1 ]; then
  echo "=== $SNIPPET ==="; render "$TPLDIR/moj-app.conf.in"
  echo "=== $CONF_DIR/moj.conf ==="; render "$TPL"
  exit 0
fi

# (a) workers do nginx no grupo do dono: ler web/ e CONECTAR no socket 0770 (senão 403/502).
if ! id -nG "$NGINX_USER" | tr ' ' '\n' | grep -qx "$OWNER"; then
  usermod -aG "$OWNER" "$NGINX_USER"
  echo ">> $NGINX_USER adicionado ao grupo $OWNER (precisa de restart do nginx p/ valer)"
  NEED_RESTART=1
fi
# o home do dono precisa ser atravessável pelo grupo (Ubuntu cria 750 <dono>:<dono>)
HOMEDIR="$(getent passwd "$OWNER" | cut -d: -f6)"
[ -n "$HOMEDIR" ] && chmod g+x "$HOMEDIR" 2>/dev/null || true

# (b) default_server da distro fora do caminho
if [ -L /etc/nginx/sites-enabled/default ]; then
  rm -f /etc/nginx/sites-enabled/default; echo ">> desabilitei /etc/nginx/sites-enabled/default"
elif [ -f /etc/nginx/sites-enabled/default ]; then
  mv /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/default.disabled
  echo ">> movi sites-enabled/default -> default.disabled"
fi

mkdir -p "$CONF_DIR" "$SNIPPET_DIR" /var/www/html
# Guarda o que existia: se o `nginx -t` reprovar, VOLTA. Senão fica um conf quebrado em disco e o
# próximo reload (o do hook de renovação do certificado, p.ex.) derruba o site sem ninguém ver.
BK="$(mktemp -d)"; trap 'rm -rf "$BK"' EXIT
for f in "$SNIPPET" "$CONF_DIR/moj.conf"; do
  [ -f "$f" ] && cp -a "$f" "$BK/$(basename "$f")"
done
render "$TPLDIR/moj-app.conf.in" > "$SNIPPET"
render "$TPL" > "$CONF_DIR/moj.conf"
chmod 644 "$SNIPPET" "$CONF_DIR/moj.conf"

# nginx mascarado (ex.: máquina que rodava só o proxy user-space) não sobe nunca — destrave.
if [ "$(systemctl is-enabled nginx 2>/dev/null)" = masked ]; then
  systemctl unmask nginx; echo ">> nginx estava MASKED — desmascarei"
fi
if ! nginx -t; then
  echo ">> nginx -t REPROVOU — revertendo os arquivos gerados" >&2
  for f in "$SNIPPET" "$CONF_DIR/moj.conf"; do
    if [ -f "$BK/$(basename "$f")" ]; then cp -a "$BK/$(basename "$f")" "$f"; else rm -f "$f"; fi
  done
  exit 1
fi
echo ">> gerados: $SNIPPET  e  $CONF_DIR/moj.conf"
if ! systemctl is-active --quiet nginx; then
  systemctl enable --now nginx; echo ">> nginx iniciado (e habilitado no boot)"
elif [ "${NEED_RESTART:-0}" = 1 ]; then
  systemctl restart nginx; echo ">> nginx reiniciado (grupo novo do worker)"
else
  systemctl reload nginx; echo ">> nginx recarregado"
fi
echo ">> ok. Teste:  curl -s -H 'Host: ${NAMES%% *}' http://127.0.0.1/api/v1/"
