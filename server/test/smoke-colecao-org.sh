#!/bin/bash
# smoke-colecao-org.sh — "SEM coleção = a coleção homônima da ORG", em TODO lugar que diz a coleção.
#
# Relato do Ribas (25/09/2026): os problemas da org `grub` apareciam na coleção "grub" na gestão, mas o
# treino livre não listava a coleção. O editor web (campo em branco) e o `moj new` mandam
# `collections: []`; o /problems/create só aplicava o default da org com o campo AUSENTE, o [] ia p/ o
# meta, e as duas leituras divergiam: o índice de donos (gen-problem-owners.sh — a gestão) trocava o
# vazio pela org; o json servível (gen-problem-json.sh — o treino) copiava o []. 21 problemas públicos
# em 5 orgs. Prende:
#   · o /problems/create grava a coleção da org quando a lista chega VAZIA (e respeita a escolhida);
#   · os DOIS geradores dão a MESMA coleção p/ o mesmo pacote — vazio, ausente, lixo, escolhida e nome
#     com VÍRGULA (o índice juntava por vírgula e partia "Curso, parte 1" em duas coleções);
#   · o que o treino lista (/treino/problems) traz a coleção da org.
# Precisa do mojtools irmão (MOJTOOLS_DIR) e de pandoc (render do enunciado); senão SKIP.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
MOJTOOLS="${MOJTOOLS_DIR:-$ROOT/../../mojtools}"; [[ -f "$MOJTOOLS/gen-problem-json.sh" ]] || MOJTOOLS="$ROOT/../mojtools"
[[ -f "$MOJTOOLS/gen-problem-json.sh" && -f "$MOJTOOLS/gen-problem-owners.sh" ]] || { echo "SKIP: sem mojtools"; exit 0; }
command -v pandoc >/dev/null || { echo "SKIP: sem pandoc"; exit 0; }
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export CONTESTSDIR="$W/contests" SESSIONDIR="$W/sess" RUNDIR="$W/run" MOJ_PROBLEMS_DIR="$W/moj-problems" MOJTOOLS_DIR="$MOJTOOLS"
T="$CONTESTSDIR/treino"; mkdir -p "$T/var/jsons" "$T/var/jsons-private" "$SESSIONDIR" "$RUNDIR" "$MOJ_PROBLEMS_DIR"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\n' > "$T/conf"
fx_user "$T" autor.admin p "Autor"
printf 'CONTEST=treino\nLOGIN=autor.admin\nUSERFULLNAME=Autor\nLOGINAT=1\n' > "$SESSIONDIR/tok"
echo '{"grub":{"members":["autor.admin"],"admins":["autor.admin"],"public_allowed":true}}' > "$T/var/orgs.json"
echo '{"grub":{"owner":"autor.admin"},"Outra":{"owner":"autor.admin"}}' > "$T/var/collections.json"
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:-${BODY:0:300}}"; ((fail++)); fi; }
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${4:-}" HTTP_AUTHORIZATION="Bearer tok" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
meta(){ jq -c '.collections' "$MOJ_PROBLEMS_DIR/grub/$1/.moj-meta.json" 2>/dev/null; }
ENUN='% Soma\n\nSome a+b.\n\n## Entrada\n\nDois inteiros.\n\n## Saída\n\nA soma.\n'

echo "== /problems/create =="
call /problems/create POST "$(jq -cn --arg e "$(printf "$ENUN")" '{repo:"grub", prob:"vazia", enunciado_md:$e, collections:[]}')"
DBG="$BODY"; ck "lista VAZIA (editor com o campo em branco, moj new) → a coleção da org" '[[ "$(meta vazia)" == "[\"grub\"]" ]]'
call /problems/create POST "$(jq -cn --arg e "$(printf "$ENUN")" '{repo:"grub", prob:"ausente", enunciado_md:$e}')"
ck "campo AUSENTE → a coleção da org (como sempre)" '[[ "$(meta ausente)" == "[\"grub\"]" ]]'
call /problems/create POST "$(jq -cn --arg e "$(printf "$ENUN")" '{repo:"grub", prob:"escolhida", enunciado_md:$e, collections:["Outra"]}')"
ck "coleção escolhida é respeitada (sem a da org)" '[[ "$(meta escolhida)" == "[\"Outra\"]" ]]'

