#!/bin/bash
# Sobe o fcgiwrap (vendored, sem root) num socket unix user-space para o nginx
# conversar com a API bash (router.sh). Rode em background ou via systemd.
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"   # .../cdmoj
# RUNDIR (estado de runtime) fica FORA do repo e é configurável; default no workspace.
: "${RUNDIR:=/home/ribas/moj/run}"
SOCK="${MOJ_FCGI_SOCK:-$RUNDIR/fcgiwrap.sock}"
FCGI="$ROOT/server/bin/fcgiwrap"; [ -x "$FCGI" ] || FCGI="$(command -v fcgiwrap || echo "$FCGI")"
mkdir -p "$(dirname "$SOCK")"
rm -f "$SOCK"
echo "fcgiwrap -> unix:$SOCK (children=8)  router=$ROOT/server/api/v1/router.sh"
exec "$FCGI" -c 8 -s "unix:$SOCK"
