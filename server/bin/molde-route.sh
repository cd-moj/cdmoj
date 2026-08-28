#!/bin/bash
# molde-route.sh {add|rm|ls} <rota> [backend] — liga/desliga UMA rota da API num caminho
# rápido: backend `porteiro` (default — leitor Python de caches) ou `molde` (bash persistente).
#   rota = caminho sob /api/v1, ex.: contest/score
# `add` escreve /etc/nginx/moj-molde-routes/<slug>.conf (location exata apontando p/ o socket
# do backend, com anteparo+breaker+microcache+shed replicados e fallback 502 → fcgiwrap),
# valida com nginx -t (reverte se reprovar) e recarrega. `rm` remove + reload.
# Rollback TOTAL: rm /etc/nginx/moj-molde-routes/*.conf && systemctl reload nginx
set -eu
[[ $EUID -eq 0 ]] || { echo "rode como root"; exit 1; }
ACT="${1:?uso: molde-route.sh add|rm|ls [rota] [porteiro|molde]}"
DIR=/etc/nginx/moj-molde-routes
SNIP=/etc/nginx/snippets/moj-app.conf
mkdir -p "$DIR"

if [[ "$ACT" == ls ]]; then ls -la "$DIR"; exit 0; fi
ROTA="${2:?uso: molde-route.sh add|rm <rota ex.: contest/score> [porteiro|molde]}"
[[ "$ROTA" =~ ^[a-z0-9/_-]+$ ]] || { echo "rota inválida"; exit 1; }
BACKEND="${3:-porteiro}"
case "$BACKEND" in porteiro) BSOCK=moj-porteiro.sock;; molde) BSOCK=moj-molde.sock;;
  *) echo "backend desconhecido: $BACKEND"; exit 1;; esac
SLUG="${ROTA//\//-}"
F="$DIR/$SLUG.conf"

if [[ "$ACT" == rm ]]; then
  rm -f "$F"; nginx -t && systemctl reload nginx
  echo ">> rota $ROTA de volta ao fcgiwrap"
  exit 0
fi
[[ "$ACT" == add ]] || { echo "ação desconhecida: $ACT"; exit 1; }

# o WORKROOT sai do snippet já instalado (fonte única: o que o install-nginx.sh rendeu)
WORKROOT="$(sed -n 's|.*unix:\(.*\)/run/fcgiwrap.sock;.*|\1|p' "$SNIP" | head -1)"
[[ -n "$WORKROOT" ]] || { echo "não achei o workroot em $SNIP"; exit 1; }

cat > "$F" <<EOF
# rota no backend rápido '$BACKEND' (molde-route.sh — rm deste arquivo + reload = fcgiwrap)
location = /api/v1/$ROTA {
    limit_conn moj_site 16;
$( [[ "$BACKEND" == porteiro ]] \
   && echo '    limit_conn moj_porteiro 256;   # zona própria: 1 ms não disputa com 200 ms' \
   || echo '    include /etc/nginx/moj-breaker-contest[.]conf;' )
    include /etc/nginx/moj-cache-api[.]conf;
    if (-f \$moj_shed_file) { return 503; }
    fastcgi_pass            unix:$WORKROOT/run/$BSOCK;
    fastcgi_split_path_info ^(/api/v1)(/.*)\$;
    error_page 502 = @moj_fcgiwrap;
}
EOF
if ! nginx -t; then rm -f "$F"; echo "nginx -t REPROVOU — snippet removido" >&2; exit 1; fi
systemctl reload nginx
echo ">> rota $ROTA no $BACKEND (fallback 502 → fcgiwrap armado)"
