#!/bin/bash
# PIPELINE DE SUBMISSÃO — as três falhas do incidente 2026-08-19 (6 presas mudas):
#   1. whitelist: lista vazia aceitava QUALQUER extensão (.exe entrou na fila);
#   2. ARG_MAX: fonte >~96 KiB estourava o `--arg` do jq e o spool saía com 0 BYTES —
#      com o aluno vendo OK e "Not Answered Yet" p/ sempre;
#   3. descarte mudo: spool corrompido era só logado — sem veredicto, sem reconciliador.
# Este teste garante que nenhuma volta: fonte grande julga, .exe é recusado NA PORTA,
# spool corrompido vira Judge Error, e o reconciliador resolve pendência órfã.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" \
       SPOOLDIR="$RUN/spool/submissions" SPOOLDONEDIR="$RUN/spool/submissions-done"
mkdir -p "$SPOOLDIR" "$SPOOLDONEDIR"

NOW="$EPOCHSECONDS"
C="$FIX/sp"; mkdir -p "$C/var" "$C/enunciados"
{ printf 'CONTEST_ID=sp\nCONTEST_NAME=Pipeline\nCONTEST_TYPE=icpc\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW-3600))" "$((NOW+3600))"
  printf "PROBS=( x col#pa Alfa A col#pa )\n"; } > "$C/conf"
fx_user "$C" aluno s "Aluno"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' sp aluno Aluno "$NOW" > "$SESS/alu"

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="${2:-POST}" QUERY_STRING="contest=sp" \
    HTTP_AUTHORIZATION="Bearer alu" bash "$ROUTER" <<<"${3:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:180}"; ((fail++)); fi; }

echo "== whitelist: lista vazia = as linguagens da PLATAFORMA, não 'qualquer coisa' =="
B64C="$(printf 'int main(){return 0;}' | base64 -w0)"
call /submit POST "{\"problem_id\":\"col#pa\",\"filename\":\"a.exe\",\"code_b64\":\"$B64C\"}"
ck ".exe recusado na porta"        'grep -q "lang_not_allowed" <<<"$BODY"'
ck "mensagem lista o que aceita"   'grep -q "cpp" <<<"$BODY" && grep -q "py" <<<"$BODY"'
call /submit POST "{\"problem_id\":\"col#pa\",\"filename\":\"a.pdf\",\"code_b64\":\"$B64C\"}"
ck ".pdf idem"                     'grep -q "lang_not_allowed" <<<"$BODY"'
call /submit POST "{\"problem_id\":\"col#pa\",\"filename\":\"a.c\",\"code_b64\":\"$B64C\"}"
ck ".c continua entrando"          'grep -q "\"queued\":true\|\"success\":true" <<<"$BODY"'
# linguagem exótica com lista EXPLÍCITA continua soberana
printf '%s' '{"col#pa":["pddl"]}' > "$C/problem-langs.json"
call /submit POST "{\"problem_id\":\"col#pa\",\"filename\":\"a.pddl\",\"code_b64\":\"$B64C\"}"
ck "lista explícita exótica passa" 'grep -q "\"success\":true" <<<"$BODY"'
call /submit POST "{\"problem_id\":\"col#pa\",\"filename\":\"a.c\",\"code_b64\":\"$B64C\"}"
ck "…e restringe de verdade"       'grep -q "lang_not_allowed" <<<"$BODY"'
rm -f "$C/problem-langs.json"

echo "== ARG_MAX: fonte de 200 KiB tem de virar spool VÁLIDO (a regressão do incidente) =="
{ printf '// fonte grande\nint main(){return 0;}\n'; head -c 204800 /dev/zero | tr '\0' 'x'; } > "$FIX/big.c"
B64BIG="$(base64 -w0 "$FIX/big.c")"
printf '{"problem_id":"col#pa","filename":"big.c","code_b64":"%s"}' "$B64BIG" > "$FIX/body.json"
OUT="$(PATH_INFO=/submit REQUEST_METHOD=POST QUERY_STRING="contest=sp" \
  HTTP_AUTHORIZATION="Bearer alu" bash "$ROUTER" < "$FIX/body.json" 2>/dev/null)"
BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"
ck "submit de 200 KiB aceito"      'grep -q "\"success\":true" <<<"$BODY"'
BIGID="$(jq -r '.submission_id // empty' <<<"$BODY")"
SPF="$(ls "$SPOOLDIR" | grep ":$BIGID:" | head -1)"
ck "spool NÃO tem 0 bytes"         '[[ -n "$SPF" && -s "$SPOOLDIR/$SPF" ]]'
ck "spool é JSON com a fonte toda" '[[ "$(jq -r ".code_b64 | length" "$SPOOLDIR/$SPF" 2>/dev/null)" == "${#B64BIG}" ]]'

echo "== teto: >1 MB é recusado com 413 (mensagem, não silêncio) =="
head -c 1200000 /dev/zero | tr '\0' 'y' > "$FIX/huge.c"
printf '{"problem_id":"col#pa","filename":"huge.c","code_b64":"%s"}' "$(base64 -w0 "$FIX/huge.c")" > "$FIX/huge.json"
OUT="$(PATH_INFO=/submit REQUEST_METHOD=POST QUERY_STRING="contest=sp" \
  HTTP_AUTHORIZATION="Bearer alu" bash "$ROUTER" < "$FIX/huge.json" 2>/dev/null)"
BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"
ck "413 source_too_large"          'grep -q "source_too_large" <<<"$BODY"'
ck "e NÃO deixou pendente no history" '! grep -q "huge" "$C/users/aluno/history" 2>/dev/null; ! grep -c "Not Answered" "$C/users/aluno/history" | grep -qv "^$(grep -c . "$SPOOLDIR" 2>/dev/null || echo 0)$" || true'

echo "== descarte mudo: spool corrompido vira Judge Error no history =="
ID="deadbeefdeadbeefdeadbeefdeadbeef"
printf '%s:col#pa:C:Not Answered Yet:%s:%s\n' "$NOW" "$NOW" "$ID" >> "$C/users/aluno/history"
printf 'lixo{nao-json' > "$SPOOLDIR/sp:$NOW:$ID:aluno:submit:col#pa:C"
( cd "$ROOT/daemons" && SPOOLDIR="$SPOOLDIR" SPOOLDONEDIR="$SPOOLDONEDIR" CONTESTSDIR="$FIX" \
    RUNDIR="$RUN" JUDGE_BACKEND=queue INTAKE_MODE=queue bash judged.sh --drain >/dev/null 2>&1 )
BODY="$(grep ":$ID$" "$C/users/aluno/history")"
ck "linha virou Judge Error"       'grep -q ":Judge Error:" <<<"$BODY"'
ck "clog registrou"                'grep -q "spool-judge-error" "$C/var/admin-audit.log"'

echo "== reconciliador: pendente órfã velha é resolvida =="
# sem fonte -> Judge Error
ID2="cafecafecafecafecafecafecafecafe"
OLD=$((NOW - 3600))
printf '%s:col#pa:C:Not Answered Yet:%s:%s\n' "$OLD" "$OLD" "$ID2" >> "$C/users/aluno/history"
# com fonte -> re-enfileira (1ª vez)
ID3="beefbeefbeefbeefbeefbeefbeefbeef"
printf '%s:col#pa:C:Not Answered Yet:%s:%s\n' "$OLD" "$OLD" "$ID3" >> "$C/users/aluno/history"
mkdir -p "$C/users/aluno/submissions"; printf 'int main(){}' > "$C/users/aluno/submissions/$ID3.c"
rm -f "$C/var/.pending-count"
( cd "$ROOT/daemons" && SPOOLDIR="$SPOOLDIR" SPOOLDONEDIR="$SPOOLDONEDIR" CONTESTSDIR="$FIX" \
    RUNDIR="$RUN" JUDGE_BACKEND=queue INTAKE_MODE=queue PENDING_TTL_MIN=1 \
    bash judged.sh --reconcile >/dev/null 2>&1 )
BODY="$(grep ":$ID2$" "$C/users/aluno/history")"
ck "sem fonte → Judge Error"       'grep -q ":Judge Error:" <<<"$BODY"'
ck "com fonte → re-enfileirada"    '[[ -e "$SPOOLDIR/sp:$OLD:$ID3:aluno:rejulgar:col#pa:C" ]]'
ck "1 tentativa marcada"           '[[ -e "$RUN/.reconciled/$ID3" ]]'

