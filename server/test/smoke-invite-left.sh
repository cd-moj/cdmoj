#!/bin/bash
# smoke-invite-left.sh — o "faltam …" do aviso de convite (lib/invite-notify.sh: _inv_left + inv_msg).
# O lembrete do painel (🔔) o admin dispara a qualquer hora: uma semana antes do fechamento a DM dizia "faltam
# ~168 h". Agora, de 24 h para cima, vêm os dias ("~1 dia e 6 h", "~7 dias"), no idioma de cada parte da DM — e a
# parte em espanhol não recebe mais o texto feito p/ o inglês.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
export CONTESTSDIR="$FIX"
_DIR="$ROOT/api/v1"
source "$ROOT/api/v1/lib/common.sh"
source "$ROOT/api/v1/lib/invite-notify.sh"
PASS=0; FAIL=0
eqk(){ if [[ "$1" == "$2" ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  FAIL: $3 (veio '$1', esperado '$2')"; fi; }
has(){ if [[ "$1" == *"$2"* ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  FAIL: $3 (não achei '$2')"; fi; }
hasnt(){ if [[ "$1" != *"$2"* ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  FAIL: $3 (achei '$2')"; fi; }

echo "== _inv_left =="
eqk "$(_inv_left 30 pt)" "~1 min" "menos de 2 min"
eqk "$(_inv_left 2400 pt)" "~40 min" "minutos"
eqk "$(_inv_left 3600 pt)" "~1 h" "1 h"
eqk "$(_inv_left 86399 pt)" "~23 h" "abaixo de 24 h segue em horas"
eqk "$(_inv_left 86400 pt)" "~1 dia" "24 h = 1 dia"
eqk "$(_inv_left $(( 86400 + 6*3600 )) pt)" "~1 dia e 6 h" "1 dia e horas"
eqk "$(_inv_left $(( 2*86400 + 3600 )) pt)" "~2 dias e 1 h" "2 dias e horas"
eqk "$(_inv_left $(( 7*86400 )) pt)" "~7 dias" "uma semana (era ~168 h)"
eqk "$(_inv_left $(( 7*86400 - 60 )) pt)" "~7 dias" "de 3 dias para cima, arredonda"
eqk "$(_inv_left $(( 86400 + 6*3600 )) en)" "~1 day and 6 h" "inglês"
eqk "$(_inv_left $(( 7*86400 )) en)" "~7 days" "inglês, plural"
eqk "$(_inv_left $(( 86400 + 6*3600 )) es)" "~1 día y 6 h" "espanhol"
eqk "$(_inv_left $(( 7*86400 )) es)" "~7 días" "espanhol, plural"

echo "== inv_msg (lembrete, fecha em 7 dias) =="
NOW="$EPOCHSECONDS"; CL=$(( NOW + 7*86400 + 30 ))
for l in pt en es; do mkdir -p "$FIX/c$l"; printf 'CONTEST_NAME=Prova\nLOCALE=%s\n' "$l" > "$FIX/c$l/conf"; done
m="$(inv_msg cpt remind 'Time A' "$CL")"
has "$m" "(faltam ~7 dias)" "pt"; hasnt "$m" "168" "pt sem as horas acumuladas"
m="$(inv_msg cen remind 'Time A' "$CL")"
has "$m" "(in ~7 days)" "en: a parte em inglês"; has "$m" "(faltam ~7 dias)" "en: a parte em português"
m="$(inv_msg ces remind 'Time A' "$CL")"
has "$m" "(faltan ~7 días)" "es: a parte em espanhol no idioma dela"; has "$m" "(faltam ~7 dias)" "es: a parte em português"
hasnt "$m" "days" "es: nada do inglês"

echo "RESULT: $PASS passed, $FAIL failed"
(( FAIL == 0 ))
