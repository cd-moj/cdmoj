#!/bin/bash
# Itens 3/7/9: deslogar usuário, desabilitar, troca de senha geral, deslogar UA divergente.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
C="$FIX/uc"; mkdir -p "$C/var"
printf 'CONTEST_ID=uc\nCONTEST_TYPE=icpc\nLOGIN_UA_SUBSTRING=MOJBOX\n' > "$C/conf"
printf 'uc.admin:p:Admin\nalice:a:Alice\nbob:b:Bob\ncarol:c:Carol\njx.judge:p:Judge\ncj.cjudge:p:Chief\n' > "$C/passwd"
b64(){ printf '%s' "$1" | base64 -w0; }
mkses(){ printf 'CONTEST=uc\nLOGIN=%q\nUSERFULLNAME=x\nLOGINAT=1\nIP=1.1.1.1\nUA_B64=%q\n' "$2" "$(b64 "$3")" > "$SESS/$1"; }
printf 'CONTEST=uc\nLOGIN=uc.admin\nLOGINAT=1\n' > "$SESS/adm"
mkses dave dave "Moz MOJBOX dave"
mkses a1 alice "Moz MOJBOX 1"; mkses a2 alice "Moz MOJBOX 2"; mkses b1 bob "other"; mkses c1 carol "badUA"
mkses cj1 cj.cjudge "badUA"   # privilegiado com UA ruim: logout-mismatch NÃO pode derrubar
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-adm}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:160}"; ((fail++)); fi; }

echo "== deslogar usuário =="
call /contest/admin/logout-user POST '{"login":"alice"}' adm 'contest=uc'
ck "removeu 2 sessões da alice" '[[ "$(jq -r .sessions_removed <<<"$BODY")" == 2 ]]'

echo "== desabilitar =="
call /contest/admin/user-disable POST '{"login":"bob"}' adm 'contest=uc'
ck "bob desabilitado"        '[[ "$(jq -r .disabled <<<"$BODY")" == "true" ]]'
ck "passwd bob começa com !" 'grep -q "^bob:!" "$C/passwd"'
call /contest/admin/user-disable POST '{"login":"jx.judge"}' adm 'contest=uc'
ck "não desabilita privilegiado 403" '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/admin/user-disable POST '{"login":"cj.cjudge"}' adm 'contest=uc'
ck "não desabilita .cjudge 403" '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/admin/users GET '' adm 'contest=uc'
ck "users: bob disabled=true"  '[[ "$(jq -r ".users[]|select(.login==\"bob\")|.disabled" <<<"$BODY")" == "true" ]]'

echo "== troca de senha geral =="
call /contest/admin/users-set-password POST '{"password":"prova2026"}' adm 'contest=uc'
ck "trocou 2 (alice,carol; pula priv/disabled)" '[[ "$(jq -r .count <<<"$BODY")" == 2 ]]'
ck "alice:prova2026"         'grep -q "^alice:prova2026:" "$C/passwd"'
ck "bob continua desabilitado" 'grep -q "^bob:!" "$C/passwd"'
ck "admin intacto"           'grep -q "^uc.admin:p:" "$C/passwd"'
ck ".cjudge intacto"         'grep -q "^cj.cjudge:p:" "$C/passwd"'
call /contest/admin/users-set-password POST '{"password":"secreta","include_disabled":true}' adm 'contest=uc'
ck "com include_disabled troca 3" '[[ "$(jq -r .count <<<"$BODY")" == 3 ]]'
ck "bob reabilitado (secreta)" 'grep -q "^bob:secreta:" "$C/passwd"'

echo "== deslogar UA divergente =="
mkses a3 alice "Moz MOJBOX ok"   # alice com UA bom
call /contest/admin/logout-mismatch POST '{}' adm 'contest=uc'
ck "removeu só os de UA ruim (carol)" '[[ "$(jq -r .sessions_removed <<<"$BODY")" -ge 1 ]]'
ck "sessão da alice (UA bom) ficou" '[[ -f "$SESS/a3" ]]'
ck "sessão da carol (UA ruim) saiu" '[[ ! -f "$SESS/c1" ]]'
ck "sessão do .cjudge (privilegiado) ficou" '[[ -f "$SESS/cj1" ]]'

echo "== carga em lote (users-bulk, legado) =="
call /contest/admin/users-bulk POST '{"users":[{"login":"nova1","fullname":"Nova Um"},{"login":"nova2","password":"pw2","fullname":"Nova Dois","email":"n2@x.com"},{"login":"alice","fullname":"Alice X"},{"login":"jx.judge","fullname":"Hack"},{"login":"inv@lido!","fullname":"X"},{"login":"nova1","fullname":"dup"}]}' adm 'contest=uc'
ck "criou 2 (nova1,nova2)"     '[[ "$(jq -r .counts.created <<<"$BODY")" == 2 ]]'
ck "nova1 com senha gerada"    '[[ -n "$(jq -r ".created[]|select(.login==\"nova1\").password" <<<"$BODY")" ]]'
ck "nova2 mantém senha dada"   '[[ "$(jq -r ".created[]|select(.login==\"nova2\").password" <<<"$BODY")" == "pw2" ]]'
ck "passwd tem nova1 e nova2"  'grep -q "^nova1:" "$C/passwd" && grep -q "^nova2:pw2:Nova Dois:n2@x.com" "$C/passwd"'
ck "skip: alice existe"        '[[ "$(jq -r ".skipped[]|select(.login==\"alice\").reason" <<<"$BODY")" == exists ]]'
ck "skip: login inválido"      '[[ "$(jq -r ".skipped[]|select(.login==\"inv@lido!\").reason" <<<"$BODY")" == invalid ]]'
ck "skip: duplicado no lote"   '[[ "$(jq -r "[.skipped[]|select(.reason==\"duplicate\")]|length" <<<"$BODY")" == 1 ]]'
call /contest/admin/users-bulk POST '{"on_existing":"update","users":[{"login":"alice","password":"alnova","fullname":"Alice Nova"},{"login":"jx.judge","password":"hack"}]}' adm 'contest=uc'
ck "update troca a alice"      '[[ "$(jq -r .counts.updated <<<"$BODY")" == 1 ]] && grep -q "^alice:alnova:Alice Nova" "$C/passwd"'
ck "update NÃO toca privilegiado" '[[ "$(jq -r ".skipped[]|select(.login==\"jx.judge\").reason" <<<"$BODY")" == privileged ]] && grep -q "^jx.judge:p:" "$C/passwd"'
call /contest/admin/users GET '' adm 'contest=uc'
ck "lista reflete nova1"       '[[ "$(jq -r ".users[]|select(.login==\"nova1\")|.login" <<<"$BODY")" == nova1 ]]'
call /contest/admin/users-bulk POST '{"users":[{"login":"x1"}]}' dave 'contest=uc'
ck "não-admin no bulk 403"     '[[ "$OUT" == *"Status: 403"* ]]'

echo "== proteção =="
call /contest/admin/logout-user POST '{"login":"bob"}' dave 'contest=uc'
ck "não-admin 403"           '[[ "$OUT" == *"Status: 403"* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
