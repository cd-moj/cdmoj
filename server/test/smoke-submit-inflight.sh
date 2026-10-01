#!/bin/bash
# smoke-submit-inflight.sh — teto de envios NA FILA por conta (submit.sh, 01/10/2026): no treino e nos contests de
# LISTA (CONTEST_PRIORITY lista-publica/lista-privada; ausente = lista-publica) a conta tem no máx.
# SUBMIT_MAX_INFLIGHT (padrão 3) envios sem veredicto; o próximo leva 429 submit_busy. Prova sem teto; papel isento;
# a participação virtual (envio do treino) conta; o número muda pelo conf; 0 desliga; envio segurado na revisão
# manual não conta; POSTs paralelos não passam juntos do teto (flock por login); veredicto que sai libera a vaga.
# O servidor NÃO olha o conteúdo: o mesmo código pode ser reenviado (heurística aleatória) — só o número de
# pendentes é limitado.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" \
       SPOOLDIR="$RUN/spool/submissions" SPOOLDONEDIR="$RUN/spool/submissions-done"
unset SUBMIT_MAX_INFLIGHT
mkdir -p "$SPOOLDIR" "$SPOOLDONEDIR"
NOW="$EPOCHSECONDS"
mkc(){ # <id> <prioridade|""> [linhas extras do conf]
  local C="$FIX/$1"; mkdir -p "$C/var" "$C/enunciados"
  { printf 'CONTEST_ID=%s\nCONTEST_NAME=%s\nCONTEST_TYPE=icpc\n' "$1" "$1"
    [[ -n "$2" ]] && printf 'CONTEST_PRIORITY=%s\n' "$2"
    printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW-3600))" "$((NOW+3600))"
    printf "PROBS=( x col#pa Alfa A col#pa )\n"; printf '%s' "${3:-}"; } > "$C/conf"
  fx_user "$C" aluno s "Aluno"; fx_user "$C" "$1.admin" s "Admin"
  printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' "$1" aluno Aluno "$NOW" > "$SESS/alu-$1"
  printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' "$1" "$1.admin" Admin "$NOW" > "$SESS/adm-$1"
}
mkc lista lista-publica; mkc semprio ""; mkc priv lista-privada; mkc prova prova; mkc cinco lista-publica 'SUBMIT_MAX_INFLIGHT=5
'; mkc zero lista-publica 'SUBMIT_MAX_INFLIGHT=0
'
B64C="$(printf 'int main(){return 0;}' | base64 -w0)"
BODYJ="{\"problem_id\":\"col#pa\",\"filename\":\"a.c\",\"code_b64\":\"$B64C\"}"
sub(){ # <contest> [token] -> STATUS + BODY
  local o; o="$(PATH_INFO=/submit REQUEST_METHOD=POST QUERY_STRING="contest=$1" HTTP_AUTHORIZATION="Bearer ${2:-alu-$1}" \
    bash "$ROUTER" <<<"$BODYJ" 2>/dev/null)"
  STATUS="$(printf '%s' "$o" | sed -n 's/^Status: \([0-9]*\).*/\1/p' | head -1)"; STATUS="${STATUS:-200}"
  BODY="$(printf '%s' "$o" | awk 'f{print} /^\r?$/{f=1}')"; }
