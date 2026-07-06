#!/bin/bash
# Templates nomeados + export + duplicate + mine (com os gates de autorização: não-dono => 404).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
T="$FIX/treino"; mkdir -p "$T/var/jsons"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\n' > "$T/conf"
fx_user "$T" boss.admin p "Boss"
fx_user "$T" regular s "Regular"
fx_user "$T" eve s "Eve"
printf '{"threshold":0,"allow":["regular","eve"],"deny":[]}' > "$T/var/contest-perms.json"
printf 'CONTEST=treino\nLOGIN=boss.admin\nUSERFULLNAME=Boss\nLOGINAT=1\n' > "$SESS/adm"
printf 'CONTEST=treino\nLOGIN=regular\nUSERFULLNAME=Regular\nLOGINAT=1\n' > "$SESS/reg"
printf 'CONTEST=treino\nLOGIN=eve\nUSERFULLNAME=Eve\nLOGINAT=1\n' > "$SESS/eve"
printf '%s' '{"id":"bankprob","title":"Banco Prob","tags":["#x"],"statement_html_b64":"PGgxPm9pPC9oMT4="}' > "$T/var/jsons/bankprob.json"
printf '%s' '{"problems":[{"id":"bankprob","title":"Banco Prob","owner":"someone","collaborators":[],"public":true}]}' > "$T/var/problem-owners.json"
NOW="$(date +%s)"; FUT=$(( NOW + 100000 ))
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-reg}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

# contest origem do regular: 2 problemas (banco + custom com enunciado), toggles e freeze
ST=$(( NOW + 1000 )); EN=$(( NOW + 11800 )); FZ=$(( EN - 3600 ))
SPEC="{\"id\":\"orig-c\",\"name\":\"Original\",\"mode\":\"icpc\",\"priority\":\"prova\",\"start\":$ST,\"end\":$EN,\"freeze\":$FZ,\"languages\":[\"c\",\"cpp\"],\"score_anon\":true,\"show_log\":false,\"penalty_minutes\":15,\"penalty_verdicts\":[\"wa\",\"ce\"],\"users\":[{\"login\":\"aluno1\",\"password\":\"pw1\",\"fullname\":\"Aluno\"}],\"problems\":[{\"bank_id\":\"bankprob\",\"name\":\"B1\",\"letter\":\"A\",\"languages\":[\"c\"]},{\"problem_id\":\"x/custom\",\"name\":\"Cust\",\"letter\":\"B\",\"statement_b64\":\"PHA+Y3VzdDwvcD4=\"}]}"
call /treino/contest-create/create POST "$SPEC" reg
[[ "$(jq -r .contest_id <<<"$BODY")" == orig-c ]] || { echo "SETUP FAIL: $BODY"; exit 1; }

echo "== templates: save do formulário / list / get / rename / delete =="
call /treino/contest-create/templates POST '{"op":"save","name":"prova ed","template":{"mode":"icpc","priority":"prova","start":1000,"end":11800,"freeze":8200,"languages":["c"],"score_anon":true,"users":[{"login":"mal","password":"x"}],"admin":{"password":"vaza"},"id":"nao-vai"}}' reg
ck "save 200"               '[[ "$(jq -r .saved <<<"$BODY")" == true ]]'
TPLF="$T/var/contest-templates/regular.json"
ck "arquivo por login criado" '[[ -f "$TPLF" ]]'
ck "whitelist: sem users/admin/id/datas absolutas" '[[ "$(jq -r ".templates[\"prova ed\"].spec | has(\"users\") or has(\"admin\") or has(\"id\") or has(\"start\") or has(\"end\")" "$TPLF")" == false ]]'
ck "relativo: duration=10800 freeze_before_end=3600" '[[ "$(jq -r ".templates[\"prova ed\"].spec.duration" "$TPLF")" == 10800 && "$(jq -r ".templates[\"prova ed\"].spec.freeze_before_end" "$TPLF")" == 3600 ]]'
call /treino/contest-create/templates GET '' reg
ck "list traz o template"   '[[ "$(jq -r ".templates[0].name" <<<"$BODY")" == "prova ed" && "$(jq -r ".templates[0].mode" <<<"$BODY")" == icpc ]]'
call /treino/contest-create/templates GET '' reg 'name=prova%20ed'
ck "get por nome"           '[[ "$(jq -r ".template.spec.priority" <<<"$BODY")" == prova ]]'
call /treino/contest-create/templates GET '' eve 'name=prova%20ed'
ck "template é por usuário (eve 404)" '[[ "$OUT" == *"Status: 404"* ]]'
call /treino/contest-create/templates POST '{"op":"rename","name":"prova ed","new_name":"prova ed2"}' reg
ck "rename"                 '[[ "$(jq -r .renamed <<<"$BODY")" == true ]]'
call /treino/contest-create/templates POST '{"op":"delete","name":"prova ed2"}' reg
ck "delete"                 '[[ "$(jq -r .deleted <<<"$BODY")" == true ]]'
call /treino/contest-create/templates POST '{"op":"delete","name":"prova ed2"}' reg
ck "delete de inexistente 404" '[[ "$OUT" == *"Status: 404"* ]]'

echo "== templates: save from_contest (gate de dono) =="
call /treino/contest-create/templates POST '{"op":"save","name":"da-prova","from_contest":"orig-c","include_problems":true}' reg
ck "dono salva do contest"  '[[ "$(jq -r .saved <<<"$BODY")" == true ]]'
ck "template tem problemas sem enunciado embutido" '[[ "$(jq -r ".templates[\"da-prova\"].spec.problems|length" "$TPLF")" == 2 && "$(jq -r ".templates[\"da-prova\"].spec.problems[1]|has(\"statement_b64\")" "$TPLF")" == false ]]'
call /treino/contest-create/templates POST '{"op":"save","name":"rouba","from_contest":"orig-c"}' eve
ck "não-dono from_contest 404" '[[ "$OUT" == *"Status: 404"* ]]'
call /treino/contest-create/templates POST '{"op":"save","name":"boss-tpl","from_contest":"orig-c"}' adm
ck "admin from_contest 200" '[[ "$(jq -r .saved <<<"$BODY")" == true ]]'

