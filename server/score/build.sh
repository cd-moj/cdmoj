#!/usr/bin/env bash
#
# build.sh <contest> [--prestart]
#
# Dispatcher for the MOJ multi-mode scoreboard generators.
#
#   "add a scoreboard mode = add one updatescore-<mode>.sh"
#
# Reads the contest conf, decides the scoreboard MODE from CONTEST_TYPE,
# calls the matching updatescore-<mode>.sh <contest> (which prints ONE TXT
# whose first line is the bare mode), and installs the result atomically as
#
#   contests/<contest>/var/placar.txt
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
[[ -n "$CONTEST" ]] || die "usage: build.sh <contest> [--prestart]"
# --prestart: gera SÓ var/placar-prestart.txt — o quadro PRÉ-INÍCIO (vitrine de times, ZERO
# colunas de problema; a regra é que o placar nunca revela a quantidade de problemas antes de
# a competição começar). Servido por /contest/score quando contest_phase == before.
PRESTART=0
[[ "${2:-}" == --prestart ]] && PRESTART=1

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
OUT="$CONTESTDIR/var/placar.txt"
FULL="$CONTESTDIR/var/placar-full.txt"
mkdir -p "$CONTESTDIR/var" || die "cannot create var dir"

# FREEZE_TIME do conf (sem sourcear arrays): se >0, também geramos o placar completo.
FREEZE_RAW="$(sed -n 's/^[[:space:]]*FREEZE_TIME=//p' "$CONF" | tail -1)"
FREEZE_RAW="$(printf '%s' "$FREEZE_RAW" | tr -cd '0-9')"

# --- metrics freshness ------------------------------------------------------
# Os geradores leem users/*/metrics.json (mantidos incrementais pelo daemon). Se o CONF
# mudou depois do último recompute em massa (ex.: FREEZE_TIME editado — a visão frozen
# vive DENTRO do metrics), recomputa todo mundo uma vez e carimba var/.metrics-stamp.
# Também cobre o 1º build de um contest importado/backfill (stamp ausente).
#
# ⚠ E cobre o DEPLOY que muda o FORMATO do metrics: a `lib/users.sh` entra como entrada, do mesmo
# jeito que o `${BASH_SOURCE[0]}` entra na validade do cache de impressão. Sem isso, um campo novo
# só apareceria quando cada usuário recebesse um veredicto — e o consumidor, que não sabe
# distinguir "não há" de "ainda não calculado", degrada por segurança. Foi o caso do
# `pending_min_epoch` (25/08/2026): sem ele o placar segura a estrela de first-to-solve, e o
# deploy apagaria a estrela de todo mundo até o próximo veredicto de cada time.
source "$HERE/../api/v1/lib/users.sh"
STAMP="$CONTESTDIR/var/.metrics-stamp"
_ULIB="$HERE/../api/v1/lib/users.sh"
# (pré-início não lê métricas — 0 colunas de problema; pula o recompute em massa)
if (( ! PRESTART )) && [[ ! -f "$STAMP" || "$CONF" -nt "$STAMP" || "$_ULIB" -nt "$STAMP" ]]; then
  while IFS= read -r _u; do
    [[ -n "$_u" ]] && metrics_recompute "$CONTEST" "$_u"
  done < <(list_users "$CONTEST")
  touch "$STAMP"
fi

# gen_one <outfile> <nofreeze:0|1> — roda o gerador (MOJ_NOFREEZE controla a visão
# frozen×completa dos metrics), instalando atômico com checagem do modo.
gen_one() {
  local out="$1" nofreeze="$2" tmp first
  tmp="$(mktemp "$out.XXXXXX")" || die "cannot create temp file next to $out"
  if ! MOJ_NOFREEZE="$nofreeze" MOJ_COHORTS="${VIEW_COHORTS:-}" MOJ_UNRANKED="${VIEW_UNRANKED:-}" \
       MOJ_PRESTART="${MOJ_PRESTART:-}" \
       bash "$GEN" "$CONTEST" > "$tmp"; then rm -f "$tmp"; die "generator failed: $GEN $CONTEST"; fi
  first="$(head -1 "$tmp")"
  [[ "$first" == "$MODE" ]] || { rm -f "$tmp"; die "generator '$GEN' line 1 was '$first', expected '$MODE'"; }
  mv "$tmp" "$out" || { rm -f "$tmp"; die "cannot install board to $out"; }
  # VERSÃO COMPRIMIDA ao lado. O placar de 2000 times tem ~175 KB e é o corpo mais servido do
  # dia; sem isto o nginx recomprime o MESMO conteúdo a cada requisição (medido: 7% da vazão
  # da rota). Gravada DEPOIS do .txt e por tmp+mv — se falhar, o pior caso é o nginx comprimir
  # como antes, nunca servir um .gz de conteúdo diferente do .txt. O handler só a usa quando
  # ela não é mais VELHA que o .txt.
  gzip -6 -c < "$out" > "$out.gz.tmp.$$" 2>/dev/null && mv -f "$out.gz.tmp.$$" "$out.gz" 2>/dev/null \
    || rm -f "$out.gz.tmp.$$" "$out.gz" 2>/dev/null
  return 0
}

