#!/usr/bin/env bash
# mojlog-compress.sh [--contest <c> | --all] [--apply] [--jobs N]
#
# Comprime em repouso os reports de julgamento já gravados (users/<login>/mojlog/<id>.html →
# <id>.html.gz), inclusive nas rodadas arquivadas (rounds/<slug>/users/…). Desde 2026-09-16 o
# judged grava direto em .gz e todo leitor aceita os dois formatos, então isto é LOSSLESS e pode
# rodar a qualquer hora (nice/ionice). Em produção eram 54 GB de .html (≈29 % depois do gzip).
#
# DRY-RUN por padrão (só mede); --apply comprime; --jobs N roda N gzip em paralelo (máquina ociosa). Atômico por arquivo: gzip grava <f>.gz.tmp e
# renomeia; o .html só sai depois do .gz pronto. Arquivo com .gz já existente é pulado.
set -uo pipefail
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
APPLY=0; ONLY=""; ALL=0; JOBS=1
while [[ $# -gt 0 ]]; do case "$1" in
  --apply) APPLY=1;; --contest) ONLY="${2:-}"; shift;; --all) ALL=1;; --jobs|-j) JOBS="${2:-1}"; shift;;
  *) echo "uso: mojlog-compress.sh [--contest <c>|--all] [--apply] [--jobs N]" >&2; exit 2;; esac; shift; done
[[ -n "$ONLY" || "$ALL" == 1 ]] || { echo "informe --contest <c> ou --all" >&2; exit 2; }
[[ "$JOBS" =~ ^[0-9]+$ && "$JOBS" -ge 1 ]] || { echo "--jobs espera um inteiro ≥ 1" >&2; exit 2; }
say(){ printf '%s\n' "$*" >&2; }
mode="DRY-RUN"; (( APPLY )) && mode="APPLY"
say "== mojlog-compress ($mode, jobs=$JOBS) =="
# resto de uma rodada interrompida no meio de um gzip
(( APPLY )) && find "$CONTESTSDIR" -path '*/mojlog/*.html.gz.tmp' -type f -delete 2>/dev/null
# um arquivo: gzip -c > tmp, mv, rm do .html; imprime os bytes economizados (o pai soma).
# ionice best-effort baixo (-c2 -n7), NÃO idle (-c3): com a API lendo disco o tempo todo a classe
# idle nunca era servida — 8 arquivos em 10 min (16/09); gzip é CPU, o nice basta p/ não atrapalhar
_one(){ local f="$1" g s
  [[ -e "$f.gz" ]] && { echo 0; return 0; }
  if nice -n 10 ionice -c2 -n7 gzip -6 -c "$f" > "$f.gz.tmp" 2>/dev/null && [[ -s "$f.gz.tmp" ]]; then
    mv -f "$f.gz.tmp" "$f.gz" && { g=$(stat -c%s "$f.gz"); s=$(stat -c%s "$f"); rm -f "$f"; echo $((s-g)); return 0; }
  fi
  rm -f "$f.gz.tmp"; echo 0; }
export -f _one
tot=0; ntot=0; saved=0; t0="$EPOCHSECONDS"
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
  # N gzip em paralelo (xargs -P); cada worker ecoa os bytes economizados
  csaved=$(printf '%s\0' "${files[@]}" | xargs -0 -n1 -P "$JOBS" bash -c '_one "$1"' _ | awk '{s+=$1} END{print s+0}')
  saved=$((saved+csaved))
  say "     → $((csaved/1048576)) MB liberados ($(( EPOCHSECONDS - t0 ))s)"
done
say ">> $ntot arquivo(s), $((tot/1048576)) MB em .html$( (( APPLY )) && echo "; liberados $((saved/1048576)) MB em $(( EPOCHSECONDS - t0 ))s" || echo " (use --apply para comprimir)")"