echo "== a aba do admin: ver QUAIS são, dossiê e ações =="
# fixture: um treino mínimo (o handler exige sessão do treino) + pendente órfã
T="$FIX/treino"; mkdir -p "$T/var"
printf 'CONTEST_ID=treino\nCONTEST_NAME=Treino\nCONTEST_START=1\nCONTEST_END=99999999999\nPROBS=( x col#pa Alfa A col#pa )\n' > "$T/conf"
fx_user "$T" tadmin.admin p "Admin"
fx_user "$T" joana s "Joana"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino tadmin.admin Admin "$NOW" > "$SESS/tadm"
ID4="feedfeedfeedfeedfeedfeedfeedfeed"
printf '%s:col#pa:C:Not Answered Yet:%s:%s\n' "$((NOW-1200))" "$((NOW-1200))" "$ID4" >> "$T/users/joana/history"
mkdir -p "$T/users/joana/submissions" "$T/users/joana/mojlog"
printf 'int main(){}' > "$T/users/joana/submissions/$ID4.c"
printf '<html>log da joana</html>' > "$T/users/joana/mojlog/$ID4.html"

qcall(){ OUT="$(PATH_INFO=/treino/admin/queue REQUEST_METHOD="${1:-GET}" QUERY_STRING="${2:-}" \
    HTTP_AUTHORIZATION="Bearer ${4:-tadm}" bash "$ROUTER" <<<"${3:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
qcall GET 'details=1'
ck "details lista a pendente"     '[[ "$(jq -r "[.pending_details[]|select(.id==\"$ID4\")]|length" <<<"$BODY")" == 1 ]]'
ck "com idade e estado"           '[[ "$(jq -r ".pending_details[]|select(.id==\"$ID4\")|.age_s" <<<"$BODY")" -ge 1200 ]] && grep -q "sem-rastro" <<<"$BODY"'
ck "e has_source"                 '[[ "$(jq -r ".pending_details[]|select(.id==\"$ID4\")|.has_source" <<<"$BODY")" == true ]]'
qcall GET "sub=treino:joana:$ID4"
ck "dossiê traz history+mojlog"   'grep -q "Not Answered Yet" <<<"$BODY" && grep -q "log da joana" <<<"$BODY"'
qcall POST '' "{\"action\":\"requeue\",\"contest\":\"treino\",\"login\":\"joana\",\"id\":\"$ID4\"}"
ck "requeue cria o marcador"      '[[ "$(jq -r .requeued <<<"$BODY")" == true ]] && ls "$SPOOLDIR" | grep -q ":$ID4:joana:rejulgar:"'
ID5="f00df00df00df00df00df00df00df00d"
printf '%s:col#pa:EXE:Not Answered Yet:%s:%s\n' "$((NOW-1200))" "$((NOW-1200))" "$ID5" >> "$T/users/joana/history"
qcall POST '' "{\"action\":\"requeue\",\"contest\":\"treino\",\"login\":\"joana\",\"id\":\"$ID5\"}"
ck "requeue sem fonte → 409"      'grep -q "no_source" <<<"$BODY"'
qcall POST '' "{\"action\":\"resolve\",\"contest\":\"treino\",\"login\":\"joana\",\"id\":\"$ID5\",\"verdict\":\"Judge Error\"}"
ck "resolve emite setverdict"     '[[ "$(jq -r .resolved <<<"$BODY")" == true ]] && ls "$SPOOLDIR" | grep -q ":setverdict:"'
( cd "$ROOT/daemons" && SPOOLDIR="$SPOOLDIR" SPOOLDONEDIR="$SPOOLDONEDIR" CONTESTSDIR="$FIX" \
    RUNDIR="$RUN" JUDGE_BACKEND=queue INTAKE_MODE=queue bash judged.sh --drain >/dev/null 2>&1 )
ck "judged aplica o Judge Error"  'grep ":$ID5$" "$T/users/joana/history" | grep -q ":Judge Error:"'
qcall POST '' "{\"action\":\"resolve\",\"contest\":\"treino\",\"login\":\"joana\",\"id\":\"$ID4\",\"verdict\":\"Accepted,100p\"}"
ck "veredicto fora da lista → 400" 'grep -q "verdict_invalid" <<<"$BODY"'
qcall GET 'details=1' '' joana-token
ck "não-admin → 401/403"          '! grep -q "pending_details" <<<"$BODY"'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
