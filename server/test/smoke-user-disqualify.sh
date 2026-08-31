#!/bin/bash
# smoke-user-disqualify.sh — flag .disqualified de 1ª classe (DSQ da LATAM 2026):
#   1. conta com .disqualified=true NÃO sai no sc_users (fora do placar/rank/estrela);
#   2. e NÃO conta na estatística (nem inscrito, nem submissões) — placar e estatística
#      SEMPRE contam a mesma população (a lição do relato do Carlos);
#   3. sem o flag (ou removido), volta a contar nos dois;
#   4. desabilitado (senha !) SEM o flag continua no placar (disable ≠ DSQ).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
export CONTESTSDIR="$FIX"
C="$FIX/dq"; mkdir -p "$C/var"
NOW=$EPOCHSECONDS
printf 'CONTEST_ID=dq\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nPROBS=( x col#pa A A col#pa )\n' \
  "$((NOW-3600))" "$((NOW+3600))" > "$C/conf"
mk(){ # <login> <json-extra>
  mkdir -p "$C/users/$1"
  jq -cn --arg l "$1" "{login:\$l, fullname:(\"Time \"+\$l), password:\"x\", team:{region:\"Sede A\", flag:\"br\"}} + $2" > "$C/users/$1/account.json"
  printf '%s:col#pa:C:Accepted:%s:id%s\n' "$NOW" "$NOW" "$1" > "$C/users/$1/history"
}
mk u-normal '{}'
mk u-dsq '{disqualified:true}'
mk u-disabled '{password:"!bloqueada"}'

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
bad(){ FAIL=$((FAIL+1)); echo "FALHOU: $*" >&2; }

# --- 1/4: sc_users ---
SU="$(CONTESTDIR="$C" bash -c 'source "'"$ROOT"'/score/score-common.sh"; sc_users' 2>/dev/null)"
grep -q "^u-normal" <<<"$SU"    && ok || bad "u-normal fora do sc_users"
grep -q "^u-disabled" <<<"$SU"  && ok || bad "u-disabled sumiu do placar (disable ≠ DSQ)"
grep -q "^u-dsq" <<<"$SU"       && bad "u-dsq APARECEU no sc_users" || ok

# --- 2: estatística ---
OUT="$FIX/stats.json"
bash "$ROOT/score/stats-gen.sh" dq "$OUT" || bad "stats-gen falhou"
jq -e '.totals.enrolled == 2' "$OUT" >/dev/null && ok || bad "enrolled devia ser 2 (sem o DSQ): $(jq -c .totals "$OUT")"
jq -e '.totals.users == 2' "$OUT" >/dev/null && ok || bad "users devia ser 2 (submissão do DSQ fora)"
jq -e '.totals.submissions == 2' "$OUT" >/dev/null && ok || bad "submissions devia ser 2"

# --- 3: reverteu, volta a contar ---
jq -c 'del(.disqualified)' "$C/users/u-dsq/account.json" > "$C/users/u-dsq/account.json.t" \
  && mv "$C/users/u-dsq/account.json.t" "$C/users/u-dsq/account.json"
SU2="$(CONTESTDIR="$C" bash -c 'source "'"$ROOT"'/score/score-common.sh"; sc_users' 2>/dev/null)"
grep -q "^u-dsq" <<<"$SU2" && ok || bad "u-dsq não voltou ao sc_users após undo"
bash "$ROOT/score/stats-gen.sh" dq "$OUT" || true
jq -e '.totals.enrolled == 3 and .totals.submissions == 3' "$OUT" >/dev/null && ok || bad "estatística não voltou a 3 após undo"

echo "smoke-user-disqualify: PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
