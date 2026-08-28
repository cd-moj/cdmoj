#!/bin/bash
# molde-diff.sh — diferencial fcgiwrap × molde para a migração de rota (fase 4 do plano).
#   molde-diff.sh capture <dir> <base-url> <token> [rota...]
#   molde-diff.sh compare <dir-antes> <dir-depois>
# Uso: `capture` ANTES de ligar a rota no molde (baseline fcgiwrap) e DE NOVO depois
# (molde servindo); `compare` exige status+corpo idênticos módulo campos voláteis
# (epochs de "agora" — normalizados). Rode as capturas COLADAS no tempo: conteúdo real
# (placar, notícias) muda com o mundo, não com o backend.
set -u
ACT="${1:?uso: molde-diff.sh capture|compare ...}"
ROTAS_DEFAULT=(contest/updates contest/score contest/basic contest/problems contest/rounds
               contest/navbuttons contest/balloons contest/staff/queue)

norm(){ # normaliza voláteis: epochs de 10 dígitos "de agora" viram E10 (json continua diffável)
  sed -E 's/17[0-9]{8}/E10/g'
}

case "$ACT" in
  capture)
    DIR="${2:?dir}"; BASE="${3:?base-url}"; TOK="${4:?token}"; shift 4
    ROTAS=("${@:-${ROTAS_DEFAULT[@]}}"); [[ $# -gt 0 ]] || ROTAS=("${ROTAS_DEFAULT[@]}")
    mkdir -p "$DIR"
    C="${MOLDE_DIFF_CONTEST:-zz-carga-2026}"
    for r in "${ROTAS[@]}"; do
      slug="${r//\//-}"
      code="$(curl -sk --compressed -m 30 -H "Authorization: Bearer $TOK" \
        -o >(norm > "$DIR/$slug.body") -w '%{http_code}' \
        "$BASE/api/v1/$r?contest=$C")"
      printf '%s\n' "$code" > "$DIR/$slug.code"
      echo "  $r -> $code ($(wc -c < "$DIR/$slug.body") B)"
    done
    ;;
  compare)
    A="${2:?antes}"; B="${3:?depois}"; rc=0
    for f in "$A"/*.code; do
      slug="$(basename "$f" .code)"
      if ! diff -q "$A/$slug.code" "$B/$slug.code" >/dev/null 2>&1; then
        echo "DIVERGE status: $slug ($(cat "$A/$slug.code") x $(cat "$B/$slug.code" 2>/dev/null))"; rc=1
      elif ! diff -q "$A/$slug.body" "$B/$slug.body" >/dev/null 2>&1; then
        echo "DIVERGE corpo: $slug"; diff "$A/$slug.body" "$B/$slug.body" | head -5; rc=1
      else
        echo "  ok: $slug idêntico (status+corpo normalizado)"
      fi
    done
    exit $rc
    ;;
  *) echo "ação desconhecida: $ACT"; exit 2;;
esac