pend(){ grep -c 'Not Answered Yet' "$FIX/$1/users/${2:-aluno}/history" 2>/dev/null || true; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: $STATUS ${BODY:0:180}"; ((fail++)); fi; }

echo "== lista: 3 na fila, o 4º leva 429 (o MESMO código — o servidor não olha conteúdo) =="
for i in 1 2 3; do sub lista; done
ck "3 envios aceitos (mesmo código)"        '[[ "$(pend lista)" == 3 ]]'
# a resposta traz o que a web precisa p/ a linha pendente aparecer na hora (shared/submit-ux.js)
ck "resposta: id + epoch + problem_id + lang" '[[ -n "$(jq -r .submission_id <<<"$BODY")" && "$(jq -r .epoch <<<"$BODY")" -ge $NOW && "$(jq -r .problem_id <<<"$BODY")" == "col#pa" && "$(jq -r .lang <<<"$BODY")" == C ]]'
sub lista
ck "4º: 429 submit_busy, com inflight/max"  '[[ "$STATUS" == 429 && "$(jq -r .error.code <<<"$BODY")" == submit_busy && "$(jq -r .error.inflight <<<"$BODY")" == 3 && "$(jq -r .error.max <<<"$BODY")" == 3 ]]'
ck "o recusado não vira linha nem spool"   '[[ "$(pend lista)" == 3 && "$(ls "$SPOOLDIR" | grep -c ":lista:\|^lista:")" == 3 ]]'
# um veredicto libera a vaga
sed -i '0,/Not Answered Yet/s//Wrong Answer/' "$FIX/lista/users/aluno/history"
sub lista
ck "veredicto liberou a vaga"               '[[ "$STATUS" == 200 && "$(pend lista)" == 3 ]]'
echo "== quem tem teto e quem não =="
for i in 1 2 3 4; do sub semprio; done
ck "sem CONTEST_PRIORITY = lista (teto 3)"  '[[ "$STATUS" == 429 && "$(pend semprio)" == 3 ]]'
for i in 1 2 3 4; do sub priv; done
ck "lista-privada: teto 3"                  '[[ "$STATUS" == 429 && "$(pend priv)" == 3 ]]'
for i in 1 2 3 4 5 6 7; do sub prova; done
ck "prova: sem teto (7 pendentes)"          '[[ "$STATUS" == 200 && "$(pend prova)" == 7 ]]'
for i in 1 2 3 4 5; do sub lista adm-lista; done
ck "papel (.admin) isento"                  '[[ "$STATUS" == 200 && "$(pend lista lista.admin)" == 5 ]]'
for i in 1 2 3 4 5 6; do sub cinco; done
ck "SUBMIT_MAX_INFLIGHT=5 no conf"          '[[ "$STATUS" == 429 && "$(pend cinco)" == 5 ]]'
for i in 1 2 3 4 5; do sub zero; done
ck "SUBMIT_MAX_INFLIGHT=0 desliga"          '[[ "$STATUS" == 200 && "$(pend zero)" == 5 ]]'
# o treino (contest `treino`, CONTEST_TYPE=treino; problema público em var/jsons): teto 3 (a virtual é envio dele)
mkc treino lista-publica; sed -i 's/^CONTEST_TYPE=icpc$/CONTEST_TYPE=treino/' "$FIX/treino/conf"
mkdir -p "$FIX/treino/var/jsons"; printf '{"id":"col#pa","public":true}' > "$FIX/treino/var/jsons/col#pa.json"
for i in 1 2 3 4; do sub treino; done
ck "treino: teto 3"                         '[[ "$STATUS" == 429 && "$(pend treino)" == 3 ]]'
# revisão manual: envio SEGURADO em review/<id>.json já foi julgado (espera voto humano) — não ocupa a fila
mkc rev lista-publica
for i in 1 2 3; do sub rev; done
_sid="$(jq -r .submission_id <<<"$BODY")"; mkdir -p "$FIX/rev/review"; printf '{"id":"%s"}' "$_sid" > "$FIX/rev/review/$_sid.json"
sub rev
ck "segurado na revisão não conta (4º entra)" '[[ "$STATUS" == 200 && "$(pend rev)" == 4 ]]'
sub rev
ck "e o teto segue valendo p/ os outros"    '[[ "$STATUS" == 429 && "$(jq -r .error.inflight <<<"$BODY")" == 3 ]]'
echo "== paralelo: 6 POSTs ao mesmo tempo ⇒ exatamente 3 entram (flock por login) =="
mkc par lista-publica
for i in 1 2 3 4 5 6; do ( sub par; echo "$STATUS" > "$RUN/par.$i" ) & done; wait
ok200="$(cat "$RUN"/par.* | grep -c '^200$')"; ok429="$(cat "$RUN"/par.* | grep -c '^429$')"
ck "3 aceitos + 3 recusados"                '[[ "$ok200" == 3 && "$ok429" == 3 && "$(pend par)" == 3 ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
