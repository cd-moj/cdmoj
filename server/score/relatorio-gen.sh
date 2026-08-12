#!/usr/bin/env bash
#
# relatorio-gen.sh <since> <until> <outfile>
#
# Gera o JSON do relatório de submissões por contest (o painel que o mojinho posta no
# grupo dos professores): top-10 de contests por submissões na janela [since,until],
# treino em linha própria, usuários ativos, e as comparações com o MESMO período do ano
# anterior e com o acumulado do ano (YTD) vs o anterior. Saída ATÔMICA em <outfile>.
#
# Conta SÓ usuários normais — descarta privilegiados (regex de stats-gen.sh, COM cstaff).
# O epoch da submissão é o PENÚLTIMO campo ($(NF-1)): o verdict pode conter ':'
# ("Accepted,100p. Pontos | 100 |") e desloca os campos — nunca usar $5/cut.
#
# UMA passada sobre todos os history (find -print0 | xargs awk): o estágio 1 é stateless
# por linha (só normaliza contest/login/epoch dentro da janela envelope), então o split
# do xargs em vários awk é inócuo; o estágio 2 agrega tudo num único awk. Não copiar o
# loop por-contest do problem-panorama-gen.sh (forka um processo por usuário).
set -u
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
export TZ="${MOJ_TZ:-America/Sao_Paulo}"

SINCE="${1:-}"; UNTIL="${2:-}"; OUT="${3:-}"
[[ "$SINCE" =~ ^[0-9]+$ && "$UNTIL" =~ ^[0-9]+$ && -n "$OUT" ]] \
  || { echo "uso: relatorio-gen.sh <since-epoch> <until-epoch> <outfile>" >&2; exit 1; }
(( SINCE < UNTIL )) || { echo "relatorio-gen: since >= until" >&2; exit 1; }

# --- as 4 janelas ------------------------------------------------------------
# A = [since,until] (relatório); B = A deslocada -1 ano (calendário, não -365d);
# C = [1º/jan do ano de until, until] (YTD); D = C deslocada -1 ano.
# ⚠ GNU date: "@N -1 year" é inválido, e "<data> -1 year" lê o -1 como FUSO (UTC-1) e
#   ANDA um ano pra frente — a forma segura é "<data local> 1 year ago".
year_ago(){ date -d "$(date -d "@$1" +'%Y-%m-%d %H:%M:%S') 1 year ago" +%s; }
AS="$SINCE"; AE="$UNTIL"
BS="$(year_ago "$AS")"; BE="$(year_ago "$AE")"
CS="$(date -d "$(date -d "@$AE" +%Y)-01-01 00:00:00" +%s)"; CE="$AE"
DS="$(year_ago "$CS")"; DE="$BE"
MIN="$AS"; for x in "$BS" "$CS" "$DS"; do (( x < MIN )) && MIN="$x"; done
MAX="$AE"

mkdir -p "$(dirname "$OUT")" 2>/dev/null
TMP="$(mktemp "$OUT.XXXXXX")" || { echo "relatorio-gen: mktemp falhou" >&2; exit 1; }
NORM="$(mktemp)"; AGG="$(mktemp)"; NAMES="$(mktemp)"
# TERM/INT também limpam (a lib roda o gerador sob `timeout` — sem o trap de TERM os
# temporários $OUT.XXXXXX iriam se acumulando em var/ a cada estouro de orçamento).
trap 'rm -f "$TMP" "$NORM" "$AGG" "$NAMES"' EXIT
trap 'rm -f "$TMP" "$NORM" "$AGG" "$NAMES"; exit 143' INT TERM

# --- estágio 1: normaliza (contest, login, epoch) na janela envelope ---------
find "$CONTESTSDIR" -mindepth 4 -maxdepth 4 -type f -path '*/users/*/history' -print0 \
| xargs -0 -r awk -F: -v MIN="$MIN" -v MAX="$MAX" '
    FNR==1 { n=split(FILENAME,p,"/"); login=p[n-1]; contest=p[n-3];
             skip=(login ~ /\.(admin|judge|cjudge|staff|cstaff|mon)$/) }
    skip { next }
    NF>=5 { e=$(NF-1)+0; if (e>=MIN && e<=MAX) printf "%s\t%s\t%d\n", contest, login, e }
  ' > "$NORM"

