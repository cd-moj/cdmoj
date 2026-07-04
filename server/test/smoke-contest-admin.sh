#!/bin/bash
# Testa o admin DO contest: config (GET/POST de cores/regiões/teams-meta/basic) e usuários
# (add/reset/remove), + as proteções de acesso (precisa ser .admin daquele contest).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
T="$FIX/treino"; mkdir -p "$T/var/jsons" "$T/controle"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\n' > "$T/conf"
printf 'boss.admin:p:Boss\nregular:s:Regular\n' > "$T/passwd"
printf '{"threshold":0,"allow":["regular"],"deny":[]}' > "$T/var/contest-perms.json"
printf 'CONTEST=treino\nLOGIN=regular\nUSERFULLNAME=Regular\nLOGINAT=1\n' > "$SESS/reg"
printf '%s' '{"id":"bankprob","title":"Banco","tags":["#x"],"statement_html_b64":"PGgxPm9pPC9oMT4="}' > "$T/var/jsons/bankprob.json"
printf '%s' '{"id":"apc#vet","title":"Vetores","tags":["#vetor"],"collections":["Prova 1"]}' > "$T/var/jsons/apc#vet.json"
mkdir -p "$T/var/jsons-private"
printf '%s' '{"id":"secret#x","title":"Prova Secreta","tags":[]}' > "$T/var/jsons-private/secret#x.json"
# índice de owners (fresco => ensure_owners_index não regenera): público + privados p/ o gate do add
printf '%s' '{"problems":[
 {"id":"bankprob","title":"Banco","owner":"someone","collaborators":[],"public":true},
 {"id":"priv#mine","title":"Prova Secreta Minha","owner":"regular","collaborators":[],"public":false},
 {"id":"priv#collab","title":"Colab Prob","owner":"eve","collaborators":["regular"],"public":false},
 {"id":"priv#other","title":"Alheia","owner":"eve","collaborators":[],"public":false}
]}' > "$T/var/problem-owners.json"
mkdir -p "$T/var/jsons-private"
printf '%s' '{"id":"priv#mine","title":"Prova Secreta Minha","statement_html_b64":"PHA+czwvcD4="}' > "$T/var/jsons-private/priv#mine.json"
: > "$T/controle/history"
NOW="$(date +%s)"; FUT=$(( NOW + 100000 ))
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-reg}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

# cria um contest com 2 problemas + 1 regra teams-meta; admin = boss.admin
SPEC="{\"id\":\"ac-c\",\"name\":\"AC Contest\",\"mode\":\"icpc\",\"end\":$FUT,\"admin\":{\"login\":\"boss\",\"password\":\"sek\",\"fullname\":\"Boss\"},\"problems\":[{\"bank_id\":\"bankprob\",\"name\":\"P1\",\"letter\":\"A\"},{\"source\":\"cdmoj\",\"problem_id\":\"x/y\",\"name\":\"P2\",\"letter\":\"B\"}],\"teams_meta\":[{\"regex\":\"^br-\",\"country\":\"BR\",\"school\":\"UnB\"}]}"
call /treino/contest-create/create POST "$SPEC" reg
ADM="$(jq -r .admin_login <<<"$BODY")"
[[ "$ADM" == "boss.admin" ]] && echo "(criou ac-c, admin=$ADM)" || { echo "SETUP FAIL: $BODY"; exit 1; }
# sessões DO contest
printf 'CONTEST=ac-c\nLOGIN=boss.admin\nUSERFULLNAME=Boss\nLOGINAT=1\n' > "$SESS/cadm"
printf 'CONTEST=ac-c\nLOGIN=alice\nUSERFULLNAME=Alice\nLOGINAT=1\n' > "$SESS/cuser"

echo "== config GET =="
call /contest/admin/config GET '' cadm 'contest=ac-c'
ck "letters A,B"        '[[ "$(jq -rc ".letters" <<<"$BODY")" == "[\"A\",\"B\"]" ]]'
ck "teams_meta veio"    '[[ "$(jq -r ".teams_meta[0].country" <<<"$BODY")" == "BR" ]]'
ck "basic.locale pt"    '[[ "$(jq -r ".basic.locale" <<<"$BODY")" == "pt" ]]'

