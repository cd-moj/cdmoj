#!/bin/bash
# telao-runs.sh <contest> [<view>] [--teams|--probs|--runs|--runs-ids]
#
# FONTE ÚNICA do que o MOJ entrega ao TELÃO (sistema Animeitor): os times de uma visão, as letras
# dos problemas e as RUNS com o flag de quatro estados. Dois consumidores, que TÊM de concordar:
#   · score/webcast-gen.sh  — o ZIP no protocolo do BOCA (legado, puxado por chave);
#   · lib/animeitor.sh      — a API do Animeitor (o MOJ empurra evento, runs e relógio).
# A regra do flag nasceu no webcast-gen (docs/WEBCAST.md) e mora AQUI desde 21/09/2026: duas cópias
# dela seriam dois placares diferentes no mesmo telão.
#
#   --teams   login \t sigla \t nome            na ORDEM do placar da visão (TXT do build.sh; conta
#                                               de papel nunca está lá)
#   --probs   letra                             na ordem do PROBS do conf
#   --runs    epoch \t login \t letra \t flag \t subid     (padrão) ordenado por (epoch, login)
#   --runs-ids  id \t epoch \t login \t letra \t flag       o mesmo, com o ID INTEIRO ESTÁVEL da
#             submissão. A API do Animeitor CORRIGE por id (reenviar o id troca o veredicto), então o
#             id não pode depender da ordem: o sequencial do webcast muda inteiro quando chega uma
#             submissão offline atrasada. O mapa subid→inteiro mora em var/animeitor-ids.tsv, SÓ
#             APÊNDICE, sob flock; id novo = maior + 1, na ordem (epoch, login) de quem ainda não tem.
#             Sempre sobre a visão `all`/pedida — o id é do CONTEST, não da visão (mesmo arquivo).
#
#   flag:  Y aceito · N errado que PENALIZA · X não conta (CE e o que mais estiver fora do
#          PENALTY_VERDICTS, Judge Error, "(Ignored)") · ? pendente
#
# A <view> é a visão de coorte (public|all|<id>): só entram runs de time daquela visão.
set -u
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
export CONTESTSDIR
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../api/v1/lib/users.sh"     # emit_history_stream
source "$HERE/../api/v1/lib/verdict.sh"   # VERDICT_CANON_AWK, PENALTY_CODES_*
source "$HERE/../api/v1/lib/cohorts.sh"   # ch_view_file

C="${1:-}"; VIEW="public"; MODE="--runs"
shift 2>/dev/null || true
for a in "$@"; do case "$a" in --teams|--probs|--runs|--runs-ids) MODE="$a";; *) VIEW="$a";; esac; done
[[ -n "$C" ]] || { echo "uso: telao-runs.sh <contest> [<view>] [--teams|--probs|--runs|--runs-ids]" >&2; exit 1; }
case "$C" in *[!A-Za-z0-9._@#+-]* | "" | *..* ) echo "telao-runs: contest inválido" >&2; exit 1;; esac
CDIR="$CONTESTSDIR/$C"
[[ -f "$CDIR/conf" ]] || { echo "telao-runs: sem conf em $CDIR" >&2; exit 1; }

PROBS=(); CONTEST_START=""
set +o noglob; shopt -s nullglob
# shellcheck disable=SC1090
source "$CDIR/conf" 2>/dev/null || true
START="${CONTEST_START:-0}"; [[ "$START" =~ ^[0-9]+$ ]] || START=0

if [[ "$MODE" == --probs ]]; then
  for (( i=0; i<${#PROBS[@]}; i+=5 )); do printf '%s\n' "${PROBS[$((i+3))]}"; done
  exit 0
fi

W="$(mktemp -d)" || exit 1
trap 'rm -rf "$W"' EXIT

# --- times da VISÃO: o TXT do placar já vem filtrado pela coorte -----------------------
TXT="$(ch_view_file "$C" "$VIEW" 2>/dev/null)"
[[ -s "$TXT" ]] || TXT="$CDIR/var/placar.txt"
[[ -s "$TXT" ]] || { echo "telao-runs: sem placar para a visão '$VIEW'" >&2; exit 1; }
awk -F: 'NR==2{ n=split($0,H,":"); s=1
    while (s<=n && (tolower(H[s])=="desc" || tolower(H[s])=="asc")) s++
    for(i=s;i<=n;i++){ c++; h=tolower(H[i]); gsub(/^[ \t]+|[ \t]+$/,"",h)
      if(h=="username")iu=c; else if(h=="univ short")ius=c; else if(h=="team name")it=c }
    next }
  NR>2 && NF{ split($0,a,":")
    if (iu && a[iu]!="") printf "%s\t%s\t%s\n", a[iu], (ius?a[ius]:""), (it?a[it]:a[iu]) }' \
  "$TXT" > "$W/teams.tsv"
if [[ "$MODE" == --teams ]]; then cat "$W/teams.tsv"; exit 0; fi

# --- problemas: probid (nas 4 grafias do history) -> LETRA -----------------------------
: > "$W/probs.tsv"
for (( i=0; i<${#PROBS[@]}; i+=5 )); do
  praw="${PROBS[$((i+1))]}"; pshort="${PROBS[$((i+3))]}"; pskey="${PROBS[$((i+4))]}"
  phash="$pskey"; [[ "$phash" == *"#"* ]] || phash="${praw//\//#}"
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
emit_history_stream "$C" \
| awk -F: -v TEAMS="$W/teams.tsv" -v PROBS="$W/probs.tsv" -v DENY="$DENY" \
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
    printf "%s\t%s\t%s\t%s\t%s\n", $(NF-1)+0, login, L[prob], flag(v), $NF
  }' \
| sort -t$'\t' -k1,1n -k2,2 > "$W/runs.tsv"
if [[ "$MODE" != --runs-ids ]]; then cat "$W/runs.tsv"; exit 0; fi

# --- id inteiro estável (mapa só-apêndice sob flock) -----------------------------------
IDS="$CDIR/var/animeitor-ids.tsv"; mkdir -p "$CDIR/var"
exec {_fd}>"$CDIR/var/.animeitor-ids.lock" || exit 1
flock -w 20 "$_fd" || { echo "telao-runs: lock do mapa de ids ocupado" >&2; exit 1; }
[[ -e "$IDS" ]] || : > "$IDS"
awk -F'\t' -v IDS="$IDS" '
  BEGIN{ while ((getline l < IDS) > 0) { n=split(l,a,"\t"); if (n>=2 && a[1]!="") { M[a[1]]=a[2]+0; if (a[2]+0 > mx) mx=a[2]+0 } } close(IDS) }
  { if (!($5 in M)) { M[$5]=++mx; printf "%s\t%d\n", $5, mx >> IDS }
    printf "%d\t%s\t%s\t%s\t%s\n", M[$5], $1, $2, $3, $4 }' "$W/runs.tsv"
exit 0