# --- estágio 2: agrega as 4 janelas ------------------------------------------
# "usuários ativos" = logins DISTINTOS (contas são por-contest, mas o login costuma ser
# a matrícula/conta única da pessoa — é a melhor aproximação de "alunos" disponível).
awk -F'\t' -v AS="$AS" -v AE="$AE" -v BS="$BS" -v BE="$BE" \
           -v CS="$CS" -v CE="$CE" -v DS="$DS" -v DE="$DE" '
  { c=$1; u=$2; e=$3+0
    if (e>=AS && e<=AE) { at++; ac[c]++; if (!(u in au)) { au[u]=1; aus++ } }
    if (e>=BS && e<=BE) { bt++; if (!(u in bu)) { bu[u]=1; bus++ } }
    if (e>=CS && e<=CE) ct++
    if (e>=DS && e<=DE) dt++ }
  END { for (c in ac) printf "C\t%s\t%d\n", c, ac[c]
        printf "G\t%d\t%d\t%d\t%d\t%d\t%d\n", at+0, aus+0, bt+0, bus+0, ct+0, dt+0 }
' "$NORM" > "$AGG"

# --- JSON base (sem nomes ainda) ----------------------------------------------
jq -R -s --argjson S "$SINCE" --argjson U "$UNTIL" --argjson now "$EPOCHSECONDS" \
   --argjson bs "$BS" --argjson be "$BE" --argjson cs "$CS" --argjson ds "$DS" --argjson de "$DE" '
  [ split("\n")[] | select(length>0) | split("\t") ] as $r
  | ([ $r[] | select(.[0]=="G") ][0]) as $g
  | ([ $r[] | select(.[0]=="C") | {contest: .[1], count: (.[2]|tonumber)} ]) as $cs0
  | ([ $cs0[] | select(.contest=="treino") ] | ((.[0].count) // 0)) as $treino
  | ([ $cs0[] | select(.contest!="treino") ] | sort_by(-.count, .contest)) as $rank
  | { success: true, generated_at: $now, since: $S, until: $U,
      window: { total: (if $g then ($g[1]|tonumber) else 0 end),
                users: (if $g then ($g[2]|tonumber) else 0 end),
                treino: $treino,
                top: ($rank[:10]),
                others: ([ $rank[10:][].count ] | add // 0),
                others_count: ($rank[10:] | length) },
      prev_window: { since: $bs, until: $be,
                     total: (if $g then ($g[3]|tonumber) else 0 end),
                     users: (if $g then ($g[4]|tonumber) else 0 end) },
      ytd:      { since: $cs, total: (if $g then ($g[5]|tonumber) else 0 end) },
      prev_ytd: { since: $ds, until: $de, total: (if $g then ($g[6]|tonumber) else 0 end) } }
' "$AGG" > "$TMP" || { echo "relatorio-gen: jq falhou" >&2; exit 1; }

# --- nomes (CONTEST_NAME) SÓ dos ≤10 do top: conf é *sourced*, sempre em subshell ----
while IFS= read -r c; do
  [[ -n "$c" ]] || continue
  name="$( ( set +u; CONTEST_NAME=""; source "$CONTESTSDIR/$c/conf" 2>/dev/null
             printf '%s' "$CONTEST_NAME" ) 2>/dev/null | tr '\t\n' '  ' )"
  printf '%s\t%s\n' "$c" "$name"
done < <(jq -r '.window.top[].contest' "$TMP" 2>/dev/null) > "$NAMES"
namesjson="$(jq -R -s '[ split("\n")[] | select(length>0) | split("\t")
                         | {key: .[0], value: (.[1] // "")} ] | from_entries' "$NAMES" 2>/dev/null)"
[[ -n "$namesjson" ]] || namesjson='{}'
jq --argjson names "$namesjson" \
   '.window.top |= map(. + {name: ($names[.contest] // "")})' "$TMP" > "$TMP.n" \
  && mv "$TMP.n" "$TMP"

mv "$TMP" "$OUT"; trap - EXIT; rm -f "$NORM" "$AGG" "$NAMES"
