#!/usr/bin/env bash
# mojlog-prune.sh [--ended-days N] [--contest <c>] [--apply]
#
# POLÍTICA DE RETENÇÃO dos reports de julgamento (users/<login>/mojlog/*, e rounds/<slug>/users/…)
# em contests ENCERRADOS: apaga só o report HTML — veredicto (history), results/<id>.json e a
# FONTE da submissão ficam; a web passa a dizer "report removido pela política de retenção".
# Contest sem CONTEST_END numérico (o treino usa "$(date …)") NUNCA é tocado; .trash é pulado.
#
# DRY-RUN por padrão. --apply apaga e registra uma linha em <contest>/var/admin-audit.log.
# DESTRUTIVO: rode com OK explícito e por contest (--contest) quando for evento grande.
set -uo pipefail
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
APPLY=0; ONLY=""; DAYS=180
while [[ $# -gt 0 ]]; do case "$1" in
  --apply) APPLY=1;; --contest) ONLY="${2:-}"; shift;; --ended-days) DAYS="${2:-180}"; shift;;
  *) echo "uso: mojlog-prune.sh [--ended-days N] [--contest <c>] [--apply]" >&2; exit 2;; esac; shift; done
[[ "$DAYS" =~ ^[0-9]+$ ]] || { echo "--ended-days espera um inteiro" >&2; exit 2; }
say(){ printf '%s\n' "$*" >&2; }
now="$EPOCHSECONDS"; cutoff=$(( now - DAYS*86400 ))
mode="DRY-RUN"; (( APPLY )) && mode="APPLY"
say "== mojlog-prune ($mode) contests encerrados há mais de $DAYS dia(s)$( [[ -n "$ONLY" ]] && echo ", só $ONLY") =="
tot=0; ntot=0
for cdir in "$CONTESTSDIR"/*/; do
  c="${cdir%/}"; c="${c##*/}"
  [[ -n "$ONLY" && "$c" != "$ONLY" ]] && continue
  [[ -f "$cdir/conf" ]] || continue
  end="$(sed -n 's/^CONTEST_END=//p' "$cdir/conf" | head -1 | tr -d '"'"'"'')"
  [[ "$end" =~ ^[0-9]+$ ]] || continue                    # treino e afins: nunca
  (( end < cutoff )) || continue
  mapfile -t files < <(find "$cdir/users" "$cdir"/rounds/*/users -path '*/mojlog/*' -type f 2>/dev/null)
  (( ${#files[@]} )) || continue
  sz=0; for f in "${files[@]}"; do s=$(stat -c%s "$f" 2>/dev/null || echo 0); sz=$((sz+s)); done
  say "  $c (fim $(date -d "@$end" +%F)): ${#files[@]} report(s), $((sz/1048576)) MB"
  tot=$((tot+sz)); ntot=$((ntot+${#files[@]}))
  if (( APPLY )); then
    printf '%s\0' "${files[@]}" | xargs -0 rm -f --
    mkdir -p "$cdir/var"; printf '%s\t%s\tmojlog-prune\tremovidos=%s bytes=%s ended_days=%s\n' "$now" "$(id -un)" "${#files[@]}" "$sz" "$DAYS" >> "$cdir/var/admin-audit.log"
  fi
done
say ">> $ntot report(s), $((tot/1048576)) MB$( (( APPLY )) && echo " removidos" || echo " (use --apply para remover)")"
