#!/bin/bash
# Itens 3/7/9: deslogar usuário, desabilitar, troca de senha geral, deslogar UA divergente.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
C="$FIX/uc"; mkdir -p "$C/var"
printf 'CONTEST_ID=uc\nCONTEST_TYPE=icpc\nLOGIN_UA_SUBSTRING=MOJBOX\nUSER_STORE=v2\n' > "$C/conf"
fx_user "$C" uc.admin p "Admin"
fx_user "$C" alice a "Alice"
fx_user "$C" bob b "Bob"
fx_user "$C" carol c "Carol"
fx_user "$C" jx.judge p "Judge"
fx_user "$C" cj.cjudge p "Chief"
fx_user "$C" dave d "Dave"        # sessão só existe p/ quem TEM conta (lib/auth.sh confere)
b64(){ printf '%s' "$1" | base64 -w0; }
mkses(){ printf 'CONTEST=uc\nLOGIN=%q\nUSERFULLNAME=x\nLOGINAT=1\nIP=1.1.1.1\nUA_B64=%q\n' "$2" "$(b64 "$3")" > "$SESS/$1"; }
printf 'CONTEST=uc\nLOGIN=uc.admin\nLOGINAT=1\n' > "$SESS/adm"
mkses dave dave "Moz MOJBOX dave"
mkses a1 alice "Moz MOJBOX 1"; mkses a2 alice "Moz MOJBOX 2"; mkses b1 bob "other"; mkses c1 carol "badUA"
mkses cj1 cj.cjudge "badUA"   # privilegiado com UA ruim: logout-mismatch NÃO pode derrubar
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-adm}" HTTP_USER_AGENT="${6:-}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:160}"; ((fail++)); fi; }

echo "== deslogar usuário =="
call /contest/admin/logout-user POST '{"login":"alice"}' adm 'contest=uc'
ck "removeu 2 sessões da alice" '[[ "$(jq -r .sessions_removed <<<"$BODY")" == 2 ]]'
ck "trilha: 2 eventos logout da alice, com quem deslogou" '[[ "$(grep -c "	alice	logout	" "$C/var/session-events.log")" == 2 ]] && grep -q "	uc.admin$" "$C/var/session-events.log"'

echo "== desabilitar =="
call /contest/admin/user-disable POST '{"login":"bob"}' adm 'contest=uc'
ck "bob desabilitado"        '[[ "$(jq -r .disabled <<<"$BODY")" == "true" ]]'
ck "passwd bob começa com !" '[[ "$(jq -r .password "$C/users/bob/account.json")" == \!* ]]'
call /contest/admin/user-disable POST '{"login":"jx.judge"}' adm 'contest=uc'
ck "não desabilita privilegiado 403" '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/admin/user-disable POST '{"login":"cj.cjudge"}' adm 'contest=uc'
ck "não desabilita .cjudge 403" '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/admin/users GET '' adm 'contest=uc'
ck "users: bob disabled=true"  '[[ "$(jq -r ".users[]|select(.login==\"bob\")|.disabled" <<<"$BODY")" == "true" ]]'

echo "== troca de senha geral =="
call /contest/admin/users-set-password POST '{"password":"prova2026"}' adm 'contest=uc'
ck "trocou 3 (alice,carol,dave; pula priv/disabled)" '[[ "$(jq -r .count <<<"$BODY")" == 3 ]]'
ck "alice:prova2026"         '[[ "$(jq -r .password "$C/users/alice/account.json")" == "prova2026" ]]'
ck "bob continua desabilitado" '[[ "$(jq -r .password "$C/users/bob/account.json")" == \!* ]]'
ck "admin intacto"           '[[ "$(jq -r .password "$C/users/uc.admin/account.json")" == "p" ]]'
ck ".cjudge intacto"         '[[ "$(jq -r .password "$C/users/cj.cjudge/account.json")" == "p" ]]'
call /contest/admin/users-set-password POST '{"password":"secreta","include_disabled":true}' adm 'contest=uc'
ck "com include_disabled troca 4" '[[ "$(jq -r .count <<<"$BODY")" == 4 ]]'
ck "bob reabilitado (secreta)" '[[ "$(jq -r .password "$C/users/bob/account.json")" == "secreta" ]]'

echo "== deslogar UA divergente =="
mkses a3 alice "Moz MOJBOX ok"   # alice com UA bom
call /contest/admin/logout-mismatch POST '{}' adm 'contest=uc'
ck "removeu só os de UA ruim (carol)" '[[ "$(jq -r .sessions_removed <<<"$BODY")" -ge 1 ]]'
ck "sessão da alice (UA bom) ficou" '[[ -f "$SESS/a3" ]]'
ck "sessão da carol (UA ruim) saiu" '[[ ! -f "$SESS/c1" ]]'
ck "sessão do .cjudge (privilegiado) ficou" '[[ -f "$SESS/cj1" ]]'
ck "trilha: mismatch-logout da carol"  'grep -q "	carol	mismatch-logout	" "$C/var/session-events.log"'

