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
#   time     minuto corrente da prova (inteiro, sem \n), limitado à duração
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
source "$HERE/../api/v1/lib/users.sh"     # emit_history_stream
source "$HERE/../api/v1/lib/verdict.sh"   # VERDICT_CANON_AWK, PENALTY_CODES_*
source "$HERE/../api/v1/lib/cohorts.sh"   # ch_view_file

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
# minuto corrente, limitado à duração (antes do início, 0)
TMIN=$(( (NOW > START) ? (NOW - START) / 60 : 0 )); (( TMIN > DUR )) && TMIN=$DUR

W="$(mktemp -d)" || exit 1
trap 'rm -rf "$W"' EXIT

# --- times da VISÃO: o TXT do placar já vem filtrado pela coorte -----------------------
TXT="$(ch_view_file "$C" "$VIEW" 2>/dev/null)"
[[ -s "$TXT" ]] || TXT="$CDIR/var/placar.txt"
[[ -s "$TXT" ]] || { echo "webcast-gen: sem placar para a visão '$VIEW'" >&2; exit 1; }

# login\tsigla\tnome — pela ORDEM do placar (a mesma que o Animeitor vai ver)
awk -F: 'NR==2{ n=split($0,H,":"); s=1
    while (s<=n && (tolower(H[s])=="desc" || tolower(H[s])=="asc")) s++
    for(i=s;i<=n;i++){ c++; h=tolower(H[i]); gsub(/^[ \t]+|[ \t]+$/,"",h)
      if(h=="username")iu=c; else if(h=="univ short")ius=c; else if(h=="team name")it=c }
    next }
  NR>2 && NF{ split($0,a,":")
    if (iu && a[iu]!="") printf "%s\t%s\t%s\n", a[iu], (ius?a[ius]:""), (it?a[it]:a[iu]) }' \
  "$TXT" > "$W/teams.tsv"
NTEAMS="$(wc -l < "$W/teams.tsv" | tr -d '[:space:]')"

# --- problemas: probid (nas 4 grafias do history) -> LETRA -----------------------------
: > "$W/probs.tsv"
NPROB=0
for (( i=0; i<${#PROBS[@]}; i+=5 )); do
  praw="${PROBS[$((i+1))]}"; pshort="${PROBS[$((i+3))]}"; pskey="${PROBS[$((i+4))]}"
  phash="$pskey"; [[ "$phash" == *"#"* ]] || phash="${praw//\//#}"
  NPROB=$((NPROB+1))
  # mesmas grafias que o report-gen resolve: offset numérico, cru, com ponto e com #
  printf '%s\t%s\n%s\t%s\n%s\t%s\n%s\t%s\n' \
    "$i" "$pshort" "$praw" "$pshort" "${praw/\//.}" "$pshort" "$phash" "$pshort" >> "$W/probs.tsv"
done

# --- veredictos que NÃO contam tentativa (viram X, como o CE do BOCA) ------------------
pvline="$(grep -m1 '^PENALTY_VERDICTS=' "$CDIR/conf" 2>/dev/null)"
if [[ -n "$pvline" ]]; then pv="$(printf '%s' "${pvline#PENALTY_VERDICTS=}" | tr -cd 'a-z ')"
else pv="$PENALTY_CODES_DEFAULT"; fi
DENY=""
for code in $PENALTY_CODES_ALL; do
  [[ " $pv " == *" $code "* ]] || DENY+="${DENY:+|}$(penalty_code_canon "$code")"
done

# --- runs: uma linha por submissão dos times da visão ----------------------------------
# id sequencial pela ordem cronológica (o BOCA usa o runnumber, que também só cresce).
emit_history_stream "$C" \
| awk -F: -v TEAMS="$W/teams.tsv" -v PROBS="$W/probs.tsv" -v START="$START" -v DENY="$DENY" \
      "$VERDICT_CANON_AWK"'
  function flag(v,   c) {
    c = canon(v)
    if (c ~ /^(Not Answered Yet|On queue|Running)/) return "?"   # pendente
    if (c ~ / \(Ignored\)$/) return "X"                          # fora da contagem
    if (c == "Accepted") return "Y"
    if (c == "Judge Error") return "X"
    if (DENY != "" && c ~ ("^(" DENY ")$")) return "X"           # não penaliza (CE por default)
    return "N"
  }
  BEGIN{
    while ((getline l < TEAMS) > 0) { n=split(l,a,"\t"); if(n>=1 && a[1]!="") T[a[1]]=1 }
    close(TEAMS)
    while ((getline l < PROBS) > 0) { n=split(l,a,"\t"); if(n>=2) L[a[1]]=a[2] }
    close(PROBS)
  }
  NF>=6 {
    # campos: 1=tempo 2=login 3=probid 4=lang 5..(NF-2)=verdict NF-1=sub_epoch NF=subid
    login=$2; prob=$3
    if (!(login in T)) next
    if (!(prob in L)) next
    v=$5; for(i=6;i<=NF-2;i++) v=v ":" $i
    ep=$(NF-1)+0
    min=int((ep - START)/60); if (min < 0) min=0
    printf "%s\t%s\t%s\t%s\t%s\n", ep, min, login, L[prob], flag(v)
  }' \
| sort -t$'\t' -k1,1n -k3,3 \
| awk -F'\t' 'BEGIN{OFS="\x1c"} { print ++id, $2, $3, $4, $5 }' > "$W/runs"

# --- contest ---------------------------------------------------------------------------
{
  printf '%s\n' "$CNAME"
  printf '%s\x1c%s\x1c%s\x1c%s\n' "$DUR" "$LMA" "$FZMIN" "$PEN"
  printf '%s\x1c%s\n' "$NTEAMS" "$NPROB"
  awk -F'\t' 'BEGIN{OFS="\x1c"} { print $1, $2, $3 }' "$W/teams.tsv"
  printf '1\x1c1\n'
  printf '%s\x1cY\n' "$NPROB"
} > "$W/contest"

printf '%s' "$TMIN" > "$W/time"
printf '1.0\n'      > "$W/version"
: > "$W/icpc"

# --- zip (entradas na RAIZ; o BOCA grava "./contest" e todo unzip normaliza) ------------
rm -f "$OUT"
( cd "$W" && zip -q -X "$OUT" contest runs time version icpc ) || {
  echo "webcast-gen: falha ao empacotar" >&2; exit 1; }
[[ -s "$OUT" ]] || { echo "webcast-gen: zip vazio" >&2; exit 1; }
exit 0
