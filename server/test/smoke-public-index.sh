#!/bin/bash
# O PORTÃO DA LISTA PÚBLICA. `contests/treino/var/jsons/` é servido SEM LOGIN (lista + enunciado
# inteiro) e quem decide o que entra lá é UM script só: mojtools/gen-problem-json.sh.
#
# Este teste existe porque esse portão já falhou em silêncio e vazou prova em elaboração para a
# internet: a checagem era `[[ "$(jq -r '.public // "unset"' meta)" == "false" ]]`, e o `//` do jq
# trata FALSE como vazio — `public:false` devolvia "unset", a comparação nunca dava certo, e TODO
# problema privado ia para a lista pública. O bug era invisível (o índice de donos usava o idioma
# certo, então o painel dizia "rascunho" enquanto o enunciado estava no ar).
#
# Regra (fail-closed): só é público se o .moj-meta.json disser `public:true`. Ausente = PRIVADO.
# E o servidor pode vetar por cima (MOJ_FORCE_PRIVATE=1: org sem public_allowed).
set -u
SELF="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ROOT="$(cd "$SELF/../.." && pwd)"                       # .../cdmoj
MOJTOOLS="${MOJTOOLS_DIR:-$ROOT/../mojtools}"
GEN="$MOJTOOLS/gen-problem-json.sh"
[[ -x "$GEN" || -r "$GEN" ]] || { echo "SKIP: sem mojtools em $MOJTOOLS"; exit 0; }
command -v pandoc >/dev/null || { echo "SKIP: sem pandoc (render do enunciado)"; exit 0; }

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
PKG="$W/pkg"; ID="orgx#probx"
mkdir -p "$PKG/docs" "$PKG/tests/input" "$PKG/tests/output"
mkdir -p "$W/contests/treino/var/jsons" "$W/contests/treino/var/jsons-private"
printf 'Some a+b.\n\n## Entrada\n\nDois inteiros.\n\n## Saída\n\nA soma.\n' > "$PKG/docs/enunciado.md"
printf '1 2\n' > "$PKG/tests/input/sample1"; printf '3\n' > "$PKG/tests/output/sample1"
printf 'Fulano\n' > "$PKG/author"

PUB="$W/contests/treino/var/jsons/$ID.json"
PRIV="$W/contests/treino/var/jsons-private/$ID.json"
fails=0
gen(){ # gen <meta-json|-> <force_private>
  rm -f "$PUB" "$PRIV"
  if [[ "$1" == "-" ]]; then rm -f "$PKG/.moj-meta.json"; else printf '%s' "$1" > "$PKG/.moj-meta.json"; fi
  MOJ_FORCE_PRIVATE="$2" CONTESTSDIR="$W/contests" MOJTOOLS_DIR="$MOJTOOLS" MOJ_TL_STORE="$W/tl" \
    bash "$GEN" "$PKG" "$ID" >/dev/null 2>&1
}
chk(){ # chk <descrição> <esperado-publico:0|1>
  local d="$1" want="$2" pub=0
  [[ -f "$PUB" ]] && pub=1
  if [[ "$pub" == "$want" && -f "$PRIV" ]]; then
    printf '  ok   %s\n' "$d"
  else
    printf '  FAIL %s (público=%s esperado=%s, privado_existe=%s)\n' \
      "$d" "$pub" "$want" "$([[ -f "$PRIV" ]] && echo 1 || echo 0)"; fails=$((fails+1))
  fi
}

echo "== portão da lista pública (gen-problem-json.sh) =="
gen '{"public":true}'  0; chk 'meta public:true            -> PÚBLICO'   1
gen '{"public":false}' 0; chk 'meta public:false           -> privado'   0   # o bug: virava público
gen '{}'               0; chk 'meta sem o campo public     -> privado'   0   # fail-closed
gen '-'                0; chk 'sem .moj-meta.json          -> privado'   0   # fail-closed
gen '{"public":true}'  1; chk 'MOJ_FORCE_PRIVATE=1 (org)   -> privado'   0   # 2ª camada

# o campo `public` tem de ir DENTRO do json (a 3ª camada, na leitura, confere `.public != false`)
gen '{"public":false}' 0
if jq -e '.public == false' "$PRIV" >/dev/null 2>&1; then echo "  ok   json privado carrega public:false"
else echo "  FAIL json privado NÃO carrega o campo public"; fails=$((fails+1)); fi
gen '{"public":true}' 0
if jq -e '.public == true' "$PUB" >/dev/null 2>&1; then echo "  ok   json público carrega public:true"
else echo "  FAIL json público NÃO carrega o campo public"; fails=$((fails+1)); fi

# despublicar tem de LIMPAR o cache da lista (o banco de contests o lê SEM TTL)
printf '[]' > "$W/contests/treino/var/problems.json"
gen '{"public":false}' 0
if [[ ! -f "$W/contests/treino/var/problems.json" ]]; then echo "  ok   cache problems.json invalidado"
else echo "  FAIL cache problems.json sobreviveu à despublicação"; fails=$((fails+1)); fi

echo "== $fails falha(s) =="
exit $(( fails > 0 ))