echo "== sair em massa + trava de login (logout-all) =="
fx_user "$C" s1.staff x "Staff 1"; fx_user "$C" cs.cstaff x "Chefe de sede"; fx_user "$C" tv.animeitor x "Telão"; fx_user "$C" mo.mon x "Monitor"
mkses st1 s1.staff "Moz"; mkses cs1 cs.cstaff "Moz"; mkses tv1 tv.animeitor "Moz"; mkses mo1 mo.mon "Moz"; mkses jx1 jx.judge "Moz"
mkses a4 alice "Moz"; mkses d2 dave "Moz"
call /contest/admin/logout-all GET '' adm 'contest=uc'
ck "GET: login aberto, contagens por classe" '[[ "$(jq -r .login_enabled <<<"$BODY")" == true && "$(jq -r .sessions.staff <<<"$BODY")" == 2 && "$(jq -r .sessions.competitors <<<"$BODY")" -ge 2 ]]'
call /contest/admin/logout-all POST '{"scope":"competitors","close_login":true}' adm 'contest=uc'
ck "competidores fora, staff e privilegiados FICAM, login fechado" '[[ "$(jq -r .competitors <<<"$BODY")" -ge 2 && "$(jq -r .staff <<<"$BODY")" == 0 && "$(jq -r .login_enabled <<<"$BODY")" == false && ! -f "$SESS/a4" && ! -f "$SESS/d2" && -f "$SESS/st1" && -f "$SESS/cs1" && -f "$SESS/tv1" && -f "$SESS/mo1" && -f "$SESS/jx1" && -f "$SESS/cj1" && -f "$SESS/adm" ]]'
ck "LOGIN_ENABLED=n no conf; audit logout-all" 'grep -q "^LOGIN_ENABLED=n$" "$C/conf" && grep -q "	logout-all	scope=competitors competitors=" "$C/var/admin-audit.log" && grep -q "login=closed" "$C/var/admin-audit.log"'
ck "trilha: eventos logout com quem mandou" 'grep -q "	alice	logout	" "$C/var/session-events.log" && grep -q "	uc.admin$" "$C/var/session-events.log"'
call /auth/login POST '{"username":"alice","password":"secreta"}' none 'contest=uc' 'Moz MOJBOX'
ck "login fechado: competidor → 403 login_disabled" '[[ "$OUT" == *"Status: 403"* && "$(jq -r .error.code <<<"$BODY")" == login_disabled ]]'
call /auth/login POST '{"username":"uc.admin","password":"p"}' none 'contest=uc' 'Moz MOJBOX'
ck "login fechado: papel entra"  '[[ "$(jq -r .logged_in <<<"$BODY")" == true ]]'
call /contest/admin/logout-all POST '{"scope":"staff"}' adm 'contest=uc'
ck "scope staff: .staff e .cstaff fora; monitor/telão/juiz ficam" '[[ "$(jq -r .staff <<<"$BODY")" == 2 && ! -f "$SESS/st1" && ! -f "$SESS/cs1" && -f "$SESS/tv1" && -f "$SESS/mo1" && -f "$SESS/jx1" ]]'
call /contest/admin/logout-all POST '{"open_login":true}' adm 'contest=uc'
ck "reabrir login apaga LOGIN_ENABLED"  '[[ "$(jq -r .login_enabled <<<"$BODY")" == true ]] && ! grep -q "^LOGIN_ENABLED=" "$C/conf"'
call /auth/login POST '{"username":"alice","password":"secreta"}' none 'contest=uc' 'Moz MOJBOX'
ck "login reaberto: competidor entra"   '[[ "$(jq -r .logged_in <<<"$BODY")" == true ]]'
call /contest/admin/logout-all POST '{"scope":"tudo"}' adm 'contest=uc'
ck "scope inválido → 422"               '[[ "$OUT" == *"Status: 422"* ]]'
call /contest/admin/logout-all POST '{"scope":"all"}' cj1 'contest=uc'
ck "chefe (não-admin) → 403"            '[[ "$OUT" == *"Status: 403"* ]]'
mkses dave dave "Moz MOJBOX dave"   # os testes seguintes usam a sessão do dave (derrubada acima)

