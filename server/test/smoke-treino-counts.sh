#!/bin/bash
# /treino/problems: contagens reais de solved/attempted (casadas por NOME DE ARQUIVO
# com var/json-count, cujo id interno é pontilhado) + /index/open_training: mais
# resolvidos na SEMANA PASSADA (janela [domingo retrasado, último domingo), distintos).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
T="$FIX/treino"; mkdir -p "$T/var/jsons" "$T/var/json-count"

# jsons: id na forma '#'. json-count: MESMO arquivo, mas id pontilhado de propósito
# (prova que o merge casa por basename, não pelo campo .id).
printf '{"id":"moj-problems#px","title":"PX","tags":["#a"]}' > "$T/var/jsons/moj-problems#px.json"
printf '{"id":"moj-problems#py","title":"PY","tags":[]}'     > "$T/var/jsons/moj-problems#py.json"
printf '{"id":"moj-problems.px","solved_count":5,"attempted_count":9}' > "$T/var/json-count/moj-problems#px.json"
# py NÃO tem json-count -> deve cair em 0/0

# history: semana passada (PREV) x esta semana (THIS), datas relativas a hoje
LW=$(date -d 'last-sunday' +%s 2>/dev/null || echo 0)
PREV=$((LW - 3*86400)); THIS=$((LW + 3600))
fx_user "$T" alice x "Alice"
fx_user "$T" bob x "Bob"
fx_user "$T" carol x "Carol"
{ printf '100:moj-problems#px:C:Accepted,100p:%s:h1\n' "$PREV"
  printf '100:moj-problems#px:C:Accepted,100p (Ignored):%s:h1b\n' "$PREV"  # mesmo user/prob -> conta 1x
  printf '100:moj-problems#py:C:Accepted,100p:%s:h3\n' "$PREV"; } > "$T/users/alice/history"
printf '100:moj-problems#px:C:Accepted,100p:%s:h2\n' "$PREV" > "$T/users/bob/history"
printf '100:moj-problems#pz:C:Accepted,100p:%s:h4\n' "$THIS" > "$T/users/carol/history"

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD=GET QUERY_STRING="${2:-}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:160}"; ((fail++)); fi; }
qp(){ jq -r "$1" <<<"$BODY"; }

echo "== /treino/problems: contagens reais (casadas por arquivo) =="
call /treino/problems
ck "px: solved=5 attempted=9 (do json-count)" '[[ "$(qp ".[]|select(.id==\"moj-problems#px\")|.solved_count")" == 5 && "$(qp ".[]|select(.id==\"moj-problems#px\")|.attempted_count")" == 9 ]]'
ck "py: 0/0 (sem json-count)" '[[ "$(qp ".[]|select(.id==\"moj-problems#py\")|.solved_count")" == 0 && "$(qp ".[]|select(.id==\"moj-problems#py\")|.attempted_count")" == 0 ]]'
ck "ids preservados na forma '#'" '[[ "$(qp ".[].id" | grep -c "moj-problems#")" == 2 ]]'

echo "== /index/open_training: most_solved_prev_week =="
call /index/open_training
ck "tem o campo most_solved_prev_week" '[[ "$(qp "has(\"most_solved_prev_week\")")" == true ]]'
ck "px: 2 resolvedores distintos na semana passada" '[[ "$(qp ".most_solved_prev_week[]|select(.problem_id==\"moj-problems#px\")|.solved_count")" == 2 ]]'
ck "py: 1 resolvedor na semana passada" '[[ "$(qp ".most_solved_prev_week[]|select(.problem_id==\"moj-problems#py\")|.solved_count")" == 1 ]]'
ck "pz (desta semana) NÃO entra na semana passada" '[[ -z "$(qp ".most_solved_prev_week[]|select(.problem_id==\"moj-problems#pz\")|.problem_id")" ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
