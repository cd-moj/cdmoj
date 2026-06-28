#!/usr/bin/env bash
#
# build.sh <contest>
#
# Dispatcher for the MOJ multi-mode scoreboard generators.
#
#   "add a scoreboard mode = add one updatescore-<mode>.sh"
#
# Reads the contest conf, decides the scoreboard MODE from CONTEST_TYPE,
# calls the matching updatescore-<mode>.sh <contest> (which prints ONE TXT
# whose first line is the bare mode), and installs the result atomically as
#
#   contests/<contest>/controle/placar.txt
#
# Prints the path of the generated board.
#
# Env:
#   CONTESTSDIR   base dir of contests (default: /home/ribas/moj/contests)
#   CONTEST_TYPE  may be exported to override the conf value (used for testing)
#
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- base dir of contests (env override allowed) --------------------------
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
export CONTESTSDIR

die() { echo "build.sh: $*" >&2; exit 1; }

CONTEST="${1:-}"
[[ -n "$CONTEST" ]] || die "usage: build.sh <contest>"

# --- validate contest id (no path traversal before sourcing conf) ---------
case "$CONTEST" in
  *[!A-Za-z0-9._-]* | "" | .* ) die "invalid contest id: '$CONTEST'" ;;
esac

CONTESTDIR="$CONTESTSDIR/$CONTEST"
CONF="$CONTESTDIR/conf"
[[ -f "$CONF" ]] || die "no conf for contest '$CONTEST' ($CONF)"

# --- read CONTEST_TYPE ----------------------------------------------------
# An exported CONTEST_TYPE (e.g. from the environment, for testing) wins over
# the conf; otherwise read it straight from the conf without sourcing the
# whole file (the conf also runs arbitrary array assignments).
if [[ -n "${CONTEST_TYPE:-}" ]]; then
  RAW_TYPE="$CONTEST_TYPE"
else
  RAW_TYPE="$(sed -n 's/^[[:space:]]*CONTEST_TYPE=//p; s/^[[:space:]]*SCORE_MODE=//p' "$CONF" | tail -1)"
fi
# strip surrounding quotes / whitespace, lowercase
RAW_TYPE="${RAW_TYPE%\"}"; RAW_TYPE="${RAW_TYPE#\"}"
RAW_TYPE="${RAW_TYPE%\'}"; RAW_TYPE="${RAW_TYPE#\'}"
RAW_TYPE="$(printf '%s' "$RAW_TYPE" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"

# --- map CONTEST_TYPE -> scoreboard MODE ----------------------------------
# Adding a mode = add an updatescore-<mode>.sh and (optionally) a case here.
case "$RAW_TYPE" in
  icpc)                         MODE=icpc ;;
  obi)                          MODE=obi ;;
  heuristic|flia)               MODE=heuristic ;;
  treino|lista-publica|lista-privada|lista|"") MODE=treino ;;
  outro|custom)                 MODE=outro ;;
  *)
    # treino is what an unrecognised value falls back to only when the field
    # is missing; per the plan a *missing* type means a classic ICPC contest.
    if [[ -z "$RAW_TYPE" ]]; then MODE=icpc; else MODE=icpc; fi
    ;;
esac
# NOTE: per the plan, a *missing* CONTEST_TYPE means a legacy ICPC contest.
[[ -z "$RAW_TYPE" ]] && MODE=icpc

GEN="$HERE/updatescore-$MODE.sh"
[[ -f "$GEN" ]] || die "no generator for mode '$MODE' ($GEN)"

# --- generate the board ---------------------------------------------------
OUT="$CONTESTDIR/controle/placar.txt"
mkdir -p "$CONTESTDIR/controle" || die "cannot create controle dir"

# Pipeline novo (contests criados pela interface têm o marcador created-by): nada no
# fluxo assíncrono escreve os controle/<login>.d/<pidx> que os geradores icpc/treino
# leem, então materializamos a partir do history. Contests legados (sem created-by)
# mantêm os .d escritos pelo juiz antigo — não tocamos neles.
if [[ -f "$CONTESTDIR/created-by" ]]; then
  bash "$HERE/dstate.sh" "$CONTEST" 2>/dev/null || true
fi

TMP="$(mktemp "$OUT.XXXXXX")" || die "cannot create temp file next to $OUT"
trap 'rm -f "$TMP"' EXIT

if ! bash "$GEN" "$CONTEST" > "$TMP"; then
  die "generator failed: $GEN $CONTEST"
fi

# sanity: first line must be the bare mode
FIRST="$(head -1 "$TMP")"
[[ "$FIRST" == "$MODE" ]] || die "generator '$GEN' first line was '$FIRST', expected '$MODE'"

# atomic install
mv "$TMP" "$OUT" || die "cannot install board to $OUT"
trap - EXIT

echo "$OUT"
