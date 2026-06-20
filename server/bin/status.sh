#!/bin/bash
# Health-check rápido do MOJ local.
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
H="Host: moj.charge.naquadah.com.br"; B="http://127.0.0.1:8080"
ok(){ printf '  [\033[32mok\033[0m] %s\n' "$1"; }
no(){ printf '  [\033[31m--\033[0m] %s\n' "$1"; }

echo "MOJ status:"
[ -S "$ROOT/run/fcgiwrap.sock" ] && ok "fcgiwrap socket ($ROOT/run/fcgiwrap.sock)" || no "fcgiwrap socket ausente — server/bin/start-fcgiwrap.sh"
[ -f "$ROOT/run/nginx.pid" ] 2>/dev/null; pgrep -x nginx >/dev/null 2>&1 && ok "nginx rodando" || no "nginx (use ~/nginx-proxy/proxy.sh start)"
pgrep -f 'server/daemons/judged.sh' >/dev/null 2>&1 && ok "judged daemon rodando" || no "judged daemon parado (opcional)"

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