echo "== os dois geradores concordam =="
# os pacotes de ANTES do conserto: o [] gravado no meta, a chave ausente e lixo — todos públicos
for p in legado-vazio legado-sem-chave legado-lixo legado-virgula; do
  d="$MOJ_PROBLEMS_DIR/grub/$p"; mkdir -p "$d/docs" "$d/tests/input" "$d/tests/output"
  printf "$ENUN" > "$d/docs/enunciado.md"; printf '1 2\n' > "$d/tests/input/sample1"; printf '3\n' > "$d/tests/output/sample1"
  printf 'Fulano\n' > "$d/author"
done
echo '{"owner":"autor.admin","public":true,"collections":[]}'        > "$MOJ_PROBLEMS_DIR/grub/legado-vazio/.moj-meta.json"
echo '{"owner":"autor.admin","public":true}'                         > "$MOJ_PROBLEMS_DIR/grub/legado-sem-chave/.moj-meta.json"
echo '{"owner":"autor.admin","public":true,"collections":["",null]}' > "$MOJ_PROBLEMS_DIR/grub/legado-lixo/.moj-meta.json"
echo '{"owner":"autor.admin","public":true,"collections":["Curso, parte 1","Outra"]}' > "$MOJ_PROBLEMS_DIR/grub/legado-virgula/.moj-meta.json"
for p in vazia ausente escolhida; do jq -c '.public = true' "$MOJ_PROBLEMS_DIR/grub/$p/.moj-meta.json" > "$W/m" && mv "$W/m" "$MOJ_PROBLEMS_DIR/grub/$p/.moj-meta.json"; done
for p in vazia ausente escolhida legado-vazio legado-sem-chave legado-lixo legado-virgula; do
  CONTESTSDIR="$CONTESTSDIR" MOJTOOLS_DIR="$MOJTOOLS" MOJ_TL_STORE="$W/tl" bash "$MOJTOOLS/gen-problem-json.sh" "$MOJ_PROBLEMS_DIR/grub/$p" "grub#$p" >/dev/null 2>&1
done
CONTESTSDIR="$CONTESTSDIR" MOJ_PROBLEMS_DIR="$MOJ_PROBLEMS_DIR" bash "$MOJTOOLS/gen-problem-owners.sh" >/dev/null 2>&1
IDX="$T/var/problem-owners.json"
for p in vazia ausente escolhida legado-vazio legado-sem-chave legado-lixo legado-virgula; do
  js="$(jq -c '.collections' "$T/var/jsons/grub#$p.json" 2>/dev/null)"
  ix="$(jq -c --arg id "grub#$p" '.problems[] | select(.id == $id) | .collections' "$IDX" 2>/dev/null)"
  want='["grub"]'; [[ "$p" == escolhida ]] && want='["Outra"]'; [[ "$p" == legado-virgula ]] && want='["Curso, parte 1","Outra"]'
  DBG="treino(json)=$js gestão(índice)=$ix"
  ck "grub#$p: treino e gestão dizem $want" '[[ "$js" == "$want" && "$ix" == "$want" ]]'
done

echo "== o treino lista a coleção da org =="
call /treino/problems GET
L="$(jq -c 'if type == "array" then . else (.problems // []) end | map({id, c:(.collections // [])})' <<<"$BODY" 2>/dev/null)"; DBG="$L"
ck "/treino/problems: 5 na coleção grub, 2 na Outra, 1 na \"Curso, parte 1\"" '[[ "$(jq "[.[] | select(.c | index(\"grub\"))] | length" <<<"$L")" == 5 && "$(jq "[.[] | select(.c | index(\"Outra\"))] | length" <<<"$L")" == 2 && "$(jq "[.[] | select(.c | index(\"Curso, parte 1\"))] | length" <<<"$L")" == 1 ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
