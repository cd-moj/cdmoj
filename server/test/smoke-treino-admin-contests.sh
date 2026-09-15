#!/bin/bash
# smoke-treino-admin-contests.sh — painel do treino › Contests (2026-09-15, pedido do Ribas):
#  • SUPERADMINS (conf do treino) vê/remove/duplica tudo; `.admin` comum vê os seus e os de criadores
#    SEM papel de admin — nunca o contest de outro `.admin` (lista, remove=404, duplicate=404, export=404);
#  • contest-perms com trilha (allow_meta/deny_meta: by/at/note), ações add/remove/threshold,
#    unknown_login 404, already_admin 422, POST legado ainda grava (e carimba meta);
#  • id `icpc*` só super-admin (403 id_prefix_reserved no create e no duplicate);
#  • permission expõe is_superadmin + reserved_id_prefixes.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
T="$FIX/treino"; mkdir -p "$T/var/jsons"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\nSUPERADMINS=super.admin\\ outro.admin\n' > "$T/conf"
fx_user "$T" super.admin p "Super Admin"
fx_user "$T" a.admin p "Prof A"
fx_user "$T" b.admin p "Prof B"
fx_user "$T" maker s "Maker Person"
fx_user "$T" nobody s "No Body"
for u in super.admin:sup a.admin:adma b.admin:admb maker:mak nobody:nob; do
  printf 'CONTEST=treino\nLOGIN=%s\nUSERFULLNAME=X\nLOGINAT=1\n' "${u%%:*}" > "$SESS/${u##*:}"
done
printf '%s' '{"problems":[]}' > "$T/var/problem-owners.json"
NOW="$(date +%s)"; FUT=$(( NOW + 100000 ))
mkc(){ # <id> <owner> <name> [start] [end]
  local d="$FIX/$1"; mkdir -p "$d/users" "$d/var"
  printf 'CONTEST_ID=%s\nCONTEST_NAME=%q\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nPROBS=( x a#b B A a#b )\nUSER_STORE=v2\n' "$1" "$3" "${4:-$NOW}" "${5:-$FUT}" > "$d/conf"
  printf '%s\n' "$2" > "$d/owner"; printf '%s\t%s\ticpc\n' "$2" "$NOW" > "$d/created-by"
}
mkc c-a a.admin "Prova do A"; mkc c-b b.admin "Prova do B"; mkc c-m maker "Lista do Maker"; mkc c-s super.admin "Prova da Org"
call(){ # <path> <method> <body> <token> <query>
  OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-sup}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" MOJ_JOBS_SYNC=1 bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; CODE="$(printf '%s' "$OUT" | sed -n 's/^Status: \([0-9]*\).*/\1/p' | head -1)"; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: code=$CODE ${BODY:0:220}"; ((fail++)); fi; }
ids(){ jq -r '[.contests[].id] | sort | join(" ")' <<<"$BODY"; }

echo "== visibilidade da lista =="
call /treino/admin/contests GET '' sup
ck "super vê os 4, scope all"            '[[ "$(ids)" == "c-a c-b c-m c-s" && "$(jq -r .scope <<<"$BODY")" == all && "$(jq -r .is_superadmin <<<"$BODY")" == true ]]'
ck "objeto rico: owner_name, start/end, problems_count, owner_is_admin" '[[ "$(jq -c ".contests[]|select(.id==\"c-m\")|[.owner,.owner_name,.owner_is_admin,.problems_count,(.start>0),(.end>0)]" <<<"$BODY")" == "[\"maker\",\"Maker Person\",false,1,true,true]" ]]'
call /treino/admin/contests GET '' adma
ck "a.admin vê o seu e o do maker, não o do b.admin nem o do super" '[[ "$(ids)" == "c-a c-m" && "$(jq -r .scope <<<"$BODY")" == admin && "$(jq -r .is_superadmin <<<"$BODY")" == false ]]'
call /treino/admin/contests GET '' admb
ck "b.admin idem (c-b c-m)"              '[[ "$(ids)" == "c-b c-m" ]]'
call /treino/admin/contests GET '' mak
ck "maker não é admin: 403"              '[[ "$CODE" == 403 ]]'
call /treino/contest-create/mine GET '' sup
ck "mine do super = só o dele"           '[[ "$(ids)" == "c-s" ]]'

echo "== remover / duplicar / exportar seguem o mesmo escopo =="
call /treino/admin/contest-remove POST '{"contest":"c-b"}' adma
ck "a.admin não remove o do b.admin (404)" '[[ "$CODE" == 404 && -d "$FIX/c-b" ]]'
call /treino/contest-create/duplicate POST '{"from":"c-b","id":"c-b2"}' adma
ck "a.admin não duplica o do b.admin (404)" '[[ "$CODE" == 404 ]]'
call /treino/contest-create/export GET '' adma "id=c-b"
ck "a.admin não exporta o do b.admin (404)" '[[ "$CODE" == 404 ]]'
call /treino/contest-create/export GET '' adma "id=c-m"
ck "a.admin exporta o do maker (200)"    '[[ "$CODE" == 200 ]]'
call /treino/admin/contest-remove POST '{"contest":"c-b"}' sup
ck "super remove o do b.admin (200)"     '[[ "$CODE" == 200 && ! -d "$FIX/c-b" ]]'

