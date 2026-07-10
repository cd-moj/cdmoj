#!/bin/bash
# backfill-public-at.sh — semeia contests/treino/var/public-at-seed.json = {id: epoch} com uma data
# APROXIMADA de "entrada" p/ os problemas PÚBLICOS que ainda NÃO têm public_at no .moj-meta.json.
# Fonte por problema: .moj-meta.json .migrated_at, senão o 1º commit (git --diff-filter=A --reverse)
# do subdir do pacote. Idempotente (re-rodar re-semeia). NÃO commita no repo do problema — o dado é aproximado
# (a migração de jun/jul-2026 concentra ~86% das datas num pico artificial) e mora só no seed lateral,
# que o mojtools/gen-problem-owners.sh usa como fallback de public_at (o meta, quando existe, ganha).
#   uso: MOJ_PROBLEMS_DIR=… CONTESTSDIR=… bash backfill-public-at.sh
set -u
: "${MOJ_PROBLEMS_DIR:=/home/ribas/moj/moj-problems}"
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
IDX="$CONTESTSDIR/treino/var/problem-owners.json"
OUT="$CONTESTSDIR/treino/var/public-at-seed.json"
[[ -f "$IDX" ]] || { echo "índice inexistente: $IDX" >&2; exit 1; }

set +o noglob
tmp="$(mktemp)"; n=0
# só problemas PÚBLICOS (o heatmap é de ENTRADA de públicos)
while IFS=$'\t' read -r id repo prob; do
  [[ -n "$id" && -n "$repo" && -n "$prob" ]] || continue
  pdir="$MOJ_PROBLEMS_DIR/$repo/$prob"; [[ -d "$pdir" ]] || continue
  meta="$pdir/.moj-meta.json"; pat=""
  # já tem public_at no meta (autoritativo)? o gerador o usa direto -> seed dispensável.
  [[ -f "$meta" ]] && { pat="$(jq -r '.public_at // empty' "$meta" 2>/dev/null)"; [[ -n "$pat" ]] && continue; }
  # senão: migrated_at do meta, senão 1º commit que ADICIONOU arquivos do subdir.
  [[ -f "$meta" ]] && pat="$(jq -r '.migrated_at // empty' "$meta" 2>/dev/null)"
  [[ -n "$pat" ]] || pat="$(git -C "$MOJ_PROBLEMS_DIR/$repo" log --diff-filter=A --reverse --format=%at -- "$prob/" 2>/dev/null | head -1)"
  pat="${pat//[^0-9]/}"; [[ -n "$pat" ]] || continue
  printf '%s\t%s\n' "$id" "$pat" >> "$tmp"; n=$((n+1))
done < <(jq -r '.problems[] | select(.public) | "\(.id)\t\(.repo)\t\(.prob)"' "$IDX" 2>/dev/null)

jq -Rn '[inputs|split("\t")|{key:.[0], value:(.[1]|tonumber)}]|from_entries' "$tmp" > "$OUT.tmp.$$" \
  && mv -f "$OUT.tmp.$$" "$OUT" || { echo "falha ao gravar $OUT" >&2; rm -f "$tmp" "$OUT.tmp.$$"; exit 1; }
rm -f "$tmp"
echo "public-at-seed: $n problemas -> $OUT"
