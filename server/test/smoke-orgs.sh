#!/bin/bash
# ORGS — quem ENTRA numa org (membro/admin) precisa EXISTIR no treino e PODER CRIAR
# PROBLEMAS (cc_can_create, a régua do /problems/create). Antes, um select() mudo
# descartava login fora da regex e gravava o resto sem conferir nada: typo virava membro
# fantasma e aluno sem permissão virava editor do acervo. Recusa é ATÔMICA (nada grava);
# REMOÇÃO nunca valida (lixo já gravado precisa poder sair).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; PROBS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN" "$PROBS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" MOJ_PROBLEMS_DIR="$PROBS"
mkdir -p "$FIX/treino/var"

NOW="$EPOCHSECONDS"
# alice PODE criar (allow); bob EXISTE mas não pode (threshold 0, fora do allow);
# chefe.admin pode (sufixo); "fantasma" não existe; org pré-existente com membro LIXO.
fx_user "$FIX/treino" alice s "Alice"
fx_user "$FIX/treino" bob s "Bob"
fx_user "$FIX/treino" chefe.admin s "Chefe"
echo '{"threshold":0,"allow":["alice"],"deny":[]}' > "$FIX/treino/var/contest-perms.json"
echo '{"velha":{"members":["alice","lixo-antigo"],"admins":["alice"],"created_by":"alice","title":"Velha","public_allowed":false}}' \
  > "$FIX/treino/var/orgs.json"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino alice Alice "$NOW" > "$SESS/ali"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino bob Bob "$NOW" > "$SESS/bb"

pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:180}"; ((fail++)); fi; }
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${4:-}" \
    HTTP_AUTHORIZATION="Bearer $3" bash "$ROUTER" <<<"${5:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
ORGS="$FIX/treino/var/orgs.json"

echo "== /orgs/create: cada membro/admin que entra é validado (recusa ATÔMICA) =="
call /orgs/create POST ali "" '{"name":"nova1","members":["fantasma"]}'
ck "membro inexistente → 404 user_notfound" 'grep -q "user_notfound" <<<"$BODY"'
ck "…e a org NÃO nasceu"                    '! jq -e ".nova1" "$ORGS" >/dev/null 2>&1'
call /orgs/create POST ali "" '{"name":"nova1","members":["bob"]}'
ck "existe mas NÃO PODE criar → 403"        'grep -q "cannot_create" <<<"$BODY"'
call /orgs/create POST ali "" '{"name":"nova1","admins":["fantasma"]}'
ck "admins também validam"                  'grep -q "user_notfound" <<<"$BODY"'
call /orgs/create POST ali "" '{"name":"nova1","members":["chefe.admin"]}'
ck "membro válido (.admin) → cria"          'grep -q "\"success\":true" <<<"$BODY"'
ck "membro gravado"                         'jq -e ".nova1.members | index(\"chefe.admin\")" "$ORGS" >/dev/null'

echo "== /orgs/members: add/admins_add validam; remove NUNCA valida =="
call /orgs/members POST ali "" '{"name":"velha","add":["Inv@lido"]}'
ck "formato inválido → 422 (não é mais descarte mudo)" 'grep -q "login_invalid" <<<"$BODY"'
call /orgs/members POST ali "" '{"name":"velha","add":["fantasma"]}'
ck "inexistente → 404"                      'grep -q "user_notfound" <<<"$BODY"'
call /orgs/members POST ali "" '{"name":"velha","admins_add":["bob"]}'
ck "admins_add sem permissão → 403"         'grep -q "cannot_create" <<<"$BODY"'
ck "…e bob NÃO entrou"                      '! jq -e ".velha.members | index(\"bob\")" "$ORGS" >/dev/null 2>&1'
call /orgs/members POST ali "" '{"name":"velha","add":["chefe.admin"]}'
ck "add válido → 200"                       'grep -q "\"success\":true" <<<"$BODY"'
call /orgs/members POST ali "" '{"name":"velha","remove":["lixo-antigo"]}'
ck "remove de membro LIXO pré-existente funciona" 'grep -q "\"success\":true" <<<"$BODY" && ! jq -e ".velha.members | index(\"lixo-antigo\")" "$ORGS" >/dev/null 2>&1'

echo "== /problems/repo-collaborators (o moj share): mesma régua =="
call /problems/repo-collaborators POST ali "" '{"repo":"velha","add":["fantasma"]}'
ck "share de inexistente → 404"             'grep -q "user_notfound" <<<"$BODY"'
call /problems/repo-collaborators POST ali "" '{"repo":"velha","add":["bob"]}'
ck "share de quem não pode criar → 403"     'grep -q "cannot_create" <<<"$BODY"'
call /problems/repo-collaborators POST ali "" '{"repo":"velha","add":["chefe.admin"]}'
ck "share válido → 200"                     'grep -q "\"success\":true" <<<"$BODY"'

echo "== travas que já existiam continuam (fixadas) =="
call /orgs/create POST bb "" '{"name":"orgdobob"}'
ck "criador sem cc_can_create → 403"        'grep -q "create_forbidden" <<<"$BODY"'
call /orgs/members POST bb "" '{"name":"velha","add":["alice"]}'
ck "não-membro não gerencia (404 opaco)"    'grep -q "not_found" <<<"$BODY"'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
