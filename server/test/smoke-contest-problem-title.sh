#!/bin/bash
# SANFONA DO CONTEST COM O TÍTULO DO PROBLEMA, não o id. Contest criado por spec sem `name` gravava o
# id como nome ("saad-problems#knight-moves" — relato do Daniel Saad, 2026-09-18). A criação foi
# consertada (smoke-contest-create.sh); ESTE teste cobre os contests que JÁ nasceram assim: o
# /contest/problems troca o nome-que-é-só-o-id pelo título do banco. Nome de verdade nunca é trocado.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$HERE/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN"; mkdir -p "$RUN/tl"
NOW="$EPOCHSECONDS"; T="$FIX/treino"; mkdir -p "$T/var/jsons" "$T/var/jsons-private"
printf 'CONTEST_ID=treino\n' > "$T/conf"; printf '{"problems":[]}' > "$T/var/problem-owners.json"
printf '{"id":"org#pub","title":"Movimento do Cavalo","public":true}' > "$T/var/jsons/org#pub.json"
printf '{"id":"org#priv","title":"Metrô","public":false}' > "$T/var/jsons-private/org#priv.json"
C="$FIX/ct"; mkdir -p "$C/var" "$C/enunciados"
{ printf 'CONTEST_ID=ct\nCONTEST_NAME=P\nCONTEST_TYPE=icpc\nSHOWTL=0\nCONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW-600))" "$((NOW+3600))"
  printf "PROBS=( cdmoj 'org#pub' 'org#pub' A 'org#pub' cdmoj 'org#priv' 'org#priv' B 'org#priv' cdmoj 'org#pub' 'Nome Escolhido' C 'org#pub' cdmoj 'org#fora' 'org#fora' D 'org#fora' )\n"; } > "$C/conf"
fx_user "$C" time1 s T1; printf 'CONTEST=ct\nLOGIN=time1\nUSERFULLNAME=T\nLOGINAT=%s\n' "$NOW" > "$SESS/tk"
OUT="$(PATH_INFO=/contest/problems REQUEST_METHOD=GET QUERY_STRING=contest=ct HTTP_AUTHORIZATION="Bearer tk" bash "$ROUTER" 2>/dev/null)"
BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"
nm(){ jq -r --arg l "$1" '.problems[]|select(.short_name==$l)|.full_name' <<<"$BODY"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }
ck "nome == id ⇒ título do banco (público)"  '[[ "$(nm A)" == "Movimento do Cavalo" ]]'
ck "…e do banco PRIVADO (rascunho)"          '[[ "$(nm B)" == "Metrô" ]]'
ck "nome de verdade NÃO é trocado"           '[[ "$(nm C)" == "Nome Escolhido" ]]'
ck "fora do banco: fica o id (nada inventa)" '[[ "$(nm D)" == "org#fora" ]]'
ck "problem_id intacto (é o que o /submit usa)" '[[ "$(jq -r ".problems[0].problem_id" <<<"$BODY")" == "org#pub" ]]'
echo; echo "RESULT: $pass passed, $fail failed"; (( fail == 0 ))
