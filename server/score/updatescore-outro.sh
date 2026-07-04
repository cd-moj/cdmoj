#!/usr/bin/env bash
#
# updatescore-outro.sh <contest>
#
# Escape hatch for fully custom boards. Prints ONE TXT to stdout whose first
# line is the bare mode "outro".
#
#   - If contests/<id>/var/placar-custom.txt exists, it is emitted as the
#     board (it already carries the "outro" mode line + arbitrary columns). If,
#     for whatever reason, its first line is not "outro", an "outro" line is
#     prepended so the dispatcher's contract still holds.
#   - Otherwise a minimal valid board is emitted (just the mode + a header).
#
# The custom 2nd line is free-form columns; if it contains a "flag" column the
# renderer shows a flag (see score-icpc.js parseOutroScore).
set -u
SC_PROG="updatescore-outro"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/score-common.sh"

sc_load "${1:-}"

CUSTOM="$CONTESTDIR/var/placar-custom.txt"

if [[ -f "$CUSTOM" ]]; then
  first="$(head -1 "$CUSTOM")"
  if [[ "$first" == "outro" ]]; then
    cat "$CUSTOM"
  else
    printf 'outro\n'
    cat "$CUSTOM"
  fi
else
  # minimal valid custom board
  printf 'outro\n'
  printf 'asc:username:team name:Total\n'
fi
