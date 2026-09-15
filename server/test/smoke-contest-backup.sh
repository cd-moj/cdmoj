#!/bin/bash
# BACKUP do competidor: GRAVAR só durante a prova (decisão do Ribas, 2026-09-15) — antes do início
# 403 contest_not_started, depois do fim 403 contest_ended (fim EFETIVO da sessão: sede prorrogada
# segue gravando), staff nunca (403 role_forbidden), admin/juiz sempre; listar/baixar/apagar seguem
# livres (o time leva o trabalho dele de volta); BACKUP=0 no conf desliga tudo p/ o time.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
C="$FIX/bk"; mkdir -p "$C/var"
NOW="$EPOCHSECONDS"
conf(){ printf 'CONTEST_ID=bk\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\n%s\n' "$1" "$2" "${3:-}" > "$C/conf"; }
conf "$((NOW-3600))" "$((NOW+3600))"
fx_user "$C" bk.admin p Admin; fx_user "$C" j.judge p Judge; fx_user "$C" s.staff p Staff; fx_user "$C" time01 p Time
for s in "adm bk.admin" "jdg j.judge" "stf s.staff" "t1 time01"; do set -- $s; printf 'CONTEST=bk\nLOGIN=%s\nLOGINAT=1\n' "$2" > "$SESS/$1"; done
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="contest=bk${5:+&$5}" HTTP_AUTHORIZATION="Bearer ${4:-t1}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }
J(){ jq -r "$1" <<<"$BODY" 2>/dev/null; }
SAVE='{"filename":"sol.cpp","file_b64":"aW50IG1haW4oKXt9"}'

echo "== durante a prova: grava, lista, baixa, apaga =="
call /contest/backup POST "$SAVE" t1;  ck "time grava -> 200"            '[[ "$(J .saved)" == true ]]'; ID="$(J .id)"
call /contest/backup GET '' t1;         ck "lista o próprio"              '[[ "$(J ".backups|length")" == 1 ]]'
call /contest/backup-file GET '' t1 "id=$ID"; ck "baixa o próprio"       '[[ "$OUT" == *"Status: 200"* ]]'

echo "== ANTES do início: time e .mon não gravam; juiz/admin gravam; staff nunca =="
conf "$((NOW+3600))" "$((NOW+7200))"
call /contest/backup POST "$SAVE" t1
ck "time antes do início -> 403 contest_not_started" '[[ "$OUT" == *"Status: 403"* && "$(J .error.code)" == contest_not_started ]]'
call /contest/backup GET '' t1;         ck "…mas LISTA (leitura livre)"   '[[ "$(J ".backups|length")" == 1 ]]'
call /contest/backup-file GET '' t1 "id=$ID"; ck "…e BAIXA"              '[[ "$OUT" == *"Status: 200"* ]]'
call /contest/backup POST "$SAVE" jdg;  ck "juiz grava antes do início"   '[[ "$(J .saved)" == true ]]'
call /contest/backup POST "$SAVE" adm;  ck "admin grava"                  '[[ "$(J .saved)" == true ]]'
call /contest/backup POST "$SAVE" stf
ck "staff nunca -> 403 role_forbidden"  '[[ "$OUT" == *"Status: 403"* && "$(J .error.code)" == role_forbidden ]]'

echo "== DEPOIS do fim: não grava; sede prorrogada ainda grava; apagar segue livre =="
conf "$((NOW-7200))" "$((NOW-3600))"
call /contest/backup POST "$SAVE" t1
ck "time depois do fim -> 403 contest_ended" '[[ "$OUT" == *"Status: 403"* && "$(J .error.code)" == contest_ended ]]'
printf '[{"regex":"^time01$","end":%s,"reason":"prorrogada"}]' "$((NOW+1800))" > "$C/time-overrides.json"
call /contest/backup POST "$SAVE" t1;   ck "sede prorrogada grava"        '[[ "$(J .saved)" == true ]]'; ID2="$(J .id)"
rm -f "$C/time-overrides.json"
call /contest/backup POST "{\"action\":\"delete\",\"id\":\"$ID2\"}" t1
ck "apagar depois do fim segue livre"   '[[ "$(J .deleted)" == true ]]'
call /contest/backup GET '' t1;         ck "lista depois do fim"          '[[ "$(J ".backups|length")" == 1 ]]'

echo "== BACKUP=0: tudo desabilitado p/ o time =="
conf "$((NOW-3600))" "$((NOW+3600))" 'BACKUP=0'
call /contest/backup POST "$SAVE" t1;   ck "BACKUP=0 -> 403 backup_disabled" '[[ "$OUT" == *"Status: 403"* && "$(J .error.code)" == backup_disabled ]]'
call /contest/backup GET '' t1;         ck "listar também 403"            '[[ "$OUT" == *"Status: 403"* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