echo "== carga em lote (users-bulk, legado) =="
call /contest/admin/users-bulk POST '{"users":[{"login":"nova1","fullname":"Nova Um"},{"login":"nova2","password":"pw2","fullname":"Nova Dois","email":"n2@x.com"},{"login":"alice","fullname":"Alice X"},{"login":"jx.judge","fullname":"Hack"},{"login":"inv@lido!","fullname":"X"},{"login":"nova1","fullname":"dup"}]}' adm 'contest=uc'
ck "criou 2 (nova1,nova2)"     '[[ "$(jq -r .counts.created <<<"$BODY")" == 2 ]]'
ck "nova1 com senha gerada"    '[[ -n "$(jq -r ".created[]|select(.login==\"nova1\").password" <<<"$BODY")" ]]'
ck "nova2 mantém senha dada"   '[[ "$(jq -r ".created[]|select(.login==\"nova2\").password" <<<"$BODY")" == "pw2" ]]'
ck "passwd tem nova1 e nova2"  '[[ -f "$C/users/nova1/account.json" && "$(jq -r .password "$C/users/nova2/account.json")" == "pw2" && "$(jq -r .email "$C/users/nova2/account.json")" == "n2@x.com" ]]'
ck "skip: alice existe"        '[[ "$(jq -r ".skipped[]|select(.login==\"alice\").reason" <<<"$BODY")" == exists ]]'
ck "skip: login inválido"      '[[ "$(jq -r ".skipped[]|select(.login==\"inv@lido!\").reason" <<<"$BODY")" == invalid ]]'
ck "skip: duplicado no lote"   '[[ "$(jq -r "[.skipped[]|select(.reason==\"duplicate\")]|length" <<<"$BODY")" == 1 ]]'
call /contest/admin/users-bulk POST '{"on_existing":"update","users":[{"login":"alice","password":"alnova","fullname":"Alice Nova"},{"login":"jx.judge","password":"hack"}]}' adm 'contest=uc'
ck "update troca a alice"      '[[ "$(jq -r .counts.updated <<<"$BODY")" == 1 ]] && [[ "$(jq -r .password "$C/users/alice/account.json")" == "alnova" && "$(jq -r .fullname "$C/users/alice/account.json")" == "Alice Nova" ]]'
ck "update NÃO toca privilegiado" '[[ "$(jq -r ".skipped[]|select(.login==\"jx.judge\").reason" <<<"$BODY")" == privileged ]] && [[ "$(jq -r .password "$C/users/jx.judge/account.json")" == "p" ]]'
call /contest/admin/users GET '' adm 'contest=uc'
ck "lista reflete nova1"       '[[ "$(jq -r ".users[]|select(.login==\"nova1\")|.login" <<<"$BODY")" == nova1 ]]'
call /contest/admin/users-bulk POST '{"users":[{"login":"x1"}]}' dave 'contest=uc'
ck "não-admin no bulk 403"     '[[ "$OUT" == *"Status: 403"* ]]'

echo "== proteção =="
call /contest/admin/logout-user POST '{"login":"bob"}' dave 'contest=uc'
ck "não-admin 403"           '[[ "$OUT" == *"Status: 403"* ]]'

echo "== contest GRANDE: a lista de contas passa de 128KiB (regressão do 500 build_fail) =="
# A lista tem um objeto por CONTA e cresce com o evento: no mdp-teste-2026 (2354 contas) ela
# passou de 250 KB e o `--argjson u` estourou o teto de 128 KiB POR ARGUMENTO do exec — o jq
# morria com "Argument list too long" e o handler devolvia 500 build_fail (`moj contest users
# ls` quebrado). Aqui sintetizamos 2400 contas e exigimos 200 com a lista INTEIRA.
for i in $(seq 1 2400); do
  d="$C/users/time-participante-numero-$(printf '%04d' "$i")"; mkdir -p "$d"
  printf '{"login":"time-participante-numero-%04d","password":"p","fullname":"Equipe Participante Número %04d da Universidade Federal de Exemplo","email":"time%04d@universidade.exemplo.br","status":"active"}\n' "$i" "$i" "$i" > "$d/account.json"
done
BIGU="$(find "$C/users" -mindepth 2 -maxdepth 2 -name account.json -print0 \
        | xargs -0 -r jq -c '{login,fullname,email}' | jq -cs . | wc -c)"
ck "fixture passou de 128KiB" '(( BIGU > 131072 ))'
call /contest/admin/users GET '' adm 'contest=uc'
ck "resposta 200"             '[[ "$OUT" == *"Status: 200"* ]]'
ck "corpo é JSON de sucesso"  'jq -e ".success == true" >/dev/null 2>&1 <<<"$BODY"'
ck "count bate com a lista"   '[[ "$(jq -r ".count" <<<"$BODY")" == "$(jq -r ".users|length" <<<"$BODY")" ]]'
ck "traz as 2400 sintéticas"  '[[ "$(jq -r "[.users[]|select(.login|startswith(\"time-participante-\"))]|length" <<<"$BODY")" == 2400 ]]'
ck "a última conta veio"      '[[ "$(jq -r ".users[]|select(.login==\"time-participante-numero-2400\")|.fullname" <<<"$BODY")" == *"2400 da Universidade"* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