echo "== config POST (cores/teams/basic) =="
call /contest/admin/config POST '{"colors":{"A":"00FF00","enableSonic":true},"teams_meta":[{"regex":"^usp-","country":"BR-SP","school":"USP"}],"basic":{"locale":"en","login_enabled":false}}' cadm 'contest=ac-c'
ck "salvou"             '[[ "$(jq -r .saved <<<"$BODY")" == "true" ]]'
ck "balloons.json A"    '[[ "$(jq -r .A < "$FIX/ac-c/balloons.json")" == "00FF00" ]]'
ck "teams-meta trocado" '[[ "$(jq -r ".rules[0].school" < "$FIX/ac-c/teams-meta.json")" == "USP" ]]'
ck "conf LOCALE=en"     'grep -q "^LOCALE=en" "$FIX/ac-c/conf"'
ck "conf LOGIN_ENABLED=n" 'grep -q "^LOGIN_ENABLED=n" "$FIX/ac-c/conf"'
call /contest/basic GET '' cadm 'contest=ac-c'
ck "basic.sh reflete en/login_enabled" '[[ "$(jq -r .locale <<<"$BODY")" == "en" && "$(jq -r .login_enabled <<<"$BODY")" == "false" ]]'

echo "== usuários =="
call /contest/admin/users GET '' cadm 'contest=ac-c'
ck "lista tem boss.admin" '[[ "$(jq -r ".users[]|select(.login==\"boss.admin\")|.admin" <<<"$BODY")" == "true" ]]'
call /contest/admin/user-add POST '{"login":"u9","fullname":"U Nine"}' cadm 'contest=ac-c'
ck "add u9 + senha gerada" '[[ "$(jq -r .user.login <<<"$BODY")" == "u9" && -n "$(jq -r .user.password <<<"$BODY")" ]]'
ck "passwd tem u9"      'grep -q "^u9:" "$FIX/ac-c/passwd"'
call /contest/admin/user-add POST '{"login":"u9","password":"reset123","fullname":"U Nine"}' cadm 'contest=ac-c'
ck "reset senha u9"     'grep -q "^u9:reset123:" "$FIX/ac-c/passwd"'
call /contest/admin/user-remove POST '{"login":"u9"}' cadm 'contest=ac-c'
ck "removeu u9"         '[[ "$(jq -r .removed <<<"$BODY")" == "true" ]] && ! grep -q "^u9:" "$FIX/ac-c/passwd"'
call /contest/admin/user-remove POST '{"login":"boss.admin"}' cadm 'contest=ac-c'
ck "não remove a si mesmo 409" '[[ "$OUT" == *"Status: 409"* ]]'

echo "== bank: busca unificada (privados do dono do contest) =="
call /contest/admin/bank GET '' cadm 'contest=ac-c'
ck "privados do dono vêm primeiro" '[[ "$(jq -r ".problems[0].private" <<<"$BODY")" == true ]]'
ck "priv#mine com título e access:mine" '[[ "$(jq -r ".problems[]|select(.id==\"priv#mine\")|.title" <<<"$BODY")" == "Prova Secreta Minha" && "$(jq -r ".problems[]|select(.id==\"priv#mine\")|.access" <<<"$BODY")" == mine ]]'
ck "priv#collab access:shared"  '[[ "$(jq -r ".problems[]|select(.id==\"priv#collab\")|.access" <<<"$BODY")" == shared ]]'
ck "priv#other NÃO aparece"     '[[ "$(jq -r "[.problems[].id]|index(\"priv#other\")" <<<"$BODY")" == null ]]'
ck "has_statement: mine sim, collab não" '[[ "$(jq -r ".problems[]|select(.id==\"priv#mine\")|.has_statement" <<<"$BODY")" == true && "$(jq -r ".problems[]|select(.id==\"priv#collab\")|.has_statement" <<<"$BODY")" == false ]]'
call /contest/admin/bank GET '' cadm 'contest=ac-c&q=secreta'
ck "busca acha privado por título" '[[ "$(jq -r ".problems[0].id" <<<"$BODY")" == "priv#mine" && "$(jq -r .mine <<<"$BODY")" == 1 ]]'

echo "== problemas: add com gate de privado =="
call /contest/admin/problems POST '{"action":"add","problem":{"bank_id":"bankprob","name":"Pub"}}' cadm 'contest=ac-c'
ck "add público 200"            '[[ "$(jq -r .saved <<<"$BODY")" == "true" ]]'
call /contest/admin/problems POST '{"action":"add","problem":{"bank_id":"priv#mine","name":"Meu"}}' cadm 'contest=ac-c'
ck "privado do dono do contest 200" '[[ "$(jq -r .saved <<<"$BODY")" == "true" ]]'
call /contest/admin/problems POST '{"action":"add","problem":{"problem_id":"priv/collab","name":"Colab"}}' cadm 'contest=ac-c'
ck "privado com dono colaborador 200" '[[ "$(jq -r .saved <<<"$BODY")" == "true" ]]'
call /contest/admin/problems POST '{"action":"add","problem":{"bank_id":"priv#other","name":"Alheio"}}' cadm 'contest=ac-c'
ck "privado alheio 404"         '[[ "$OUT" == *"Status: 404"* ]]'
call /contest/admin/problems POST '{"action":"add","problem":{"source":"forjado","problem_id":"priv/other","name":"Bypass"}}' cadm 'contest=ac-c'
ck "source forjado não pula o gate (404)" '[[ "$OUT" == *"Status: 404"* ]]'
rm -f "$FIX/ac-c/owner"
call /contest/admin/problems POST '{"action":"add","problem":{"bank_id":"priv#mine","name":"Meu2"}}' cadm 'contest=ac-c'
ck "contest sem owner: privado 404" '[[ "$OUT" == *"Status: 404"* ]]'

