#!/bin/bash
# smoke-contest-tz.sh — FUSO da prova (CONTEST_TZ), 03/10/2026. O organizador do Chile pôs America/Belem porque a
# lista de sugestões (11 fusos do Brasil) não tinha o dele; e a criação JOGAVA FORA o fuso do assistente. Afirma:
#   • Central › Regras (/contest/admin/settings): America/Santiago é aceito; nome ANTIGO (o que o Chrome sugere,
#     America/Buenos_Aires) é aceito e gravado com o nome ATUAL — a imagem (Debian trixie) não tem os antigos; o
#     mapa vem do tzdata.zi. Aqui a árvore de zoneinfo é FALSA (MOJ_ZONEINFO) p/ ser igual à da imagem; nome
#     desconhecido = 422 tz_invalid; vazio = volta ao padrão (linha some do conf);
#   • criação (/treino/contest-create/create): `tz` vira CONTEST_TZ (nome antigo → atual; inválido = 422 e nada
#     criado); export, duplicate e template levam o fuso.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; ZI="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$ZI"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
# zoneinfo como o da imagem: só os nomes ATUAIS + o tzdata.zi com as linhas `L <atual> <antigo>`
mkdir -p "$ZI/America/Argentina" "$ZI/Asia"
for z in America/Santiago America/Belem America/Sao_Paulo America/Argentina/Buenos_Aires Asia/Kolkata; do : > "$ZI/$z"; done
printf 'Z America/Santiago -4:42:45 - LMT 1890\nL America/Argentina/Buenos_Aires America/Buenos_Aires\nL Asia/Kolkata Asia/Calcutta\nL Europe/Kyiv Europe/Kiev\n' > "$ZI/tzdata.zi"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" MOJ_ZONEINFO="$ZI"
NOW="$EPOCHSECONDS"; FUT=$(( NOW + 100000 ))
T="$FIX/treino"; mkdir -p "$T/var/jsons"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=treino\n' > "$T/conf"
fx_user "$T" prof.admin p "Prof"; printf 'CONTEST=treino\nLOGIN=prof.admin\nUSERFULLNAME=Prof\nLOGINAT=1\n' > "$SESS/t-prof"
fx_owners_index "$FIX"
C="$FIX/ct"; mkdir -p "$C/var" "$C/enunciados"
{ printf 'CONTEST_ID=ct\nCONTEST_NAME=Prova\nCONTEST_TYPE=icpc\nCONTEST_PRIORITY=prova\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW-3600))" "$FUT"; printf "PROBS=( x col#pa Alfa A col#pa )\n"; } > "$C/conf"
printf 'prof.admin\n' > "$C/owner"; printf 'prof.admin\t%s\ticpc\n' "$NOW" > "$C/created-by"
fx_user "$C" ct.admin p "Admin"; printf 'CONTEST=ct\nLOGIN=ct.admin\nUSERFULLNAME=Admin\nLOGINAT=1\n' > "$SESS/c-adm"
call(){ # <path> <method> <body> <token> [query]
  local o; o="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer $4" bash "$ROUTER" <<<"$3" 2>/dev/null)"
  STATUS="$(printf '%s' "$o" | sed -n 's/^Status: \([0-9]*\).*/\1/p' | head -1)"; STATUS="${STATUS:-200}"
  BODY="$(printf '%s' "$o" | awk 'f{print} /^\r?$/{f=1}')"; }
regras(){ call /contest/admin/settings POST "$1" c-adm "contest=ct"; }
tzof(){ local v; v="$(grep -m1 '^CONTEST_TZ=' "$FIX/$1/conf" 2>/dev/null | cut -d= -f2-)"; printf '%s' "${v//\\/}"; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: $STATUS ${BODY:0:200}"; ((fail++)); fi; }

echo "== Central › Regras =="
regras '{"tz":"America/Santiago"}'
ck "America/Santiago aceito"                       '[[ "$STATUS" == 200 && "$(tzof ct)" == America/Santiago ]]'
call /contest/admin/settings GET '' c-adm "contest=ct"
ck "GET devolve o fuso"                            '[[ "$(jq -r .tz <<<"$BODY")" == America/Santiago ]]'
regras '{"tz":"America/Buenos_Aires"}'
ck "nome antigo aceito e gravado com o atual"      '[[ "$STATUS" == 200 && "$(tzof ct)" == America/Argentina/Buenos_Aires ]]'
regras '{"tz":"Asia/Calcutta"}'
ck "outro nome antigo (Asia/Calcutta → Asia/Kolkata)" '[[ "$STATUS" == 200 && "$(tzof ct)" == Asia/Kolkata ]]'
regras '{"tz":"Europe/Kiev"}'
ck "antigo cujo atual não existe na árvore: 422"   '[[ "$STATUS" == 422 && "$(tzof ct)" == Asia/Kolkata ]]'
regras '{"tz":"Marte/Olympus"}'
ck "desconhecido: 422 tz_invalid, nada gravado"    '[[ "$STATUS" == 422 && "$(jq -r .error.code <<<"$BODY")" == tz_invalid && "$(tzof ct)" == Asia/Kolkata ]]'
regras '{"tz":"../../etc/passwd"}'
ck "caminho no nome: 422"                          '[[ "$STATUS" == 422 ]]'
regras '{"tz":""}'
ck "vazio: volta ao padrão (linha some)"           '[[ "$STATUS" == 200 ]] && ! grep -q "^CONTEST_TZ=" "$C/conf"'

echo "== criação, export, duplicate, template =="
spec(){ printf '{"id":"%s","name":"%s","mode":"icpc","end":%s,"tz":"%s","problems":[{"problem_id":"a/b","name":"AB"}]}' "$1" "$1" "$FUT" "$2"; }
call /treino/contest-create/create POST "$(spec nz1 America/Santiago)" t-prof
ck "criação grava o fuso do assistente (antes ia fora)" '[[ "$STATUS" == 200 && "$(tzof nz1)" == America/Santiago ]]'
call /treino/contest-create/create POST "$(spec nz2 America/Buenos_Aires)" t-prof
ck "criação: nome antigo vira o atual"             '[[ "$STATUS" == 200 && "$(tzof nz2)" == America/Argentina/Buenos_Aires ]]'
call /treino/contest-create/create POST "$(spec nz3 Marte/Olympus)" t-prof
ck "criação: fuso inválido = 422, nada criado"     '[[ "$STATUS" == 422 && "$(jq -r .error.code <<<"$BODY")" == tz_invalid && ! -d "$FIX/nz3" ]]'
call /treino/contest-create/create POST "$(spec nz4 '')" t-prof
ck "criação sem fuso: sem linha no conf"           '[[ "$STATUS" == 200 ]] && ! grep -q "^CONTEST_TZ=" "$FIX/nz4/conf"'
call /treino/contest-create/export GET '' t-prof "id=nz1"
ck "export leva o fuso"                            '[[ "$(jq -r ".spec.tz // .tz" <<<"$BODY")" == America/Santiago ]]'
call /treino/contest-create/duplicate POST '{"from":"nz1","id":"nz1copia"}' t-prof
ck "duplicate mantém o fuso"                       '[[ "$STATUS" == 200 && "$(tzof nz1copia)" == America/Santiago ]]'
call /treino/contest-create/templates POST '{"op":"save","name":"chile","from_contest":"nz1"}' t-prof
call /treino/contest-create/templates GET '' t-prof "name=chile"
ck "template guarda o fuso"                        '[[ "$(jq -r .template.spec.tz <<<"$BODY")" == America/Santiago ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
