#!/bin/bash
# Health-check rápido do MOJ local. Host/porta e caminhos por env (o default é o dev user-space).
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"   # .../cdmoj
# RUNDIR fica FORA do repo (na raiz do workspace) — não é "$ROOT/run".
: "${RUNDIR:=$(cd "$ROOT/.." && pwd)/run}"
H="Host: ${MOJ_HOST:-moj.charge.naquadah.com.br}"; B="${MOJ_BASE:-http://127.0.0.1:8080}"
ok(){ printf '  [\033[32mok\033[0m] %s\n' "$1"; }
no(){ printf '  [\033[31m--\033[0m] %s\n' "$1"; }

echo "MOJ status:"
[ -S "$RUNDIR/fcgiwrap.sock" ] && ok "fcgiwrap socket ($RUNDIR/fcgiwrap.sock)" || no "fcgiwrap socket ausente — server/bin/start-fcgiwrap.sh"
pgrep -x nginx >/dev/null 2>&1 && ok "nginx rodando" || no "nginx parado (dev: ~/nginx-proxy/proxy.sh start; prod: systemctl start nginx)"
# judged: processo local OU heartbeat (ele pode estar em outro container — ver lib/common.sh)
if pgrep -f 'server/daemons/judged.sh' >/dev/null 2>&1; then ok "judged daemon rodando"
elif [ -f "$RUNDIR/judged.alive" ] && [ $(( $(date +%s) - $(stat -c %Y "$RUNDIR/judged.alive") )) -le "${JUDGED_ALIVE_TTL:-120}" ]; then
  ok "judged daemon rodando (heartbeat — outro container)"
else no "judged daemon parado (opcional)"; fi

root="$(curl -s --max-time 3 -H "$H" "$B/api/v1/" 2>/dev/null)"
case "$root" in
  *'"version":"v1"'*) ok "API via nginx → $root";;
  *) no "API não respondeu via nginx ($root)";;
esac
n="$(curl -s --max-time 5 -H "$H" "$B/api/v1/treino/problems" 2>/dev/null | jq 'length' 2>/dev/null)"
[ -n "$n" ] && ok "treino/problems: $n problemas" || no "treino/problems falhou"
echo ""
echo "Teste no navegador (com DNS/hosts apontando o domínio):"
echo "  https://moj.charge.naquadah.com.br:8443/            (home)"
echo "  https://moj.charge.naquadah.com.br:8443/treino/     (problemas)"
echo "  sandbox de submissão: contest 'zzdemo' login demo/demo"
