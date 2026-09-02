#!/usr/bin/env bash
# session-index-seed.sh <contest> [--force]
# Semeia o ÍNDICE de sessões por login (run/sessions/.idx/<contest>/) a partir de todas as
# sessões existentes — é o que a "sessão única por time" (lib/session-index.sh) usa no login.
# O painel Pessoas › Sessões & anomalias semeia sozinho na 1ª abertura; este script é p/ fazer
# isso antes da prova (ou refazer com --force) sem abrir o painel. Estado de runtime, não código.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_DIR="$HERE/../api/v1"
source "$_DIR/lib/common.sh"; source "$_DIR/lib/auth.sh"; source "$_DIR/lib/session-index.sh"
c="${1:-}"; [[ -n "$c" ]] || { echo "uso: session-index-seed.sh <contest> [--force]" >&2; exit 1; }
valid_id "$c" || { echo "contest inválido" >&2; exit 1; }
if sess_seed_index "$c" "${2:-}"; then
  n="$(ls "$(_sidx_dir "$c")" 2>/dev/null | grep -vc '^\.' )"
  echo "índice de $c semeado: ${n:-0} login(s) em $(_sidx_dir "$c")"
else
  echo "não semeou (outro processo semeando? veja $(_sidx_dir "$c")/.seed.lock)" >&2; exit 1
fi
