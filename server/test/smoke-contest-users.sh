#!/bin/bash
# Testa usuários do contest (próprios/compartilhados + admin obrigatório), criar vazio,
# senhas legíveis, listagem de tags e sorteio de problemas, e o login com fallback USERS_FROM.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
T="$FIX/treino"; mkdir -p "$T/var/jsons"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\n' > "$T/conf"
fx_user "$T" boss.admin p "Boss"
fx_user "$T" regular s "Regular User"
printf '{"threshold":0,"allow":["regular"],"deny":[]}' > "$T/var/contest-perms.json"
printf 'CONTEST=treino\nLOGIN=boss.admin\nUSERFULLNAME=Boss\nLOGINAT=1\n' > "$SESS/adm"
printf 'CONTEST=treino\nLOGIN=regular\nUSERFULLNAME=Regular User\nLOGINAT=1\n' > "$SESS/reg"
printf '%s' '{"id":"bankprob","title":"Banco Prob","tags":["#x","#easy"],"statement_html_b64":"PGgxPm9pPC9oMT4="}' > "$T/var/jsons/bankprob.json"
printf '%s' '{"id":"p2","title":"Problema Dois","tags":["#x"]}' > "$T/var/jsons/p2.json"
printf '%s' '{"id":"p3","title":"Problema Tres","tags":["#y"]}' > "$T/var/jsons/p3.json"
{ printf '1:bankprob:C:Accepted,100p:1:h1\n'; printf '3:p2:C:Wrong Answer:3:h3\n'; } > "$T/users/regular/history"
printf '2:bankprob:C:Accepted,100p:2:h2\n' > "$T/users/boss.admin/history"

