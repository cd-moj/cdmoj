#!/bin/bash
# contest-backup.sh <contest> [--dest DIR] [--keep N]
#
# SNAPSHOT rotacionado de um contest durante a prova (plano de desastre — em LAN isolada
# é a única cópia além do disco do host): tar.gz de contests/<c>/ inteiro (conf, users/
# com history+submissões+metrics, var/, review/, print-requests/, time-overrides) + o
# spool PENDENTE (run/spool/submissions — submissões ainda não julgadas não se perdem).
# A escrita do MOJ é atômica (mv), então o tar de um contest vivo é consistente o
# suficiente p/ restore; roda em segundos p/ contests de prova.
#
#   --dest DIR   destino (default $MOJ_BACKUP_DEST ou /var/backups/moj) — ideal: outro
#                disco/máquina (NFS/rsync do destino fica a cargo do deploy)
#   --keep N     mantém os N snapshots mais recentes do contest (default 48)
#
# Agendar: systemd `moj-contest-backup@<contest>.timer` (a cada 5 min — ver etc/systemd/).
# Restore: parar moj-judged, extrair o tar em contests/ (e spool/ se quiser), religar.
set -euo pipefail
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
: "${RUNDIR:=/home/ribas/moj/run}"
: "${MOJ_BACKUP_DEST:=/var/backups/moj}"

CONTEST=""; DEST="$MOJ_BACKUP_DEST"; KEEP=48
while [[ $# -gt 0 ]]; do case "$1" in
  --dest) DEST="${2:?--dest precisa de diretório}"; shift 2;;
  --keep) KEEP="${2:?--keep precisa de N}"; shift 2;;
  -h|--help) sed -n '2,18p' "$0"; exit 0;;
  *) CONTEST="$1"; shift;;
esac; done
[[ -n "$CONTEST" && -d "$CONTESTSDIR/$CONTEST" ]] \
  || { echo "contest-backup: contest inexistente: '$CONTEST' (em $CONTESTSDIR)" >&2; exit 2; }
[[ "$KEEP" =~ ^[0-9]+$ && "$KEEP" -ge 1 ]] || { echo "contest-backup: --keep inválido" >&2; exit 2; }

mkdir -p "$DEST"
stamp="$(date +%Y%m%d-%H%M%S)"
out="$DEST/$CONTEST-$stamp.tar.gz"
tmp="$out.tmp"

# spool pendente só se existir (contest recém-criado pode não ter nada na fila)
spool_args=()
[[ -d "$RUNDIR/spool/submissions" ]] && spool_args=(-C "$RUNDIR" spool/submissions)

# --warning=no-file-changed: history pode ganhar linha durante o tar (escrita atômica por
# mv — o snapshot fica íntegro; o aviso viraria exit 1 à toa com set -e)
tar czf "$tmp" --warning=no-file-changed \
  -C "$CONTESTSDIR" "$CONTEST" "${spool_args[@]}" || [[ $? -eq 1 ]]
mv -f "$tmp" "$out"

# rotação: mantém os $KEEP mais recentes deste contest
find "$DEST" -maxdepth 1 -name "$CONTEST-*.tar.gz" -printf '%T@ %p\n' 2>/dev/null \
  | sort -rn | awk -v k="$KEEP" 'NR>k {sub(/^[^ ]+ /,""); print}' \
  | xargs -r rm -f --

echo "contest-backup: $out ($(du -h "$out" | cut -f1)) — $(find "$DEST" -maxdepth 1 -name "$CONTEST-*.tar.gz" | wc -l | tr -d ' ') snapshot(s) mantidos"
