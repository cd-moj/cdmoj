#!/usr/bin/env bash
#
# score-common.sh — tiny shared helpers for the updatescore-<mode>.sh family.
#
# Sourced (not executed) by each generator. Keeps the per-mode scripts small
# without duplicating the conf/PROBS parsing. No mode-specific logic lives here.
#
# After `sc_load <contest>` the following are set:
#
#   CONTESTSDIR        base dir (env override honoured)
#   CONTEST            the contest id
#   CONTESTDIR         $CONTESTSDIR/$CONTEST
#   CONTEST_START      epoch (0 if unset in conf)
#   PROBS              the flat 5-tuple array from the conf
#   SC_PIDX[]          flat-array start index of each problem (== numeric probid
#                      used in data/<user>, controle/history and the .d files)
#   SC_SHORT[]         short name of each problem (PROBS[idx+3])
#   SC_FULL[]          full name of each problem (PROBS[idx+2])
#   SC_CANON[]         canonical 'collection#problem' id of each problem (the form
#                      the async pipeline writes to history/data; '#' = treino parity)
#   SC_NPROB           number of problems
#
# The numeric probid is the index where a 5-tuple starts in PROBS, i.e. the
# judge dispatcher does SITE=${PROBS[PROBID]} / IDSITE=${PROBS[PROBID+1]}.

: "${CONTESTSDIR:=/home/ribas/moj/contests}"

sc_die() { echo "${SC_PROG:-updatescore}: $*" >&2; exit 1; }

sc_valid_id() {
  case "$1" in
    *[!A-Za-z0-9._-]* | "" | .* ) return 1 ;;
    *) return 0 ;;
  esac
}

sc_load() {
  CONTEST="${1:-}"
  [[ -n "$CONTEST" ]] || sc_die "usage: ${SC_PROG:-updatescore} <contest>"
  sc_valid_id "$CONTEST" || sc_die "invalid contest id: '$CONTEST'"

  CONTESTDIR="$CONTESTSDIR/$CONTEST"
  [[ -f "$CONTESTDIR/conf" ]] || sc_die "no conf for '$CONTEST'"

  # defaults so the conf doesn't have to define everything
  CONTEST_START=0
  PROBS=()
  # shellcheck disable=SC1090
  source "$CONTESTDIR/conf" || sc_die "could not source conf"
  : "${CONTEST_START:=0}"

  SC_PIDX=(); SC_SHORT=(); SC_FULL=(); SC_CANON=()
  local i n=${#PROBS[@]} canon
  for ((i=0; i<n; i+=5)); do
    SC_PIDX+=("$i")
    SC_FULL+=("${PROBS[i+2]:-}")
    SC_SHORT+=("${PROBS[i+3]:-$((i/5))}")
    # SC_CANON = id canônico 'coleção#problema' (forma que o pipeline novo grava no
    # history/data). O statement_key (PROBS[i+4]) já é '#' nos contests novos; em
    # contests legados é o nome simples, então convertemos a barra do problem_id.
    canon="${PROBS[i+4]:-}"
    [[ "$canon" == *"#"* ]] || canon="${PROBS[i+1]//\//#}"
    SC_CANON+=("$canon")
  done
  SC_NPROB=${#SC_PIDX[@]}
}

# sc_is_real_user <login>  -> 0 if it's a contestant row we should score.
# Skips passwd comments, admin/judge/staff/mon roles and the literal "admin".
sc_is_real_user() {
  local u="$1"
  [[ -z "$u" ]] && return 1
  [[ "$u" == \#* ]] && return 1
  case "$u" in
    *.admin|*.judge|*.cjudge|*.staff|*.mon|admin) return 1 ;;
  esac
  return 0
}

# sc_users  -> prints, one per line: "login<TAB>fullname<TAB>team<TAB>univshort<TAB>univfull<TAB>flag"
#
# Source order:
#   1. controle/teams  (optional), lines: login:flag:univ short:team name:univ full
#   2. passwd extra fields after fullname:  login:pass:fullname:email:flag:univshort:team:univfull
#      (only used when controle/teams has no entry)
# Missing optional fields are left empty. Only "real" users are emitted.
sc_users() {
  local teamsfile="$CONTESTDIR/controle/teams"
  declare -A TF_FLAG TF_US TF_TN TF_UF TF_HAS
  if [[ -f "$teamsfile" ]]; then
    local L lu lflag lus ltn luf
    while IFS=: read -r lu lflag lus ltn luf _; do
      [[ -z "$lu" || "$lu" == \#* ]] && continue
      TF_HAS["$lu"]=1
      TF_FLAG["$lu"]="$lflag"; TF_US["$lu"]="$lus"
      TF_TN["$lu"]="$ltn";     TF_UF["$lu"]="$luf"
    done < "$teamsfile"
  fi

  local login pass full email f5 f6 f7 f8
  while IFS=: read -r login pass full email f5 f6 f7 f8; do
    sc_is_real_user "$login" || continue
    local flag="" us="" tn="" uf=""
    if [[ -n "${TF_HAS[$login]:-}" ]]; then
      flag="${TF_FLAG[$login]}"; us="${TF_US[$login]}"
      tn="${TF_TN[$login]}";     uf="${TF_UF[$login]}"
    else
      # optional passwd extras: flag, univ short, team name, univ full
      flag="$f5"; us="$f6"; tn="$f7"; uf="$f8"
    fi
    [[ -z "$tn" ]] && tn="$full"
    # strip any stray ':' that would break the field layout
    full="${full//:/ }"; tn="${tn//:/ }"; us="${us//:/ }"; uf="${uf//:/ }"; flag="${flag//:/}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$login" "$full" "$tn" "$us" "$uf" "$flag"
  done < "$CONTESTDIR/passwd"
}
