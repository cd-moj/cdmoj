#!/bin/bash
# SHOWLOG efetivo (showlog_effective em lib/verdict.sh): em modo icpc, SHOWLOG ausente do
# conf = log OCULTO ao dono (o report.html expõe input+diff de TODOS os testes — anti-
# vazamento de prova); explícito manda; demais modos seguem visíveis. O settings POST
# religa gravando SHOWLOG=1 explícito e o GET devolve o valor EFETIVO.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
SID="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

mkc(){ # <id> <type> [linha extra de conf]
  local C="$FIX/$1"; mkdir -p "$C/var"
  { printf 'CONTEST_ID=%s\nCONTEST_TYPE=%s\nCONTEST_START=1000\nCONTEST_END=2000\nUSER_STORE=v2\n' "$1" "$2"
    [[ -n "${3:-}" ]] && printf '%s\n' "$3"
    printf "PROBS=(f0 col/pa 'Prob A' A 'col#pa')\n"; } > "$C/conf"
  fx_user "$C" "$1.admin" p "Admin"
  fx_user "$C" alice a "Alice"
  printf '5:col#pa:C:Accepted,100p:1718000000:%s\n' "$SID" > "$C/users/alice/history"
  printf 'int main(){return 0;}\n' > "$C/users/alice/submissions/$SID.c"
  printf '<html>report</html>\n'   > "$C/users/alice/mojlog/$SID.html"
}
mktok(){ printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' "$1" "$2" "$2" "$EPOCHSECONDS" > "$SESS/$3"; }

mkc icy icpc                       # icpc sem SHOWLOG -> oculto
mkc ion icpc 'SHOWLOG=1'           # icpc com SHOWLOG=1 -> visível
mkc lst lista-publica              # treino sem SHOWLOG -> visível
mktok icy alice t-icy-a; mktok icy icy.admin t-icy-adm
mktok ion alice t-ion-a
mktok lst alice t-lst-a
mktok icy icy.judge t-icy-j; fx_user "$FIX/icy" icy.judge j "Judge"

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${4:-}" HTTP_AUTHORIZATION="Bearer $3" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${5:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${OUT:0:200}"; ((fail++)); fi; }

echo "== icpc sem SHOWLOG: log OCULTO ao dono, aberto a admin/judge =="
call /submission/log GET t-icy-a "contest=icy&id=$SID"
ck "dona 403 log_hidden"        '[[ "$OUT" == *"Status: 403"* && "$OUT" == *log_hidden* ]]'
call /submission/log GET t-icy-adm "contest=icy&id=$SID"
ck "admin 200"                  '[[ "$OUT" == *"Status: 200"* && "$BODY" == *report* ]]'
call /submission/log GET t-icy-j "contest=icy&id=$SID"
ck "judge 200"                  '[[ "$OUT" == *"Status: 200"* && "$BODY" == *report* ]]'
call /contest/userinfo GET t-icy-a "contest=icy"
ck "userinfo show_log=false"    '[[ "$(jq -r .show_log <<<"$BODY")" == "false" ]]'
call /contest/admin/settings GET t-icy-adm "contest=icy"
ck "settings GET show_log=false (efetivo)" '[[ "$(jq -r .show_log <<<"$BODY")" == "false" ]]'

echo "== icpc com SHOWLOG=1 explícito: visível =="
call /submission/log GET t-ion-a "contest=ion&id=$SID"
ck "dona 200"                   '[[ "$OUT" == *"Status: 200"* && "$BODY" == *report* ]]'
call /contest/userinfo GET t-ion-a "contest=ion"
ck "userinfo show_log=true"     '[[ "$(jq -r .show_log <<<"$BODY")" == "true" ]]'

echo "== lista-publica sem SHOWLOG: comportamento clássico (visível) =="
call /submission/log GET t-lst-a "contest=lst&id=$SID"
ck "dona 200"                   '[[ "$OUT" == *"Status: 200"* && "$BODY" == *report* ]]'
call /contest/userinfo GET t-lst-a "contest=lst"
ck "userinfo show_log=true"     '[[ "$(jq -r .show_log <<<"$BODY")" == "true" ]]'

echo "== settings POST: religar grava SHOWLOG=1 explícito; desligar grava 0 =="
call /contest/admin/settings POST t-icy-adm "contest=icy" '{"show_log":true}'
ck "POST true ok"               '[[ "$(jq -r .saved <<<"$BODY")" == "true" ]]'
ck "conf tem SHOWLOG=1"         'grep -q "^SHOWLOG=1$" "$FIX/icy/conf"'
call /submission/log GET t-icy-a "contest=icy&id=$SID"
ck "dona agora 200"             '[[ "$OUT" == *"Status: 200"* ]]'
call /contest/admin/settings POST t-icy-adm "contest=icy" '{"show_log":false}'
ck "conf tem SHOWLOG=0"         'grep -q "^SHOWLOG=0$" "$FIX/icy/conf"'
call /submission/log GET t-icy-a "contest=icy&id=$SID"
ck "dona volta a 403"           '[[ "$OUT" == *"Status: 403"* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
