#!/bin/bash
# smoke-stats-enrolled.sh — estatística conta INSCRITOS, não só quem submeteu (relato do
# Carlos na LATAM 2026: 43 zeros no placar viravam 2 na página). Fixa:
#   1. totals: enrolled = todos os não-privilegiados; users = quem submeteu; absent = diferença;
#   2. problems_solved_dist bucket 0 inclui os ausentes (a distribuição casa com o placar);
#   3. by_region herda os três (sede por regex de login) e fatia com view:true no
#      regions.json sai marcada (recorte sobreposto — não soma com as sedes);
#   4. conta de papel (.admin) NÃO conta como inscrita.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
export CONTESTSDIR="$FIX"
C="$FIX/st"; mkdir -p "$C/var"
NOW=$EPOCHSECONDS
printf 'CONTEST_ID=st\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nPROBS=( x col#pa A A col#pa )\n' \
  "$((NOW-3600))" "$((NOW+3600))" > "$C/conf"
mkuser(){ # <login> [region]
  mkdir -p "$C/users/$1"
  jq -cn --arg r "${2:-}" '{fullname:"T", team:{region:$r, flag:"br-pr"}}' > "$C/users/$1/account.json"
  : > "$C/users/$1/history"
}
mkuser u-solve "Sede A"; mkuser u-zero "Sede A"; mkuser u-absent "Sede A"; mkuser x.admin "Sede A"
printf '%s:col#pa:C:Accepted:%s:aaaa\n' "$NOW" "$NOW" >> "$C/users/u-solve/history"
printf '%s:col#pa:C:Wrong Answer:%s:bbbb\n' "$NOW" "$NOW" >> "$C/users/u-zero/history"
printf '%s:col#pa:C:Accepted:%s:cccc\n' "$NOW" "$NOW" >> "$C/users/x.admin/history"
jq -cn '[{name:"Pais", regex:"^u-", subregions:[{name:"Sede A", regex:"^u-"}]},
         {name:"Recorte X", regex:"^u-", view:true}]' > "$C/regions.json"

OUT="$FIX/stats.json"
bash "$ROOT/score/stats-gen.sh" st "$OUT" || { echo "stats-gen falhou"; exit 1; }

PASS=0; FAIL=0
ck(){ if jq -e "$1" "$OUT" >/dev/null 2>&1; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: $2  [$1]" >&2; fi }

ck '.totals.enrolled == 3'  "enrolled global (3 não-papel)"
ck '.totals.users == 2'     "users global (2 submeteram; .admin fora)"
ck '.totals.absent == 1'    "absent global (u-absent)"
ck '(.problems_solved_dist[] | select(.solved==0) | .users) == 2' "bucket 0 = zero-com-sub + ausente"
ck '(.problems_solved_dist[] | select(.solved==1) | .users) == 1' "bucket 1 = u-solve"
ck '.view == false'         "global não é recorte"
ck '.by_region["Sede A"].totals.enrolled == 3' "sede: enrolled"
ck '.by_region["Sede A"].totals.absent == 1'   "sede: absent"
ck '(.by_region["Sede A"].view // false) == false' "sede real sem flag"
ck '.by_region["Recorte X"].view == true'      "fatia view marcada"
ck '(.by_region["Sede A"].problems_solved_dist[] | select(.solved==0) | .users) == 2' "sede: bucket 0 com ausente"

# --- Estatísticas 2.0 (01/09): eventos, desempenho, dirt, línguas ---
ck '(.ac_events | length) == 1 and .ac_events[0][0] == "u-solve"' "ac_events com o 1º AC"
ck '.teams_idx["u-solve"].n != null and (.penalty_minutes == 20) and (.unranked_regex != null)' "teams_idx {n,c,r} + pen + unranked"
ck '.top_teams[0].login == "u-solve" and .top_teams[0].solved == 1' "top_teams"
ck '.performance.teams_with_ac == 1 and .performance.solved.median == 1' "performance global"
ck '(.problems[0].tries_per_ac != null) and (.problems[0].ac_langs | length) >= 1' "por-problema: tentativas e língua"

echo "smoke-stats-enrolled: PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
