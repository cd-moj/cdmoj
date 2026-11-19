#!/bin/bash
# smoke-teams-meta-big.sh — regras de países e escolas (teams-meta.json) GRANDES: cada regra pode levar o brasão da escola
# como data: URI (o `logo` do editor), e a lista passa dos 128 KiB POR ARGUMENTO do jq. 19/11/2026, cnpci-2026: a criação
# mandava a lista ao `jq --argjson`, o jq nem rodava (Argument list too long) e o `>` deixava o teams-meta.json VAZIO; daí
# todo GET de /contest/admin/config (Evento › Balões, Sedes…) virava 500 build_fail. Afirma:
#   • criar com uma regra de brasão de ~200 KB grava o arquivo inteiro (a regra e o brasão);
#   • o GET do config responde 200 com a regra; o POST do painel grava a mesma lista grande;
#   • o export e o duplicate levam a regra grande (a seção do módulo ia por argv no export);
#   • um teams-meta.json VAZIO (o dano antigo) é lido como "sem regras", com 200.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
T="$FIX/treino"; mkdir -p "$T/var/jsons"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\nSUPERADMINS=boss.admin\n' > "$T/conf"
fx_user "$T" boss.admin p "Boss"
printf 'CONTEST=treino\nLOGIN=boss.admin\nUSERFULLNAME=Boss\nLOGINAT=1\n' > "$SESS/boss"
printf '%s' '{"id":"bankprob","title":"Banco Prob","tags":[],"statement_html_b64":"PGgxPm9pPC9oMT4="}' > "$T/var/jsons/bankprob.json"
printf '%s' '{"problems":[{"id":"bankprob","title":"Banco Prob","owner":"someone","collaborators":[],"public":true}]}' > "$T/var/problem-owners.json"
NOW="$(date +%s)"; FUT=$(( NOW + 100000 ))
call(){ # <path> <method> <arquivo-do-corpo|''> <token> <query>
  OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer $4" CONTEST_HOST="${6:-}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" < "${3:-/dev/null}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

LOGO="data:image/png;base64,$(head -c 150000 /dev/urandom | base64 -w0)"   # ~200 KB, como um brasão de verdade
printf '%s' "$LOGO" > "$FIX/logo.txt"   # (o próprio teste não passa o brasão por argv: o teto é o mesmo)
jq -cn --rawfile l "$FIX/logo.txt" --argjson fut "$FUT" '{id:"big-c", name:"Big", mode:"icpc", priority:"prova", end:$fut,
  admin:{login:"big.admin", password:"pw"}, problems:[{bank_id:"bankprob", letter:"A"}],
  modules:{sedes:{on:true, regions:[{name:"MX", regex:"^mx"}], teams_meta:[{regex:"^mx", country:"mx", school:"ESC", logo:$l}]}}}' > "$FIX/spec.json"
ck "o spec passa dos 128 KiB (o teste vale)" '(( $(wc -c < "$FIX/spec.json") > 131072 ))'

echo "== criação =="
call /treino/contest-create/create POST "$FIX/spec.json" boss
ck "criou big-c"                                   '[[ "$(jq -r .contest_id <<<"$BODY")" == big-c ]]'
TM="$FIX/big-c/teams-meta.json"
ck "teams-meta.json não ficou vazio (era 0 bytes)" '[[ -s "$TM" ]]'
ck "…com a regra e o brasão inteiros"              '[[ "$(jq -r ".rules[0].school" "$TM")" == ESC ]] && cmp -s <(jq -j ".rules[0].logo" "$TM") "$FIX/logo.txt"'

echo "== GET/POST do config (Evento › Balões, Sedes) =="
printf 'CONTEST=big-c\nLOGIN=big.admin\nUSERFULLNAME=x\nLOGINAT=1\n' > "$SESS/adm"
call /contest/admin/config GET '' adm 'contest=big-c' big-c
ck "GET 200 com a regra grande"                    '[[ "$OUT" != *"Status: 500"* && "$(jq -r ".teams_meta[0].logo | length" <<<"$BODY")" == "${#LOGO}" ]]'
ck "…e as sedes e as cores"                         '[[ "$(jq -r ".regions[0].name" <<<"$BODY")" == MX && "$(jq -r ".colors|type" <<<"$BODY")" == object ]]'
jq -c '{teams_meta:.teams_meta}' <<<"$BODY" > "$FIX/post.json"; rm -f "$TM"
call /contest/admin/config POST "$FIX/post.json" adm 'contest=big-c' big-c
ck "POST do painel com a lista grande: salvo"      '[[ "$(jq -r .saved <<<"$BODY")" == true ]]'
ck "…gravou o arquivo inteiro"                     'cmp -s <(jq -j ".rules[0].logo" "$TM" 2>/dev/null) "$FIX/logo.txt"'
ck "…sem temporário sobrando"                       '! ls "$FIX/big-c"/teams-meta.json.tmp.* >/dev/null 2>&1'

echo "== cópia: export e duplicate levam a regra grande =="
call /treino/contest-create/export GET '' boss 'id=big-c'
ck "export com o brasão inteiro"                    'cmp -s <(jq -j ".modules.sedes.teams_meta[0].logo" <<<"$BODY" 2>/dev/null) "$FIX/logo.txt"'
printf '{"from":"big-c","id":"big-d"}' > "$FIX/dup.json"
call /treino/contest-create/duplicate POST "$FIX/dup.json" boss
ck "duplicate: a cópia tem o teams-meta.json inteiro" '[[ "$(jq -r .contest_id <<<"$BODY")" == big-d ]] && cmp -s <(jq -j ".rules[0].logo" "$FIX/big-d/teams-meta.json" 2>/dev/null) "$FIX/logo.txt"'

echo "== arquivo vazio (o dano de antes) =="
: > "$TM"
call /contest/admin/config GET '' adm 'contest=big-c' big-c
ck "teams-meta.json vazio: GET 200 com teams_meta []" '[[ "$OUT" != *"Status: 500"* && "$(jq -c .teams_meta <<<"$BODY")" == "[]" ]]'
printf 'nao-json{' > "$TM"
call /contest/admin/config GET '' adm 'contest=big-c' big-c
ck "teams-meta.json corrompido: GET 200 com teams_meta []" '[[ "$(jq -c .teams_meta <<<"$BODY")" == "[]" ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
