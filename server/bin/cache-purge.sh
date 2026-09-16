#!/usr/bin/env bash
# cache-purge.sh [--apply] [--pdf-days N] [--trash-days N]
#
# Caches e restos de CUSTO ZERO para apagar:
#   • print-requests/*.combined.pdf (e rounds/*/print-requests) de contests encerrados há > N dias
#     (default 7): pr_build_pdf/pr_build_balloon reconstroem do .src/.json na próxima impressão;
#   • contests/.trash/<id>-<epoch> com mais de N dias (default 60) — contests removidos pela interface;
#   • tmp órfãos var/problems-cache.*.tmp.* (bug antigo do ${BASHPID} no redirect).
# DRY-RUN por padrão; --apply remove. Nunca toca em .src/.json da fila nem em contest vivo.
set -uo pipefail
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
APPLY=0; PDF_DAYS=7; TRASH_DAYS=60
while [[ $# -gt 0 ]]; do case "$1" in
  --apply) APPLY=1;; --pdf-days) PDF_DAYS="${2:-7}"; shift;; --trash-days) TRASH_DAYS="${2:-60}"; shift;;
  *) echo "uso: cache-purge.sh [--apply] [--pdf-days N] [--trash-days N]" >&2; exit 2;; esac; shift; done
say(){ printf '%s\n' "$*" >&2; }
now="$EPOCHSECONDS"; mode="DRY-RUN"; (( APPLY )) && mode="APPLY"
say "== cache-purge ($mode) =="
tot=0
rmlist(){ # <rótulo> (lê caminhos NUL-separados no stdin)
  local label="$1" n=0 sz=0 f s
  while IFS= read -r -d '' f; do s=$(stat -c%s "$f" 2>/dev/null || echo 0); sz=$((sz+s)); n=$((n+1)); (( APPLY )) && rm -rf -- "$f"; done
  (( n )) && say "  $label: $n item(ns), $((sz/1048576)) MB"; tot=$((tot+sz)); return 0; }
for cdir in "$CONTESTSDIR"/*/; do
  c="${cdir%/}"; c="${c##*/}"; [[ -f "$cdir/conf" ]] || continue
  end="$(sed -n 's/^CONTEST_END=//p' "$cdir/conf" | head -1 | tr -d '"'"'"'')"
  [[ "$end" =~ ^[0-9]+$ ]] && (( end < now - PDF_DAYS*86400 )) || continue
  find "$cdir/print-requests" "$cdir"/rounds/*/print-requests -maxdepth 1 -name '*.combined.pdf' -type f -print0 2>/dev/null | rmlist "$c: PDFs de impressão"
done
find "$CONTESTSDIR/.trash" -mindepth 1 -maxdepth 1 -mtime "+$TRASH_DAYS" -print0 2>/dev/null | rmlist ".trash (> $TRASH_DAYS d)"
find "$CONTESTSDIR" -path '*/var/problems-cache.*.tmp.*' -type f -print0 2>/dev/null | rmlist "tmp órfãos do cache de problems"
say ">> total: $((tot/1048576)) MB$( (( APPLY )) && echo " removidos" || echo " (use --apply)")"
