#!/bin/bash
# /submit do TREINO só aceita problema que o LOGIN pode ver: público no índice, ou privado de que
# ele é dono/colaborador/membro da org. Antes disto um id privado CONHECIDO era julgado e devolvia
# veredicto + report a qualquer conta (achado de 2026-09-18, na leitura p/ a Participação Virtual)
# — uma sonda contra prova em elaboração. Em CONTEST o conjunto é o do conf: problema fora do PROBS = 404
# (não era conferido até 03/10/2026 — qualquer id do banco, até privado alheio, ia ao juiz).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" \
       SPOOLDIR="$RUN/spool/submissions" SPOOLDONEDIR="$RUN/spool/submissions-done"
mkdir -p "$SPOOLDIR" "$SPOOLDONEDIR"
NOW="$EPOCHSECONDS"
T="$FIX/treino"; mkdir -p "$T/var/jsons/pub" "$T/var/jsons-private/priv"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\nCONTEST_END=%s\n' "$((NOW+86400))" > "$T/conf"
printf '%s' '{"id":"pub#a","title":"Pub A","public":true,"languages":["c"]}'   > "$T/var/jsons/pub#a.json"
printf '%s' '{"id":"priv#x","title":"Priv X","public":false,"languages":["c"]}' > "$T/var/jsons-private/priv#x.json"
printf '%s' '{"problems":[
 {"id":"pub#a","title":"Pub A","owner":"dona","collaborators":[],"public":true},
 {"id":"priv#x","title":"Priv X","owner":"dona","collaborators":["colab"],"public":false}
]}' > "$T/var/problem-owners.json"
for u in aluno dona colab; do
  fx_user "$T" "$u" s "$u"
  printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino "$u" "$u" "$NOW" > "$SESS/tok-$u"
done
call(){ OUT="$(PATH_INFO=/submit REQUEST_METHOD=POST QUERY_STRING="contest=${3:-treino}" \
    HTTP_AUTHORIZATION="Bearer tok-$1" bash "$ROUTER" <<<"$2" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${OUT:0:200}"; ((fail++)); fi; }
B64="$(printf 'int main(){return 0;}' | base64 -w0)"
sub(){ call "$1" "{\"problem_id\":\"$2\",\"filename\":\"a.c\",\"code_b64\":\"$B64\"}"; }
nspool(){ find "$SPOOLDIR" -type f | wc -l; }

echo "== treino: público entra; privado alheio é 404 e NÃO vai à fila =="
sub aluno 'pub#a';  ck "público: aceito"                 'grep -q "\"success\":true" <<<"$BODY"'
n0="$(nspool)"
sub aluno 'priv#x'; ck "privado alheio: 404 problem_notfound" '[[ "$OUT" == *"Status: 404"* && "$(jq -r .error.code <<<"$BODY")" == problem_notfound ]]'
ck "…nada entrou no spool"                               '[[ "$(nspool)" == "$n0" ]]'
ck "…nem no history"                                     '! grep -q "priv#x" "$T/users/aluno/history"'
sub aluno 'nao#existe'; NF_BODY="$BODY"
ck "inexistente: 404 problem_notfound"                   '[[ "$OUT" == *"Status: 404"* && "$(jq -r .error.code <<<"$BODY")" == problem_notfound ]]'
sub aluno 'priv#x'
ck "privado e inexistente são INDISTINGUÍVEIS"           '[[ "$BODY" == "$NF_BODY" ]]'
echo "== quem pode ver o privado segue submetendo (autor testa o próprio problema) =="
sub dona  'priv#x'; ck "dona: aceito"                    'grep -q "\"success\":true" <<<"$BODY"'
sub colab 'priv#x'; ck "colaborador: aceito"             'grep -q "\"success\":true" <<<"$BODY"'
echo "== índice de donos quebrado: FAIL-CLOSED (503), nunca 'segue' =="
mv "$T/var/problem-owners.json" "$T/var/po.bak"; printf 'lixo' > "$T/var/problem-owners.json"
MOJTOOLS_DIR=/nonexistent sub aluno 'priv#x'
ck "privado com índice quebrado: recusa (404|503)"       '[[ "$OUT" == *"Status: 404"* || "$OUT" == *"Status: 503"* ]]'
sub aluno 'pub#a';  ck "público não depende do índice de donos" 'grep -q "\"success\":true" <<<"$BODY"'
mv "$T/var/po.bak" "$T/var/problem-owners.json"
echo "== CONTEST: só problema DA PROVA (PROBS do conf; auditoria 03/10/2026 — antes qualquer id ia ao juiz) =="
C="$FIX/ct"; mkdir -p "$C/var"
{ printf 'CONTEST_ID=ct\nCONTEST_TYPE=icpc\nUSER_STORE=v2\nCONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW-600))" "$((NOW+3600))"
  printf "PROBS=( cdmoj 'pub#a' 'Pub A' A 'pub#a' cdmoj leg/velho 'Velho' B velho )\n"; } > "$C/conf"
