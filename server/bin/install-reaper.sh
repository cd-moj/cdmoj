#!/bin/bash
# install-reaper.sh — instala/atualiza o timer do reaper de handlers órfãos no HOST (root).
# Idempotente. Os units apontam para o script NO CHECKOUT (git pull atualiza a lógica sem
# reinstalar; reinstale só se os units mudarem).
set -eu
D="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $EUID -eq 0 ]] || { echo "rode como root"; exit 1; }
sed "s|/home/moj/moj/cdmoj|${D%/server}|" "$D/etc/systemd/moj-reaper.service" > /etc/systemd/system/moj-reaper.service
cp "$D/etc/systemd/moj-reaper.timer" /etc/systemd/system/moj-reaper.timer
systemctl daemon-reload
systemctl enable --now moj-reaper.timer
systemctl list-timers moj-reaper.timer --no-pager | head -3
echo ">> reaper instalado (varre a cada 5 min; MAX_S=600)"
