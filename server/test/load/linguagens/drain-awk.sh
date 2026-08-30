#!/bin/bash
# drain-awk.sh [awk-bin] — orquestra o ingest.awk: find alimenta, xargs mv consome.
# Total de processos: find(1) + awk(1) + xargs/mv(1-2) — o resto é o awk sozinho.
set -u
AWK="${1:-gawk}"
S="$(dirname "$0")"
export NOW_EPOCH=$EPOCHSECONDS
find "$RUNDIR/spool/submissions" -maxdepth 1 -type f -name '*:result:*' \
  | "$AWK" -f "$S/ingest.awk" \
  | xargs -r mv -t "$RUNDIR/spool/submissions-done"
