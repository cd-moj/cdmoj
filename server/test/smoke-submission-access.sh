#!/bin/bash
# FONTE, REPORT e RESUMO de uma submissão = DONO ou JUIZ/ADMIN. Sempre.
# Existia a opção SHOWCODE ("mostrar o código das submissões a todos"): com ela qualquer login do
# contest baixava o fonte, o report e o resumo das submissões DOS OUTROS pela API. Ninguém sabia dizer
# em que caso isso era desejável — e quem a ligava (relato do Daniel Saad, 2026-09-18) achava que ela
# deixava o aluno ver o PRÓPRIO código, o que sempre valeu. Foi removida. Este teste parte do caso
# LEGADO — conf com SHOWCODE=1 — e exige que a linha morta não abra nada.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$HERE/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN"
NOW="$EPOCHSECONDS"; C="$FIX/sa"; mkdir -p "$C/var"
mkdir -p "$FIX/treino/var"; printf 'CONTEST_ID=treino\n' > "$FIX/treino/conf"
{ printf 'CONTEST_ID=sa\nCONTEST_NAME=Acesso\nCONTEST_TYPE=obi\nCONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW-3600))" "$((NOW+3600))"
  printf 'SHOWCODE=1\nSHOWLOG=1\nPROBS=( x col/pa Alfa A col#pa )\n'; } > "$C/conf"
for u in dona outro sa.judge sa.admin; do fx_user "$C" "$u" s "$u"
  printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' sa "$u" "$u" "$NOW" > "$SESS/tok-$u"; done
SID=0123456789abcdef0123456789abcdef
printf '%s:col#pa:C:Accepted,100p:%s:%s\n' "$NOW" "$NOW" "$SID" > "$C/users/dona/history"
printf 'int main(){/*SEGREDO_DA_DONA*/}\n' > "$C/users/dona/submissions/$SID.c"
printf '<h1>REPORT_DA_DONA</h1>' | gzip -c > "$C/users/dona/mojlog/$SID.html.gz"
printf '{"verdict":"Accepted,100p","verdict_canon":"Accepted","score":100,"score_max":100,"correct":5,"total_tests":5}' > "$C/users/dona/results/$SID.json"

call(){ OUT="$(PATH_INFO="$2" REQUEST_METHOD="${4:-GET}" QUERY_STRING="contest=sa&$3" HTTP_AUTHORIZATION="Bearer tok-$1" bash "$ROUTER" <<<"${5:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${OUT:0:220}"; ((fail++)); fi; }

echo "== conf LEGADO com SHOWCODE=1: o código dos outros NÃO abre =="
call outro /submission/source "id=$SID";  ck "outro time: fonte 403 source_forbidden" '[[ "$OUT" == *"Status: 403"* && "$OUT" == *source_forbidden* && "$OUT" != *SEGREDO_DA_DONA* ]]'
call outro /submission/log "id=$SID";     ck "outro time: report 403 log_forbidden"   '[[ "$OUT" == *"Status: 403"* && "$OUT" == *log_forbidden* && "$OUT" != *REPORT_DA_DONA* ]]'
call outro /submission/summary "ids=$SID"; ck "outro time: resumo OMITE o id alheio"   '[[ "$OUT" == *"Status: 200"* && "$(jq -r "has(\"$SID\")" <<<"$BODY")" == false ]]'
echo "== dono e juiz/admin seguem vendo =="
call dona /submission/source "id=$SID";    ck "dona: o próprio fonte"  '[[ "$OUT" == *SEGREDO_DA_DONA* ]]'
call dona /submission/log "id=$SID";       ck "dona: o próprio report" '[[ "$OUT" == *"Status: 200"* ]]'
call dona /submission/summary "ids=$SID";  ck "dona: o próprio resumo" '[[ "$(jq -r ".[\"$SID\"].score" <<<"$BODY")" == 100 ]]'
call sa.judge /submission/source "id=$SID"; ck "juiz: fonte de qualquer um"  '[[ "$OUT" == *SEGREDO_DA_DONA* ]]'
call sa.admin /submission/summary "ids=$SID"; ck "admin: resumo de qualquer um" '[[ "$(jq -r "has(\"$SID\")" <<<"$BODY")" == true ]]'
echo "== a opção sumiu da API =="
call sa.admin /contest/admin/settings "";  ck "settings GET sem show_code"  '[[ "$OUT" == *"Status: 200"* && "$(jq -r "has(\"show_code\")" <<<"$BODY")" == false ]]'
call sa.admin /contest/admin/settings "" POST '{"show_code":true,"show_log":true}'
ck "POST com show_code: 200 (chave ignorada — cliente antigo manda o formulário inteiro)" '[[ "$OUT" == *"Status: 200"* ]]'
ck "…não gravou, e a linha morta SAIU do conf"  '! grep -q "^SHOWCODE=" "$C/conf"'
call outro /submission/source "id=$SID";   ck "…e continua fechado depois do POST" '[[ "$OUT" == *"Status: 403"* ]]'
call dona /contest/userinfo "";            ck "userinfo sem show_code" '[[ "$OUT" == *"Status: 200"* && "$(jq -r "has(\"show_code\")" <<<"$BODY")" == false ]]'
call sa.admin /contest/admin/preflight ""; ck "preflight sem a checagem show_code" '[[ "$OUT" == *"Status: 200"* && "$(jq -r "[.checks[]?.id]|index(\"show_code\")" <<<"$BODY")" == null ]]'
echo; echo "RESULT: $pass passed, $fail failed"; (( fail == 0 ))
