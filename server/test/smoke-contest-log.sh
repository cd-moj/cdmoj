#!/bin/bash
# Item 3: sessões/log do contest (admin), alerta de UA/IP diferentes, e gate de login por UA.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
C="$FIX/lc"; mkdir -p "$C/var"
printf 'CONTEST_ID=lc\nCONTEST_TYPE=icpc\nLOGIN_UA_SUBSTRING=MOJBOX\nUSER_STORE=v2\n' > "$C/conf"
fx_user "$C" lc.admin p "Admin"
fx_user "$C" alice a "Alice"
b64(){ printf '%s' "$1" | base64 -w0; }
# sessões: alice de 2 IPs/UAs (anomalia) + admin
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\nIP=%q\nUA_B64=%q\n' lc alice Alice 100 1.1.1.1 "$(b64 Browser1)" > "$SESS/s1"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\nIP=%q\nUA_B64=%q\n' lc alice Alice 200 2.2.2.2 "$(b64 Browser2)" > "$SESS/s2"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\nIP=%q\nUA_B64=%q\n' lc lc.admin Admin 300 3.3.3.3 "$(b64 Browser3)" > "$SESS/adm"
printf 'CONTEST=%q\nLOGIN=%q\nLOGINAT=%q\n' lc alice 100 > "$SESS/aliceonly"
# access.log: alice de 2 IPs/UAs + admin
{ printf '%s\t%s\t%s\t%s\n' 1718000000 alice 1.1.1.1 "$(b64 Browser1)"
  printf '%s\t%s\t%s\t%s\n' 1718000100 alice 2.2.2.2 "$(b64 Browser2)"
  printf '%s\t%s\t%s\t%s\n' 1718000200 lc.admin 3.3.3.3 "$(b64 Browser3)"; } > "$C/var/access.log"

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-adm}" HTTP_USER_AGENT="${6:-}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

echo "== sessões + alerta UA/IP =="
call /contest/admin/sessions GET '' adm 'contest=lc'
ck "4 sessões"           '[[ "$(jq -r .count <<<"$BODY")" == 4 ]]'
ck "alerta p/ alice (multi ip+ua)" '[[ "$(jq -r ".alerts[]|select(.login==\"alice\")|.multi_ip" <<<"$BODY")" == "true" && "$(jq -r ".alerts[]|select(.login==\"alice\")|.multi_ua" <<<"$BODY")" == "true" ]]'
ck "admin sem anomalia"  '[[ "$(jq -r ".sessions[]|select(.login==\"lc.admin\")|.multi_ip" <<<"$BODY")" == "false" ]]'

echo "== log de acessos + alerta =="
call /contest/admin/access-log GET '' adm 'contest=lc'
ck "3 acessos"           '[[ "$(jq -r ".entries|length" <<<"$BODY")" == 3 ]]'
ck "UA decodificado"     '[[ "$(jq -r ".entries[]|select(.login==\"lc.admin\")|.user_agent" <<<"$BODY")" == "Browser3" ]]'
ck "alerta alice no log" '[[ "$(jq -r ".alerts[]|select(.login==\"alice\")|.multi_ua" <<<"$BODY")" == "true" ]]'

echo "== gate de login por UA =="
call /auth/login POST '{"username":"alice","password":"a"}' '' 'contest=lc' 'Mozilla MOJBOX-7 X'
ck "alice com UA correto loga" '[[ "$(jq -r .logged_in <<<"$BODY")" == "true" ]]'
call /auth/login POST '{"username":"alice","password":"a"}' '' 'contest=lc' 'Mozilla outro'
ck "alice com UA errado 403"   '[[ "$OUT" == *"Status: 403"* ]] && [[ "$(jq -r .error.code <<<"$BODY")" == "ua_gate" ]]'
call /auth/login POST '{"username":"lc.admin","password":"p"}' '' 'contest=lc' 'Mozilla outro'
ck "admin isento do gate"      '[[ "$(jq -r .logged_in <<<"$BODY")" == "true" ]]'

echo "== proteção: não-admin =="
call /contest/admin/sessions GET '' aliceonly 'contest=lc'
ck "alice (não-admin) 403"     '[[ "$OUT" == *"Status: 403"* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
