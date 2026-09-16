#!/usr/bin/env bash
# mojlog-compress.sh [--contest <c> | --all] [--apply]
#
# Comprime em repouso os reports de julgamento já gravados (users/<login>/mojlog/<id>.html →
# <id>.html.gz), inclusive nas rodadas arquivadas (rounds/<slug>/users/…). Desde 2026-09-16 o
# judged grava direto em .gz e todo leitor aceita os dois formatos, então isto é LOSSLESS e pode
# rodar a qualquer hora (nice/ionice). Em produção eram 54 GB de .html (≈29 % depois do gzip).
#
# DRY-RUN por padrão (só mede); --apply comprime. Atômico por arquivo: gzip grava <f>.gz.tmp e
# renomeia; o .html só sai depois do .gz pronto. Arquivo com .gz já existente é pulado.
set -uo pipefail
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
APPLY=0; ONLY=""; ALL=0
while [[ $# -gt 0 ]]; do case "$1" in
  --apply) APPLY=1;; --contest) ONLY="${2:-}"; shift;; --all) ALL=1;;
  *) echo "uso: mojlog-compress.sh [--contest <c>|--all] [--apply]" >&2; exit 2;; esac; shift; done
[[ -n "$ONLY" || "$ALL" == 1 ]] || { echo "informe --contest <c> ou --all" >&2; exit 2; }
say(){ printf '%s\n' "$*" >&2; }
mode="DRY-RUN"; (( APPLY )) && mode="APPLY"
say "== mojlog-compress ($mode) =="
tot=0; ntot=0; saved=0
for cdir in "$CONTESTSDIR"/*/; do
  c="${cdir%/}"; c="${c##*/}"
  [[ -n "$ONLY" && "$c" != "$ONLY" ]] && continue
  [[ -f "$cdir/conf" ]] || continue
  mapfile -t files < <(find "$cdir/users" "$cdir"/rounds/*/users -path '*/mojlog/*.html' -type f 2>/dev/null)
  (( ${#files[@]} )) || continue
  sz=0; for f in "${files[@]}"; do s=$(stat -c%s "$f" 2>/dev/null || echo 0); sz=$((sz+s)); done
  say "  $c: ${#files[@]} arquivo(s), $((sz/1048576)) MB"
  tot=$((tot+sz)); ntot=$((ntot+${#files[@]}))
  (( APPLY )) || continue
  for f in "${files[@]}"; do
    [[ -e "$f.gz" ]] && continue
    if nice -n 10 ionice -c3 gzip -6 -c "$f" > "$f.gz.tmp" 2>/dev/null && [[ -s "$f.gz.tmp" ]]; then
      mv -f "$f.gz.tmp" "$f.gz" && { g=$(stat -c%s "$f.gz"); s=$(stat -c%s "$f"); saved=$((saved+s-g)); rm -f "$f"; }
    else rm -f "$f.gz.tmp"; fi
  done
done
say ">> $ntot arquivo(s), $((tot/1048576)) MB em .html$( (( APPLY )) && echo "; liberados $((saved/1048576)) MB" || echo " (use --apply para comprimir)")"
