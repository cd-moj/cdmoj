#!/usr/bin/env bash
#
# classify-manual.sh — motor `manual`: TODA promoção é feita à mão (contests menores: seletiva de universidade). O
# admin diz quantos times sobem (`slots`) e qual é a próxima fase (nome/local/quando/chip do estágio); o painel mostra
# o PLACAR e ele clica no time a promover, com motivo OPCIONAL. Cada promoção é um override `add` (via manual) — o
# handler recusa passar de `slots` (409 slots_full). Este script só devolve o ranking (molde do classify-br.sh: nunca
# grava no contest).
#
#   classify-manual.sh <contest> <config.json> [out]
#   classify-manual.sh --check <config.json>          (rc 0 | rc 2 + {errors})
# config: {slots: N (≥ 0), ranking_limit?: 500, exclude?: [login], preassigned?: [{login}]}
# saída:  {classified:[] (nada é automático), ranking:[{place, login, team, univ, total, penalty, flag}] (o placar
#          OFICIAL, sem convidados e sem os excluídos, até ranking_limit linhas), slots, pre:[…], blocks, warnings,
#          labels (a via `manual` aqui é "promovido pela organização", não "comitê")}
set -u
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
mn_check(){
  jq -c 'def nonneg: type == "number" and floor == . and . >= 0;
    if type != "object" then ["a config tem de ser um objeto {slots}"] else [
      (if (.slots | nonneg) | not then "slots: inteiro ≥ 0 (quantos times serão promovidos)" else empty end),
      (if has("ranking_limit") and ((.ranking_limit | nonneg and . >= 1) | not) then "ranking_limit: inteiro ≥ 1" else empty end),
      (if has("exclude") and (.exclude | type) != "array" then "exclude: lista" else empty end),
      (if has("preassigned") and (.preassigned | type) != "array" then "preassigned: lista" else empty end)
    ] end' "$1" 2>/dev/null || printf '["config não é JSON válido"]'
}
if [[ "${1:-}" == --check ]]; then
  [[ -s "${2:-}" ]] || { echo '{"errors":["config vazia"]}' >&2; exit 2; }
  e="$(mn_check "$2")"; [[ "$e" == "[]" ]] && exit 0
  jq -cn --argjson e "$e" '{errors:$e}' >&2; exit 2
fi
C="${1:-}"; CFG="${2:-}"; OUT="${3:-/dev/stdout}"
[[ -n "$C" && -s "$CFG" ]] || { echo "uso: classify-manual.sh <contest> <config.json> [out]" >&2; exit 1; }
E="$(mn_check "$CFG")"
[[ "$E" == "[]" ]] || { jq -cn --argjson e "$E" '{errors:$e}' >&2; exit 2; }
source "$HERE/classify-common.sh"
cl_init "$C" || exit 1
cl_rows
jq -r '(.exclude // [])[] | if type == "object" then (.login // "") else tostring end | select(length > 0)' "$CFG" > "$W/excl.txt"
jq -r '(.preassigned // [])[] | if type == "object" then (.login // "") else tostring end | select(length > 0)' "$CFG" > "$W/pre.txt"
# ranking: as linhas do placar oficial, sem os excluídos (place · login · flag · sigla · time · escola · total · penal.)
awk -F'\t' -v OFS='\t' -v XF="$W/excl.txt" 'BEGIN { while ((getline l < XF) > 0) X[l] = 1; close(XF) }
  !($3 in X) { print $2, $3, $4, $5, $6, $7, ($8 + 0), ($9 + 0) }' "$W/rows.tsv" > "$W/rank.tsv"
LIM="$(jq -r '.ranking_limit // 500' "$CFG")"
NR="$(wc -l < "$W/rank.tsv")"
(( NR > LIM )) && cl_warn ranking_truncated "$(jq -cn --argjson n "$NR" --argjson l "$LIM" '{teams:$n, shown:$l}')"
jq -Rn --arg contest "$C" --slurpfile cfg "$CFG" --rawfile rk "$W/rank.tsv" --rawfile pr "$W/pre.txt" --argjson lim "$LIM" \
   --slurpfile wn <(cl_warnings_json) '
  ($rk | split("\n") | map(select(length > 0) | split("\t")
    | {place:(.[0] | tonumber? // null), login:.[1], flag:.[2], team:.[4], univ:(if .[3] != "" then .[3] else .[5] end),
       total:(.[6] | tonumber), penalty:(.[7] | tonumber)})) as $R
  | ($pr | split("\n") | map(select(length > 0))) as $P
  | ($R | map({key:.login, value:.}) | from_entries) as $byl
  | {contest:$contest, algorithm:"manual", generated_at:(now | floor), slots:$cfg[0].slots,
     classified:[], total:0, ranking:$R[0:$lim],
     pre:[ $P[] | select($byl[.] != null) | $byl[.] | {login, place, total, team, univ} ],
     blocks:[{id:"manual", type:"manual", slots:$cfg[0].slots, used:($P | length)}],
     via_order:["manual"],
     labels:{manual:{pt:"Promovido pela organização", en:"Promoted by the organizers", es:"Promovido por la organización",
                     short:{pt:"escolha da organização", en:"organizers\u0027 choice", es:"elección de la organización"}}},
     warnings:($wn[0] // [])}' > "$OUT"