fx_user "$C" time1 s T1; printf 'CONTEST=ct\nLOGIN=time1\nUSERFULLNAME=T1\nLOGINAT=%s\n' "$NOW" > "$SESS/tok-time1"
csub(){ call time1 "{\"problem_id\":\"$1\",\"filename\":\"a.c\",\"code_b64\":\"$B64\"}" ct; }
csub 'pub#a';   ck "problema da prova: aceito"                    'grep -q "\"success\":true" <<<"$BODY"'
csub 'leg#velho'; ck "contest legado (statement_key sem #): o id canônico entra" 'grep -q "\"success\":true" <<<"$BODY"'
n0="$(nspool)"
csub 'priv#x';  ck "privado FORA da prova: 404 problem_notfound" '[[ "$OUT" == *"Status: 404"* && "$(jq -r .error.code <<<"$BODY")" == problem_notfound ]]'
csub 'outro#b'; ck "id qualquer fora da prova: 404"             '[[ "$OUT" == *"Status: 404"* ]]'
ck "…nada foi à fila nem ao history"                             '[[ "$(nspool)" == "$n0" ]] && ! grep -q "priv#x\|outro#b" "$C/users/time1/history"'
echo "== CONTEST offline-submit: a MESMA regra (pacote cifrado de problema fora da prova é rejeitado) =="
( source "$ROOT/api/v1/lib/common.sh" >/dev/null 2>&1; source "$ROOT/api/v1/lib/contest-offline.sh"
  offline_beacon ct time1 ) > "$FIX/beacon" 2>/dev/null
pkt(){ # <problem_id> -> pacote {v,wk,ct} cifrado com a pública do contest (o formato do moj-comp)
  local inner key iv mac wk ct
  inner="$(jq -cn --arg p "$1" --arg b "$(cat "$FIX/beacon")" --arg c "$B64" --argjson t "$EPOCHSECONDS" \
    '{v:1, l:"time1", c:"ct", problem_id:$p, filename:"a.c", code_b64:$c, claimed_utc:$t, beacon:$b}')"
  key="$(head -c32 /dev/urandom | od -An -tx1 | tr -d ' \n')"; iv="$(head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  mac="$(printf '%s' "$inner" | sha256sum | cut -d' ' -f1)"
  wk="$(printf '%s:%s:%s' "$key" "$iv" "$mac" | openssl pkeyutl -encrypt -pubin -inkey "$FIX/ct/secrets/offline.pub" -pkeyopt rsa_padding_mode:oaep | base64 -w0)"
  ct="$(printf '%s' "$inner" | openssl enc -aes-256-cbc -K "$key" -iv "$iv" | base64 -w0)"
  jq -cn --arg w "$wk" --arg c "$ct" '{v:1, wk:$w, ct:$c} | tojson'
}
if [[ -s "$FIX/ct/secrets/offline.pub" ]]; then
  OUT="$(PATH_INFO=/contest/offline-submit REQUEST_METHOD=POST QUERY_STRING=contest=ct HTTP_AUTHORIZATION="Bearer tok-time1" \
    bash "$ROUTER" <<<"{\"packets\":[$(pkt 'priv#x'),$(pkt 'pub#a')]}" 2>/dev/null)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"
  ck "offline: privado fora da prova rejeitado com o motivo" '[[ "$(jq -r ".results[0].status + \" \" + .results[0].reason" <<<"$BODY")" == "rejected problema não pertence a este contest" ]]'
  ck "offline: problema da prova aceito"                    '[[ "$(jq -r ".results[1].status" <<<"$BODY")" == accepted ]]'
else
  echo "  (openssl sem gerar chave — pulando o offline)"
fi
echo; echo "pass=$pass fail=$fail"; (( fail == 0 ))