NOW="$(date +%s)"; FUT=$(( NOW + 100000 ))
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-reg}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
login(){ LOUT="$(PATH_INFO=/auth/login REQUEST_METHOD=POST QUERY_STRING="contest=$1" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"{\"username\":\"$2\",\"password\":\"$3\"}" 2>&1)"
  LBODY="$(printf '%s' "$LOUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

echo "== senhas legíveis =="
call /treino/contest-create/genpass GET '' reg 'n=5'
ck "5 senhas"          '[[ "$(jq -r ".passwords|length" <<<"$BODY")" == 5 ]]'
ck "senha não-vazia"   '[[ -n "$(jq -r ".passwords[0]" <<<"$BODY")" ]]'

echo "== tags do banco =="
call /treino/contest-create/tags GET '' reg
ck "tag #x com contagem 2" '[[ "$(jq -r ".tags[]|select(.tag==\"#x\")|.count" <<<"$BODY")" == 2 ]]'

echo "== sorteio por tag =="
call /treino/contest-create/draw GET '' reg 'tags=%23x&count=1&seed=42'
ck "candidatos=2 (#x)"  '[[ "$(jq -r ".candidates" <<<"$BODY")" == 2 ]]'
ck "sorteou 1"          '[[ "$(jq -r ".drawn" <<<"$BODY")" == 1 ]]'
ck "seed reproduzível"  '[[ "$(jq -r ".seed" <<<"$BODY")" == 42 ]]'
call /treino/contest-create/draw GET '' reg 'tags=%23y&count=9'
ck "poucos candidatos (#y=1)" '[[ "$(jq -r ".candidates" <<<"$BODY")" == 1 && "$(jq -r ".drawn" <<<"$BODY")" == 1 ]]'

echo "== criar com usuários próprios + admin custom =="
SPEC="{\"id\":\"own-c\",\"name\":\"Own\",\"mode\":\"icpc\",\"end\":$FUT,\"admin\":{\"login\":\"chief\",\"password\":\"sek123\",\"fullname\":\"Chief\"},\"users\":[{\"login\":\"u1\",\"fullname\":\"User One\"},{\"login\":\"u2\",\"password\":\"p2pass\",\"fullname\":\"User Two\",\"email\":\"u2@x.com\"}],\"problems\":[{\"bank_id\":\"bankprob\",\"name\":\"P1\",\"letter\":\"A\"}]}"
call /treino/contest-create/create POST "$SPEC" reg
ck "criou own-c"        '[[ "$(jq -r .contest_id <<<"$BODY")" == "own-c" ]]'
ck "admin = chief.admin" '[[ "$(jq -r .admin_login <<<"$BODY")" == "chief.admin" ]]'
ck "3 credenciais"      '[[ "$(jq -r .users_count <<<"$BODY")" == 3 ]]'
ck "u1 ganhou senha"    '[[ -n "$(jq -r ".users[]|select(.login==\"u1\")|.password" <<<"$BODY")" ]]'
ck "store: chief.admin:sek123" '[[ "$(jq -r .password "$FIX/own-c/users/chief.admin/account.json")" == "sek123" ]]'
ck "store: u2 com email" '[[ "$(jq -r .email "$FIX/own-c/users/u2/account.json")" == "u2@x.com" && "$(jq -r .password "$FIX/own-c/users/u2/account.json")" == "p2pass" ]]'

echo "== criar compartilhado (USERS_FROM=treino) + login fallback =="
SPEC2="{\"id\":\"shared-c\",\"name\":\"Shared\",\"mode\":\"icpc\",\"end\":$FUT,\"users_from\":\"treino\",\"problems\":[{\"bank_id\":\"bankprob\",\"name\":\"P1\",\"letter\":\"A\"}]}"
call /treino/contest-create/create POST "$SPEC2" reg
ADMPW="$(jq -r .admin_password <<<"$BODY")"
ck "criou shared-c"     '[[ "$(jq -r .contest_id <<<"$BODY")" == "shared-c" ]]'
ck "users_from=treino"  '[[ "$(jq -r .users_from <<<"$BODY")" == "treino" ]]'
ck "conf tem USERS_FROM" 'grep -q "^USERS_FROM=treino" "$FIX/shared-c/conf"'
ck "store só tem o admin (1 conta)" '[[ "$(ls "$FIX/shared-c/users" | wc -l)" == 1 ]]'
login shared-c regular s
ck "login fallback (treino) ok" '[[ "$(jq -r .logged_in <<<"$LBODY")" == "true" ]]'
login shared-c regular.admin "$ADMPW"
ck "login admin do contest ok"  '[[ "$(jq -r .logged_in <<<"$LBODY")" == "true" ]]'
login shared-c regular errada
ck "senha errada 401"           '[[ "$LOUT" == *"Status: 401"* ]]'

echo "== criar vazio (só admin obrigatório) =="
SPEC3="{\"id\":\"empty-c\",\"name\":\"Empty\",\"mode\":\"icpc\",\"end\":$FUT,\"allow_empty\":true}"
call /treino/contest-create/create POST "$SPEC3" reg
ck "criou vazio"        '[[ "$(jq -r .contest_id <<<"$BODY")" == "empty-c" ]]'
ck "0 problemas"        '[[ "$(jq -r .problems <<<"$BODY")" == 0 && "$( . "$FIX/empty-c/conf"; echo ${#PROBS[@]} )" == 0 ]]'
ck "tem admin no store" '[[ -f "$FIX/empty-c/users/regular.admin/account.json" ]]'
call /treino/contest-create/create POST "{\"name\":\"NoProb\",\"mode\":\"icpc\",\"end\":$FUT}" reg
ck "sem problema e sem allow_empty 422" '[[ "$OUT" == *"Status: 422"* ]]'

echo "== configs visuais na criação + endpoints (cores/sonic/regiões/teams-meta) =="
SPEC4="{\"id\":\"viz-c\",\"name\":\"Viz\",\"mode\":\"icpc\",\"end\":$FUT,\"allow_empty\":true,\"colors\":{\"A\":\"FF0000\",\"enableSonic\":true},\"regions\":[{\"name\":\"Brasil\",\"regex\":\"^br-\"}],\"teams_meta\":[{\"regex\":\"^br-df-\",\"country\":\"BR-DF\",\"school\":\"UnB\",\"school_full\":\"Universidade de Brasília\"}]}"
call /treino/contest-create/create POST "$SPEC4" reg
ck "criou viz-c"             '[[ "$(jq -r .contest_id <<<"$BODY")" == "viz-c" ]]'
ck "balloons.json (A=FF0000)" '[[ "$(jq -r .A < "$FIX/viz-c/balloons.json")" == "FF0000" ]]'
ck "regions.json gravado"    '[[ -f "$FIX/viz-c/regions.json" ]]'
ck "teams-meta {rules}"      '[[ "$(jq -r ".rules[0].country" < "$FIX/viz-c/teams-meta.json")" == "BR-DF" ]]'
call /contest/teams-meta GET '' reg 'contest=viz-c'
ck "endpoint teams-meta"     '[[ "$(jq -r ".rules[0].school" <<<"$BODY")" == "UnB" ]]'
call /contest/balloons GET '' reg 'contest=viz-c'
ck "balloons + sonic"        '[[ "$(jq -r ".balloons.enableSonic" <<<"$BODY")" == "true" && "$(jq -r ".balloons.A" <<<"$BODY")" == "FF0000" ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
