#!/bin/bash
# Sobe o fcgiwrap (vendored, sem root) num socket unix user-space para o nginx
# conversar com a API bash (router.sh). Rode em background ou via systemd.
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"   # .../cdmoj
# RUNDIR (estado de runtime) fica FORA do repo e é configurável; default no workspace.
: "${RUNDIR:=/home/ribas/moj/run}"
SOCK="${MOJ_FCGI_SOCK:-$RUNDIR/fcgiwrap.sock}"
# O socket unix nasce com 0777&~umask. Com o default (022) sai 0755 = sem `w` p/ grupo/outros:
# um nginx que rode como OUTRO usuário (www-data, do nginx do sistema) leva EACCES no connect()
# e a API vira 502. 007 => 0770 (dono + GRUPO) e basta pôr o usuário do nginx no grupo do dono
# (`usermod -aG <dono> www-data`; o nginx faz initgroups()). Ver docs/DEPLOY.md.
: "${FCGI_UMASK:=007}"
FCGI="$ROOT/server/bin/fcgiwrap"; [ -x "$FCGI" ] || FCGI="$(command -v fcgiwrap || echo "$FCGI")"
mkdir -p "$(dirname "$SOCK")"
rm -f "$SOCK"
echo "fcgiwrap -> unix:$SOCK (children=8, umask=$FCGI_UMASK)  router=$ROOT/server/api/v1/router.sh"
umask "$FCGI_UMASK"
exec "$FCGI" -c 8 -s "unix:$SOCK"
