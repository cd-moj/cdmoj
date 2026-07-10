#!/bin/bash
# Sobe o MOJ local (dev): setup + fcgiwrap + reload nginx + daemon de julgamento.
# Uso: bash server/bin/start-all.sh [mock|local|cluster]   (default: mock)
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
BACKEND="${1:-mock}"
cd "$ROOT"

bash server/bin/setup.sh

# (Storage de problemas é MOJ-nativo: repo git LOCAL por problema, sem serviço externo.)

if [ ! -S run/fcgiwrap.sock ]; then
  echo ">> iniciando fcgiwrap…"
  nohup bash server/bin/start-fcgiwrap.sh >run/fcgiwrap.log 2>&1 &
  for i in $(seq 1 25); do [ -S run/fcgiwrap.sock ] && break; sleep 0.2; done
else
  echo ">> fcgiwrap já rodando."
fi

echo ">> nginx test + reload…"
~/nginx-proxy/proxy.sh test >/dev/null 2>&1 && ~/nginx-proxy/proxy.sh reload || echo "   (verifique o nginx-proxy)"

if ! pgrep -f 'server/daemons/judged.sh' >/dev/null 2>&1; then
  echo ">> iniciando judged (backend=$BACKEND)…"
  JUDGE_BACKEND="$BACKEND" nohup bash server/daemons/judged.sh >run/judged.log 2>&1 &
else
  echo ">> judged já rodando."
fi

sleep 0.5
bash server/bin/status.sh