echo "== export (gate + conteúdo) =="
call /treino/contest-create/export GET '' reg 'id=orig-c'
ck "dono exporta (attachment)" '[[ "$OUT" == *"Content-Disposition"* ]]'
ck "spec sem passwd/senhas"  '[[ "$(printf "%s" "$BODY" | grep -ci "password\|passwd")" == 0 ]]'
ck "spec com toggles/priority" '[[ "$(jq -r .priority <<<"$BODY")" == prova && "$(jq -r .score_anon <<<"$BODY")" == true && "$(jq -r .show_log <<<"$BODY")" == false ]]'
ck "langs por problema no export" '[[ "$(jq -rc ".problems[0].languages" <<<"$BODY")" == "[\"c\"]" ]]'
ck "penalidade no export"    '[[ "$(jq -r .penalty_minutes <<<"$BODY")" == 15 && "$(jq -rc .penalty_verdicts <<<"$BODY")" == "[\"wa\",\"ce\"]" ]]'
ck "auto: custom embutido, banco não" '[[ "$(jq -r ".problems[1]|has(\"statement_b64\")" <<<"$BODY")" == true && "$(jq -r ".problems[0]|has(\"statement_b64\")" <<<"$BODY")" == false ]]'
EXPORTED="$BODY"
call /treino/contest-create/export GET '' reg 'id=orig-c&full_statements=1'
ck "full: banco também embutido" '[[ "$(jq -r ".problems[0]|has(\"statement_b64\")" <<<"$BODY")" == true ]]'
call /treino/contest-create/export GET '' eve 'id=orig-c'
ck "não-dono export 404"    '[[ "$OUT" == *"Status: 404"* ]]'
call /treino/contest-create/export GET '' adm 'id=orig-c'
ck "admin export 200"       '[[ "$OUT" == *"Content-Disposition"* ]]'
mkdir -p "$FIX/legacy"; printf 'CONTEST_ID=legacy\n' > "$FIX/legacy/conf"
call /treino/contest-create/export GET '' adm 'id=legacy'
ck "legado sem created-by 404" '[[ "$OUT" == *"Status: 404"* ]]'

echo "== round-trip: export -> create =="
RT="$(jq -c '.id="rt-c" | .name="Round Trip" | .end='"$FUT" <<<"$EXPORTED")"
call /treino/contest-create/create POST "$RT" reg
ck "criou do export"        '[[ "$(jq -r .contest_id <<<"$BODY")" == "rt-c" ]]'
ck "toggles no conf novo"   'grep -q "^SCORE_ANON=1" "$FIX/rt-c/conf" && grep -q "^SHOWLOG=0" "$FIX/rt-c/conf"'
ck "penalidade no conf novo" '[[ "$( . "$FIX/rt-c/conf"; echo "$PENALTY_MINUTES/$PENALTY_VERDICTS" )" == "15/wa ce" ]]'
ck "enunciado custom no novo" '[[ -f "$FIX/rt-c/enunciados/x#custom.html" ]]'
ck "problem-langs no novo"  '[[ "$(jq -rc ".[\"bankprob\"]" "$FIX/rt-c/problem-langs.json")" == "[\"c\"]" ]]'

echo "== duplicate =="
call /treino/contest-create/duplicate POST '{"from":"orig-c","id":"dup-c"}' reg
ck "duplicou"               '[[ "$(jq -r .contest_id <<<"$BODY")" == "dup-c" ]]'
ck "nome default Cópia de"  '[[ "$( . "$FIX/dup-c/conf"; echo "$CONTEST_NAME" )" == "Cópia de Original" ]]'
ck "sem usuários copiados (só admin)" '[[ "$(ls "$FIX/dup-c/users" | wc -l)" == 1 && -f "$FIX/dup-c/users/regular.admin/account.json" ]]'
ck "duração preservada (10800)" '[[ "$( . "$FIX/dup-c/conf"; echo $((CONTEST_END - CONTEST_START)) )" == 10800 ]]'
ck "freeze relativo preservado" '[[ "$( . "$FIX/dup-c/conf"; echo $((CONTEST_END - FREEZE_TIME)) )" == 3600 ]]'
ck "enunciado custom copiado por arquivo" '[[ -f "$FIX/dup-c/enunciados/x#custom.html" ]]'
ck "toggles copiados"       'grep -q "^SCORE_ANON=1" "$FIX/dup-c/conf"'
ck "penalidade copiada"     '[[ "$( . "$FIX/dup-c/conf"; echo "$PENALTY_MINUTES/$PENALTY_VERDICTS" )" == "15/wa ce" ]]'
call /treino/contest-create/duplicate POST '{"from":"orig-c"}' eve
ck "não-dono duplicate 404" '[[ "$OUT" == *"Status: 404"* ]]'

echo "== mine =="
call /treino/contest-create/mine GET '' reg
ck "mine lista os do regular (orig-c, rt-c, dup-c)" '[[ "$(jq -r .total <<<"$BODY")" == 3 ]]'
ck "mine traz contagem de problemas" '[[ "$(jq -r ".contests[]|select(.id==\"orig-c\").problems_count" <<<"$BODY")" == 2 ]]'
call /treino/contest-create/mine GET '' eve
ck "mine da eve vazio"      '[[ "$(jq -r .total <<<"$BODY")" == 0 ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
