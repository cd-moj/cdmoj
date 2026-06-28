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

# --- generate the board(s) ------------------------------------------------
# placar.txt = público (com freeze). placar-full.txt = COMPLETO (sem freeze), servido
# aos privilegiados (.admin/.judge + allowlist do conf) — só gerado quando há FREEZE_TIME.
OUT="$CONTESTDIR/controle/placar.txt"
FULL="$CONTESTDIR/controle/placar-full.txt"
mkdir -p "$CONTESTDIR/controle" || die "cannot create controle dir"

# FREEZE_TIME do conf (sem sourcear arrays): se >0, também geramos o placar completo.
FREEZE_RAW="$(sed -n 's/^[[:space:]]*FREEZE_TIME=//p' "$CONF" | tail -1)"
FREEZE_RAW="$(printf '%s' "$FREEZE_RAW" | tr -cd '0-9')"

# gen_one <outfile> <nofreeze:0|1> — materializa os .d (contests novos; MOJ_NOFREEZE
# controla o freeze) e roda o gerador, instalando atômico com checagem do modo.
gen_one() {
  local out="$1" nofreeze="$2" tmp first
  if [[ -f "$CONTESTDIR/created-by" ]]; then
    MOJ_NOFREEZE="$nofreeze" bash "$HERE/dstate.sh" "$CONTEST" 2>/dev/null || true
  fi
  tmp="$(mktemp "$out.XXXXXX")" || die "cannot create temp file next to $out"
  if ! MOJ_NOFREEZE="$nofreeze" bash "$GEN" "$CONTEST" > "$tmp"; then rm -f "$tmp"; die "generator failed: $GEN $CONTEST"; fi
  first="$(head -1 "$tmp")"
  [[ "$first" == "$MODE" ]] || { rm -f "$tmp"; die "generator '$GEN' line 1 was '$first', expected '$MODE'"; }
  mv "$tmp" "$out" || { rm -f "$tmp"; die "cannot install board to $out"; }
}

if [[ -n "$FREEZE_RAW" ]] && (( FREEZE_RAW > 0 )); then
  gen_one "$FULL" 1     # completo (sem freeze) — gera primeiro
  gen_one "$OUT"  0     # público (com freeze) — os .d terminam congelados
else
  rm -f "$FULL" 2>/dev/null   # sem freeze: completo == público
  gen_one "$OUT" 0
fi

echo "$OUT"