echo "== prefixo icpc: só super-admin =="
SPEC='{"id":"icpc-x","name":"X","mode":"icpc","end":'$FUT',"problems":[{"problem_id":"a/b","name":"AB"}]}'
call /treino/contest-create/create POST "$SPEC" adma
ck "a.admin: 403 id_prefix_reserved"     '[[ "$CODE" == 403 ]] && grep -q id_prefix_reserved <<<"$BODY"'
call /treino/admin/contest-perms POST '{"action":"add","list":"allow","login":"maker"}' sup
call /treino/contest-create/create POST "$SPEC" mak
ck "maker (liberado): 403"               '[[ "$CODE" == 403 ]] && grep -q id_prefix_reserved <<<"$BODY"'
call /treino/contest-create/duplicate POST '{"from":"c-a","id":"icpc-dup"}' adma
ck "duplicate com id icpc*: 403"         '[[ "$CODE" == 403 ]] && grep -q id_prefix_reserved <<<"$BODY"'
call /treino/contest-create/create POST "$SPEC" sup
ck "super cria icpc-x"                   '[[ "$CODE" == 200 && -d "$FIX/icpc-x" ]]'
call /treino/contest-create/create POST "${SPEC/icpc-x/prova-a}" adma
ck "a.admin cria id comum"               '[[ "$CODE" == 200 && -d "$FIX/prova-a" ]]'
call /treino/contest-create/permission GET '' sup
ck "permission: is_superadmin + reserved_id_prefixes" '[[ "$(jq -c "[.is_superadmin, .reserved_id_prefixes]" <<<"$BODY")" == "[true,[\"icpc\"]]" ]]'
call /treino/contest-create/permission GET '' adma
ck "a.admin: is_admin true, is_superadmin false" '[[ "$(jq -c "[.is_admin, .is_superadmin]" <<<"$BODY")" == "[true,false]" ]]'

echo "== contest-perms: trilha e ações =="
call /treino/admin/contest-perms GET '' adma
ck "maker na allow com by=super.admin, nome resolvido" '[[ "$(jq -c ".allow_info[]|select(.login==\"maker\")|[.name,.by,.by_name,(.at>0)]" <<<"$BODY")" == "[\"Maker Person\",\"super.admin\",\"Super Admin\",true]" ]]'
call /treino/admin/contest-perms POST '{"action":"add","list":"deny","login":"nobody","note":"spam"}' adma
ck "add deny com nota"                   '[[ "$CODE" == 200 && "$(jq -c ".deny_info[0]|[.login,.by,.note]" <<<"$BODY")" == "[\"nobody\",\"a.admin\",\"spam\"]" ]]'
call /treino/admin/contest-perms POST '{"action":"add","list":"allow","login":"nobody"}' adma
ck "add allow tira da deny"              '[[ "$(jq -c "[(.perms.allow|sort), .perms.deny]" <<<"$BODY")" == "[[\"maker\",\"nobody\"],[]]" ]]'
call /treino/admin/contest-perms POST '{"action":"add","list":"allow","login":"ghost"}' adma
ck "login inexistente: 404 unknown_login" '[[ "$CODE" == 404 ]] && grep -q unknown_login <<<"$BODY"'
call /treino/admin/contest-perms POST '{"action":"add","list":"allow","login":"b.admin"}' adma
ck ".admin na allow: 422 already_admin"  '[[ "$CODE" == 422 ]] && grep -q already_admin <<<"$BODY"'
call /treino/admin/contest-perms POST '{"action":"remove","list":"allow","login":"nobody"}' adma
ck "remove tira login e meta"            '[[ "$(jq -c "[.perms.allow, (.perms.allow_meta|keys)]" <<<"$BODY")" == "[[\"maker\"],[\"maker\"]]" ]]'
call /treino/admin/contest-perms POST '{"action":"threshold","threshold":5}' adma
ck "threshold"                           '[[ "$(jq -r .perms.threshold <<<"$BODY")" == 5 ]]'
call /treino/admin/contest-perms POST '{"action":"zap"}' adma
ck "ação inválida 400"                   '[[ "$CODE" == 400 ]]'
call /treino/admin/contest-perms POST '{"threshold":2,"allow":["maker","nobody"],"deny":[]}' admb
ck "POST legado: grava, preserva meta do maker e carimba nobody com b.admin" '[[ "$(jq -c "[.perms.threshold, (.allow_info[]|select(.login==\"maker\")|.by), (.allow_info[]|select(.login==\"nobody\")|.by)]" <<<"$BODY")" == "[2,\"super.admin\",\"b.admin\"]" ]]'
call /treino/admin/contest-perms GET '' mak
ck "não-admin: 403"                      '[[ "$CODE" == 403 ]]'
ck "cc_can_create ainda lê a lista simples (maker pode)" 'call /treino/contest-create/permission GET "" mak; [[ "$(jq -r .can_create <<<"$BODY")" == true ]]'

echo; echo "RESULT: $pass passed, $fail failed"; [[ $fail -eq 0 ]]
