#!/bin/bash
# webcast-gen.sh <contest> <view> <saída.zip>
#
# Gera o PACOTE DE PLACAR que o sistema **Animeitor** consome — o mesmo formato que o BOCA
# entrega em `admin/report/webcast.php?webcastcode=…` (analisado byte a byte; ver
# docs/WEBCAST.md). É um ZIP com cinco arquivos, campos separados por **0x1C** (FS, não TAB!)
# e linhas por \n:
#
#   contest  1: <nome da competição>
#            2: <duração>␜<lastmileanswer>␜<lastmilescore>␜<penalidade>   (MINUTOS)
#            3: <nº de times>␜<nº de problemas>
#            N: <login>␜<sigla>␜<nome do time>
#               1␜1
#               <nº de problemas>␜Y
#   runs     <id>␜<minuto>␜<login>␜<letra>␜<Y|N|?|X>   (uma por submissão)
#   time     SEGUNDOS decorridos da prova (inteiro, sem \n; NEGATIVO antes do início,
#            limitado à duração no teto)
#   version  1.0
#   icpc     vazio (no BOCA o bloco que o preenchia está sob `if(false)`)
#
# PRINCÍPIO: o pacote vai SEMPRE COMPLETO, sem congelamento — no BOCA o `$freezeTime` é
# sobrescrito pela duração antes de filtrar. Quem anima a virada é o Animeitor, e ele sabe a
# hora do congelamento porque ela está no `lastmilescore` do `contest`.
#
# A <view> é a visão de coorte (public|all|<id da coorte>): o pacote sai com os times daquela
# visão — é o análogo do `webcast.sep` do BOCA, que restringia por site/faixa de usuário.
set -u
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
export CONTESTSDIR

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

C="${1:-}"; VIEW="${2:-public}"; OUT="${3:-}"
[[ -n "$C" && -n "$OUT" ]] || { echo "uso: webcast-gen.sh <contest> <view> <saída.zip>" >&2; exit 1; }
# o zip roda com `cd` no staging: caminho relativo iria parar lá dentro
[[ "$OUT" == /* ]] || OUT="$PWD/$OUT"
case "$C" in *[!A-Za-z0-9._@#+-]* | "" | *..* ) echo "webcast-gen: contest inválido" >&2; exit 1;; esac
CDIR="$CONTESTSDIR/$C"
[[ -f "$CDIR/conf" ]] || { echo "webcast-gen: sem conf em $CDIR" >&2; exit 1; }

PROBS=(); CONTEST_NAME=""; CONTEST_START=""; CONTEST_END=""; FREEZE_TIME=""; PENALTY_MINUTES=""
set +o noglob; shopt -s nullglob
# shellcheck disable=SC1090
source "$CDIR/conf" 2>/dev/null || true
START="${CONTEST_START:-0}"; [[ "$START" =~ ^[0-9]+$ ]] || START=0
END="${CONTEST_END:-0}";     [[ "$END"   =~ ^[0-9]+$ ]] || END=0
FREEZE="${FREEZE_TIME:-0}";  [[ "$FREEZE" =~ ^[0-9]+$ ]] || FREEZE=0
PEN="${PENALTY_MINUTES:-20}"; [[ "$PEN" =~ ^[0-9]+$ ]] || PEN=20
CNAME="${CONTEST_NAME:-$C}"
NOW="$EPOCHSECONDS"

DUR=$(( (END > START) ? (END - START) / 60 : 0 ))
# lastmilescore = minuto do congelamento (o Animeitor usa p/ saber a partir de onde animar).
# Sem freeze, "congela" no fim = nunca.
FZMIN=$DUR; (( FREEZE > START )) && FZMIN=$(( (FREEZE - START) / 60 ))
(( FZMIN > DUR )) && FZMIN=$DUR
# lastmileanswer = quando os juízes param de responder (o MOJ não tem esse conceito: = duração)
LMA=$DUR
# relógio da prova em SEGUNDOS decorridos — NEGATIVO antes do início (pedido do Animeitor,
# 27/08/2026; até então saía em minutos e com piso 0, e o telão não sabia distinguir "faltam
# 10 min" de "acabou de começar"). Teto na duração: prova encerrada = relógio parado no fim.
# ⚠ só o arquivo `time` fala em segundos — duração/freeze/penalidade do `contest` e o carimbo
# das linhas de `runs` continuam em MINUTOS (formato do BOCA).
TSEC=$(( NOW - START )); (( TSEC > DUR * 60 )) && TSEC=$(( DUR * 60 ))

W="$(mktemp -d)" || exit 1
trap 'rm -rf "$W"' EXIT

# --- times, problemas e runs: FONTE ÚNICA em telao-runs.sh (a mesma da API do Animeitor —
# lib/animeitor.sh; a regra do flag Y/N/X/? mora lá, duas cópias seriam dois placares no telão)
bash "$HERE/telao-runs.sh" "$C" "$VIEW" --teams > "$W/teams.tsv" \
  || { echo "webcast-gen: sem placar para a visão '$VIEW'" >&2; exit 1; }
[[ -s "$W/teams.tsv" ]] || { echo "webcast-gen: sem placar para a visão '$VIEW'" >&2; exit 1; }
NTEAMS="$(wc -l < "$W/teams.tsv" | tr -d '[:space:]')"
NPROB=$(( ${#PROBS[@]} / 5 ))

# runs: id sequencial pela ordem cronológica (o BOCA usa o runnumber, que também só cresce) e
# carimbo em MINUTOS — é o formato do BOCA; a API do Animeitor recebe segundos e id estável.
bash "$HERE/telao-runs.sh" "$C" "$VIEW" --runs \
| awk -F'\t' -v START="$START" 'BEGIN{OFS="\x1c"} {
    min=int(($1 - START)/60); if (min < 0) min=0
    print ++id, min, $2, $3, $4 }' > "$W/runs"

# --- contest ---------------------------------------------------------------------------
{
  printf '%s\n' "$CNAME"
  printf '%s\x1c%s\x1c%s\x1c%s\n' "$DUR" "$LMA" "$FZMIN" "$PEN"
  printf '%s\x1c%s\n' "$NTEAMS" "$NPROB"
  awk -F'\t' 'BEGIN{OFS="\x1c"} { print $1, $2, $3 }' "$W/teams.tsv"
  printf '1\x1c1\n'
  printf '%s\x1cY\n' "$NPROB"
} > "$W/contest"

printf '%s' "$TSEC" > "$W/time"
printf '1.0\n'      > "$W/version"
: > "$W/icpc"

# --- zip (entradas na RAIZ; o BOCA grava "./contest" e todo unzip normaliza) ------------
rm -f "$OUT"
( cd "$W" && zip -q -X "$OUT" contest runs time version icpc ) || {
  echo "webcast-gen: falha ao empacotar" >&2; exit 1; }
[[ -s "$OUT" ]] || { echo "webcast-gen: zip vazio" >&2; exit 1; }
exit 0