echo "== banco/sorteio no admin do contest =="
call /contest/admin/bank GET '' cadm 'contest=ac-c&q=vetores'
ck "bank acha por título"       '[[ "$(jq -r ".problems[0].id" <<<"$BODY")" == "apc#vet" ]]'
call /contest/admin/bank GET '' cadm 'contest=ac-c&collection=Prova%201'
ck "bank filtra por coleção"    '[[ "$(jq -r .total <<<"$BODY")" == 1 && "$(jq -r ".problems[0].id" <<<"$BODY")" == "apc#vet" ]]'
call /contest/admin/bank GET '' cadm 'contest=ac-c'
ck "privado NÃO aparece no bank" '[[ "$(jq -r "[.problems[].id]|index(\"secret#x\")" <<<"$BODY")" == null ]]'
ck "sem owner: busca não lista privados" '[[ "$(jq -r "[.problems[]|select(.private)]|length" <<<"$BODY")" == 0 ]]'
call /contest/admin/bank GET '' cadm 'contest=ac-c&meta=1'
ck "meta=1: tags e coleções"    '[[ "$(jq -r ".collections[0].collection" <<<"$BODY")" == "Prova 1" && "$(jq -r ".tags|length" <<<"$BODY")" -ge 2 ]]'
call /contest/admin/bank GET '' cuser 'contest=ac-c'
ck "bank de aluno 403"          '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/admin/draw GET '' cadm 'contest=ac-c&collections=%5B%22Prova%201%22%5D&count=5&seed=3'
ck "draw por coleção no admin"  '[[ "$(jq -r .candidates <<<"$BODY")" == 1 && "$(jq -r ".problems[0].id" <<<"$BODY")" == "apc#vet" ]]'
call /contest/admin/draw GET '' cadm 'contest=ac-c&count=2&seed=42'
D1="$(jq -rc '[.problems[].id]' <<<"$BODY")"
call /contest/admin/draw GET '' cadm 'contest=ac-c&count=2&seed=42'
ck "draw reproduzível por seed" '[[ "$(jq -rc "[.problems[].id]" <<<"$BODY")" == "$D1" ]]'
call /contest/admin/draw GET '' cuser 'contest=ac-c&count=2'
ck "draw de aluno 403"          '[[ "$OUT" == *"Status: 403"* ]]'

echo "== letras além de Z (AA, AB, …) =="
for i in $(seq 1 25); do
  call /contest/admin/problems POST "{\"action\":\"add\",\"problem\":{\"bank_id\":\"bankprob\",\"name\":\"P$i\"}}" cadm 'contest=ac-c' >/dev/null
done
call /contest/admin/problems GET '' cadm 'contest=ac-c'
NPROB="$(jq -r '.problems|length' <<<"$BODY")"
ck "30 problemas"               '[[ "$NPROB" == 30 ]]'
ck "27º recebe letra AA"        '[[ "$(jq -r ".problems[26].letter" <<<"$BODY")" == "AA" ]]'
ORD="$(jq -c '[.problems[].letter]|reverse' <<<"$BODY")"
call /contest/admin/problems POST "{\"action\":\"reorder\",\"order\":$ORD}" cadm 'contest=ac-c'
ck "reorder >26 sem letra inválida" '[[ "$(jq -r "[.problems[].letter]|join(\",\")" <<<"$BODY")" == *"Z,AA,AB,AC,AD"* ]]'
ck "reorder inverteu (último virou A)" '[[ "$(jq -r ".problems[0].name" <<<"$BODY")" == "P25" ]]'

echo "== proteções de acesso =="
call /contest/admin/config GET '' cuser 'contest=ac-c'
ck "não-admin do contest 403" '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/admin/config GET '' reg 'contest=ac-c'
ck "sessão de outro contest 403" '[[ "$OUT" == *"Status: 403"* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
