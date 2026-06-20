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

echo "== proteções de acesso =="
call /contest/admin/config GET '' cuser 'contest=ac-c'
ck "não-admin do contest 403" '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/admin/config GET '' reg 'contest=ac-c'
ck "sessão de outro contest 403" '[[ "$OUT" == *"Status: 403"* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
