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
#   SC_PIDX[]          flat-array start index of each problem
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

  # MOJ_PRESTART=1 — quadro PRÉ-INÍCIO: o placar nunca revela a quantidade de problemas
  # antes de a competição começar. Zerar as tuplas aqui faz TODOS os geradores saírem sem
  # coluna de problema (vitrine de times: bandeira/sigla/nome, totais 0), sem tocar em cada um.
  if [[ "${MOJ_PRESTART:-}" == 1 ]]; then
    SC_PIDX=(); SC_SHORT=(); SC_FULL=(); SC_CANON=(); SC_NPROB=0
  fi
}

# sc_cells — emits one TSV row per (user, problem) from users/*/metrics.json in a
# single pass (find|xargs jq, login from input_filename — no ARG_MAX, no per-user fork).
# Columns:
#   login  probid  solved(0|1)  first_ac_epoch  counted  pending(0|1)  best_score(-|N)  heur_score(-|N)  heur_adj(F)
# View: MOJ_NOFREEZE=1 (or metrics without .frozen) = full; otherwise the frozen one.
# This is the ONLY scoreboard data source (replaces the old .d state files and data/).
sc_cells() {
  local d="$CONTESTDIR/users"
  [[ -d "$d" ]] || return 0
  find "$d" -mindepth 2 -maxdepth 2 -name metrics.json -print0 2>/dev/null \
  | xargs -0 -r jq -r --arg nofreeze "${MOJ_NOFREEZE:-0}" '
      (input_filename | split("/") | .[-2]) as $login
      | (.by_problem // {}) | to_entries[]
      | (if ($nofreeze == "1") or (.value.frozen == null) then .value
         else (.value + .value.frozen) end) as $v
      | [$login, .key,
         (if $v.solved then 1 else 0 end),
         ($v.first_ac_epoch // 0),
         ($v.counted // 0),
         (if $v.pending then 1 else 0 end),
         ($v.best_score // "-"),
         ($v.heur.score // "-"),
         ($v.heur.adjusted // 0)]
      | @tsv'
}

# sc_is_real_user <login>  -> 0 if it's a contestant row we should score.
# Skips passwd comments, admin/judge/staff/cstaff/mon roles and the literal "admin".
sc_is_real_user() {
  local u="$1"
  [[ -z "$u" ]] && return 1
  [[ "$u" == \#* ]] && return 1
  case "$u" in
    *.admin|*.judge|*.cjudge|*.staff|*.cstaff|*.mon|*.animeitor|admin) return 1 ;;
  esac
  return 0
}

# sc_users  -> uma linha por time, campos separados por \x01 (SOH):
#   login \x01 fullname \x01 team \x01 univ_short \x01 univ_full \x01 flag \x01 cohort
#
# POR QUE \x01 E NÃO TAB: `IFS=$'\t' read -r a b c …` COLAPSA runs de tab (tab é IFS
# whitespace), então um campo vazio no meio DESLOCA todos os seguintes — um time com bandeira
# mas sem `univ_full` tinha a bandeira lida como univ_full (bug silencioso que existia antes da
# coorte e que a 7ª coluna escancarou). Separador não-whitespace preserva campo vazio.
#
# Source: users/*/account.json (batch find|xargs jq — no ARG_MAX, no per-user fork).
# Team metadata lives in account.json .team {name, univ_short, univ_full, flag} (optional;
# falls back to fullname). USERS_FROM: shared participants have a LOCAL user dir (history,
# created on first submit) without a local account.json — their identity comes from the
# source contest's account.json. Only "real" users are emitted (sc_is_real_user).
# Saída TSV: login, fullname, team, univ_short, univ_full, flag, **cohort** (7 campos).
sc_users() {
  local d="$CONTESTDIR/users"
  [[ -d "$d" ]] || return 0
  # USERS_FROM (lido por sed — o conf roda command substitution, nunca source aqui)
  local src srcdir=""
  src="$(sed -n 's/^[[:space:]]*USERS_FROM=//p' "$CONTESTDIR/conf" 2>/dev/null | tail -1)"
  src="${src//\'/}"; src="${src//\"/}"
  [[ -n "$src" ]] && sc_valid_id "$src" && [[ -d "$CONTESTSDIR/$src/users" ]] \
    && srcdir="$CONTESTSDIR/$src/users"

  # COORTE (times oficiais × convidados): o 7º campo. `.team.cohort` vence; senão a 1ª coorte
  # cujo regex casa o login; senão a default. Resolvido AQUI, no mesmo jq que já lê cada
  # account.json — nada de fork por usuário. `.regex` bindado antes do test (armadilha de
  # contexto de args do jq). MOJ_COHORTS="id id" filtra a saída; vazio = todas (comportamento
  # de sempre). É deste funil que saem o rank (ordem das linhas) e a ESTRELA de first-to-solve,
  # e é por isso que o corte por coorte tem de ser aqui e não no TXT pronto.
  local CH_JSON='{"cohorts":[]}'
  if [[ -s "$CONTESTDIR/cohorts.json" ]]; then
    CH_JSON="$(jq -c '{cohorts:[ (.cohorts // [])[] | {id:(.id//""), regex:(.regex//""),
                       default:(.default == true)} | select(.id != "") ]}' \
                 "$CONTESTDIR/cohorts.json" 2>/dev/null)" || CH_JSON='{"cohorts":[]}'
    [[ -n "$CH_JSON" ]] || CH_JSON='{"cohorts":[]}'
  fi
  local ACCT_JQ='(.login // "") as $l
    | [$l, .fullname//"", (.team.name // .fullname // ""),
       (.team.univ_short//""), (.team.univ_full//""), (.team.flag//""),
       ((.team.cohort // "") as $c
        | if $c != "" then $c
          else ((first($CH.cohorts[] | .regex as $rr
                       | select($rr != "" and (try ($l|test($rr;"i")) catch false)) | .id))
                // (first($CH.cohorts[] | select(.default) | .id)) // "") end)]
    | map(tostring | gsub("[\t\n\r]"; " ")) | join("\u0001")'
  {
    # contas locais em uma passada
    find "$d" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
      | xargs -0 -r jq -r --argjson CH "$CH_JSON" "$ACCT_JQ"
    # participantes compartilhados: dir local sem account.json -> identidade da fonte
    if [[ -n "$srcdir" ]]; then
      ( set +o noglob 2>/dev/null; shopt -s nullglob
        local ud login
        for ud in "$d"/*/; do
          login="${ud%/}"; login="${login##*/}"
          [[ -f "$ud/account.json" ]] && continue
          [[ -f "$srcdir/$login/account.json" ]] || continue
          jq -r --argjson CH "$CH_JSON" "$ACCT_JQ" "$srcdir/$login/account.json" 2>/dev/null
        done )
    fi
  } | {
    local login full tn us uf flag coh
    local want=" ${MOJ_COHORTS:-} "
    while IFS=$'\001' read -r login full tn us uf flag coh; do
      sc_is_real_user "$login" || continue
      # filtro de VISÃO: só as coortes pedidas (vazio = todas)
      if [[ -n "${MOJ_COHORTS:-}" ]]; then
        [[ "$want" == *" ${coh:-} "* ]] || continue
      fi
      [[ -z "$tn" ]] && tn="$full"
      # strip any stray ':' that would break the field layout
      full="${full//:/ }"; tn="${tn//:/ }"; us="${us//:/ }"; uf="${uf//:/ }"; flag="${flag//:/}"
      printf '%s\x01%s\x01%s\x01%s\x01%s\x01%s\x01%s\n' \
        "$login" "$full" "$tn" "$us" "$uf" "$flag" "${coh:-}"
    done
  }
}
