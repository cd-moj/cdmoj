#!/bin/bash
# reap-stale-handlers.sh — mata handlers CGI órfãos: processos `api/v1/router.sh` com mais de
# MAX_S segundos (default 600). O nginx desiste aos 300 s (fastcgi_read_timeout) — além disso
# a resposta NÃO TEM MAIS DONO e o handler vivo é só CPU presa. Casos reais de 28/08/2026:
# reconcile de balões preso 1h46 (bug do memo em subshell) e import O(n²) de 10+ min — os dois
# seguravam 1-2 núcleos e um worker do pool cada.
#
# Roda no HOST como root (enxerga os processos do container via /proc). Instalação:
# server/bin/install-reaper.sh (timer systemd de 5 min). Vítimas vão pro journal (moj-reaper).
# Subshells/filhos também casam o padrão e caem na mesma varredura ou na seguinte.
set -u
MAX_S="${MAX_S:-600}"
for pid in $(pgrep -f "api/v1/router[.]sh"); do
  et="$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')"
  [[ -n "$et" ]] || continue
  (( et > MAX_S )) || continue
  uri="$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^PATH_INFO=//p' | head -1)"
  logger -t moj-reaper "matando router.sh pid=$pid etimes=${et}s uri=${uri:-?}"
  kill -9 "$pid" 2>/dev/null
done
exit 0
