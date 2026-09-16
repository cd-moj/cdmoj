#!/bin/bash
# install-housekeeping.sh — instala/atualiza o timer DIÁRIO de limpeza de espaço no HOST (root):
# reports de contests encerrados há > 6 meses (mojlog-prune) e caches regeneráveis (cache-purge).
# Idempotente. Os units apontam para os scripts NO CHECKOUT (git pull atualiza a lógica sem
# reinstalar; reinstale só se os units mudarem). Molde: install-reaper.sh.
#   MOJ_USER (default moj) e MOJ_WORKROOT (default /home/moj/moj) ajustam usuário e caminhos.
set -eu
D="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $EUID -eq 0 ]] || { echo "rode como root"; exit 1; }
: "${MOJ_USER:=moj}"; : "${MOJ_WORKROOT:=/home/moj/moj}"
sed -e "s|/home/moj/moj|${MOJ_WORKROOT}|g" -e "s|^User=moj$|User=${MOJ_USER}|" \
  "$D/etc/systemd/moj-housekeeping.service" > /etc/systemd/system/moj-housekeeping.service
cp "$D/etc/systemd/moj-housekeeping.timer" /etc/systemd/system/moj-housekeeping.timer
systemctl daemon-reload
systemctl enable --now moj-housekeeping.timer
systemctl list-timers moj-housekeeping.timer --no-pager | head -3
echo ">> limpeza diária instalada (03:30: mojlog-prune --ended-days 180 --apply + cache-purge --apply)"