# gen_pair <out-frozen> <out-full> — o par de sempre (com freeze gera os dois; sem freeze,
# completo == público e o `-full` é removido).
gen_pair() {
  local out="$1" full="$2"
  if [[ -n "$FREEZE_RAW" ]] && (( FREEZE_RAW > 0 )); then
    gen_one "$full" 1     # completo (sem freeze) — gera primeiro
    gen_one "$out"  0     # público (com freeze)
  else
    rm -f "$full" "$full.gz" 2>/dev/null
    gen_one "$out" 0
  fi
}

# COORTES (times oficiais × convidados): quando o contest tem coorte NÃO-pública, cada VISÃO
# ganha o seu par de placares — `var/placar[-full].txt` continua sendo a visão pública (nada
# mudou de nome para quem já lia), e cada visão extra vira `var/placar-view-<id>[-full].txt`.
# Sem cohorts.json (ou com todas as coortes públicas) isto roda exatamente as 1-2 passadas de
# sempre: nenhum custo novo. Ver server/api/v1/lib/cohorts.sh.
VIEW_COHORTS=""; VIEW_UNRANKED=""
CH_LIB="$HERE/../api/v1/lib/cohorts.sh"
if [[ -s "$CONTESTDIR/cohorts.json" && -r "$CH_LIB" ]]; then
  # shellcheck source=/dev/null
  source "$CH_LIB"
  export CONTESTSDIR
fi

# --prestart: uma passada só, com os envs da VISÃO PÚBLICA das coortes (coorte privada não
# pode aparecer antes do início) e sem par frozen/full (não há submissão antes do start).
if (( PRESTART )); then
  PRE="$CONTESTDIR/var/placar-prestart.txt"
  if declare -F ch_enabled >/dev/null && ch_enabled "$CONTEST"; then
    VIEW_COHORTS="$(ch_cohorts_of_view "$CONTEST" public)"
    VIEW_UNRANKED="$(ch_unranked_of_view "$CONTEST" public | tr '\n' ' ' | sed 's/ *$//')"
  fi
  MOJ_PRESTART=1 gen_one "$PRE" 1
  echo "$PRE"
  exit 0
fi

if declare -F ch_enabled >/dev/null && ch_enabled "$CONTEST"; then
  mapfile -t VIEWS < <(ch_views "$CONTEST")
  for v in "${VIEWS[@]}"; do
    [[ -n "$v" ]] || continue
    VIEW_COHORTS="$(ch_cohorts_of_view "$CONTEST" "$v")"
    VIEW_UNRANKED="$(ch_unranked_of_view "$CONTEST" "$v" | tr '\n' ' ' | sed 's/ *$//')"
    if [[ "$v" == public ]]; then gen_pair "$OUT" "$FULL"
    else gen_pair "$(ch_view_file "$CONTEST" "$v")" "$(ch_view_file "$CONTEST" "$v" full)"; fi
  done
  # placares de visão que sobraram de uma coorte removida não podem seguir servíveis
  ( set +o noglob; shopt -s nullglob
    for f in "$CONTESTDIR"/var/placar-view-*.txt; do
      base="${f##*/placar-view-}"; base="${base%-full.txt}"; base="${base%.txt}"
      printf '%s\n' "${VIEWS[@]}" | grep -qxF "$base" || rm -f "$f" "$f.gz"
    done )
else
  rm -f "$CONTESTDIR"/var/placar-view-*.txt "$CONTESTDIR"/var/placar-view-*.txt.gz 2>/dev/null
  gen_pair "$OUT" "$FULL"
fi

echo "$OUT"
