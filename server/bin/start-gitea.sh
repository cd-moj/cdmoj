#!/bin/bash
# Sobe o Gitea (store git da gestão de problemas) user-space, sem root. Idempotente:
# se já estiver respondendo na porta, não faz nada. O Gitea é a fonte git por trás —
# os autores NUNCA falam com ele direto (só com a API do MOJ, que usa o token admin).
# Uso: bash server/bin/start-gitea.sh        (background recomendado, ou via systemd)
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"   # .../cdmoj
: "${RUNDIR:=/home/ribas/moj/run}"
GHOME="${GITEA_WORK_DIR:-$RUNDIR/gitea}"
BIN="${GITEA_BIN:-$GHOME/gitea}"
INI="${GITEA_CONFIG:-$GHOME/custom/conf/app.ini}"
PORT="$( [ -f "$GHOME/.port" ] && cat "$GHOME/.port" || echo 3939 )"

if [ ! -x "$BIN" ]; then
  echo "!! binário do Gitea ausente em $BIN" >&2
  echo "   baixe (ex.): curl -fsSL -o '$BIN' https://dl.gitea.com/gitea/1.26.4/gitea-1.26.4-linux-amd64 && chmod +x '$BIN'" >&2
  exit 1
fi
[ -f "$INI" ] || { echo "!! app.ini ausente em $INI (ver docs/DEPLOY-GITEA.md p/ provisionar)" >&2; exit 1; }

if curl -fsS "http://127.0.0.1:$PORT/api/v1/version" >/dev/null 2>&1; then
  echo ">> gitea já rodando em :$PORT"; exit 0
fi

echo ">> iniciando gitea (:$PORT, work=$GHOME)…"
GITEA_WORK_DIR="$GHOME" exec "$BIN" -c "$INI" -w "$GHOME" web
