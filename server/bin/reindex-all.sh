#!/bin/bash
# reindex-all.sh — regera o json servível (var/jsons[-private]/<id>.json + sidecar) de TODOS os
# problemas do índice de donos, SEQUENCIAL, pelo MESMO caminho da API (`index_problem_now`, que
# aplica a camada da org — MOJ_FORCE_PRIVATE — e o stamp da lista). Existe p/ quando o FORMATO do
# json ganha campo novo (2026-09-16: `samples`) e os 1.4k jsons de produção precisam acompanhar.
# NUNCA chame gen-problem-json.sh cru em laço: sem a camada da org um problema `public:true` de
# org privada viraria json PÚBLICO (é o portão da lista anônima do treino).
#
# Uso: bash server/bin/reindex-all.sh [--only <regex-de-id>] [--dry-run] [--limit N]
#      (rode como o usuário do servidor, fora de horário de prova: é um pandoc por enunciado)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_DIR="$HERE/../api/v1"
source "$_DIR/lib/common.sh"; source "$_DIR/lib/tl-store.sh"
ONLY=""; DRY=0; LIMIT=0
while [[ $# -gt 0 ]]; do case "$1" in
  --only) ONLY="${2:-}"; shift 2;; --dry-run) DRY=1; shift;; --limit) LIMIT="${2:-0}"; shift 2;;
  *) echo "opção desconhecida: $1" >&2; exit 2;; esac; done
IDX="$CONTESTSDIR/treino/var/problem-owners.json"
[[ -f "$IDX" ]] || { echo "índice de donos ausente: $IDX" >&2; exit 1; }
mapfile -t IDS < <(jq -r '.problems[].id' "$IDX" | { if [[ -n "$ONLY" ]]; then grep -E -- "$ONLY"; else cat; fi; } | sort -u)
(( LIMIT > 0 )) && IDS=("${IDS[@]:0:$LIMIT}")
echo ">> ${#IDS[@]} problema(s) a reindexar$( (( DRY )) && echo ' (dry-run)')"
ok=0; miss=0; i=0; t0="$EPOCHSECONDS"
for id in "${IDS[@]}"; do
  i=$((i+1))
  pkg="$(pkg_path "$id")"
  if [[ -z "$pkg" ]]; then miss=$((miss+1)); echo "   [$i/${#IDS[@]}] $id: sem pacote (pulado)"; continue; fi
  if (( DRY )); then echo "   [$i/${#IDS[@]}] $id -> $pkg"; continue; fi
  if index_problem_now "$id" 0; then ok=$((ok+1)); else echo "   [$i/${#IDS[@]}] $id: FALHOU" >&2; fi
  (( i % 50 == 0 )) && echo "   … $i/${#IDS[@]} ($(( EPOCHSECONDS - t0 ))s)"
done
echo ">> pronto: $ok reindexado(s), $miss sem pacote, $(( EPOCHSECONDS - t0 ))s"
