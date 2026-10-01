#!/usr/bin/env bash
#
# classify-mundial.sh — motor `latam-mundial`: promoção do CAMPEONATO LATINO-AMERICANO ao MUNDIAL (World Finals),
# regra "2026-2027 ICPC Latin America – Promotion Rules", "Promotion to the World Finals" (docs/CLASSIFICACAO.md,
# seção latam-mundial). Roda no contest do Campeonato. Standalone, molde do classify-pda.sh.
#
#   classify-mundial.sh <contest> <config.json> [out]
#   classify-mundial.sh --check <config.json>          (rc 0 | rc 2 + {errors})
# rc: 0 ok · 1 uso/IO · 2 config inválida · 3 RECUSA de dado (login fora do padrão de região/país).
#
# Regra (N_WF = vagas da LATAM no Mundial, o RCD informa; sem ele o motor avisa e não classifica ninguém):
#   1. o campeão de cada região (o melhor time da região com ≥ min_solved resolvidos) — `wf-region`;
#   2. as N_WF − (campeões) vagas restantes aos melhores do GERAL — `wf-overall`. Região sem time elegível: a vaga
#      vai ao geral (`region_slot_unfilled: "overall"`, decisão do Ribas).
#   Só UM time por instituição (`max_per_school`, padrão 1) vai ao Mundial, nos dois passos.
# Prêmios (INFORMATIVOS, em `awards`; não mudam a classificação): campeão LATAM (1º lugar), medalhas por posição
# (ouro 1–4, prata 5–8, bronze 9–12 — empate divide a posição; se o empate atravessa a faixa, a medalha vai a mais
# times e o motor avisa) e o campeão de cada região, com o título dela.
# Dados como no latam-pda: região/país pelas capturas de `login_regex`, escola = "<país>:<sigla>" › `school_alias`,
# overrides `exclude[]`/`preassigned[]` (o promovido à mão conta para a instituição, não ocupa vaga de N_WF).
set -u
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

wf_check(){ # <cfg> → stdout: array JSON de erros
  local cfg="$1" errs re
  errs="$(jq -c '
    def int: type == "number" and floor == .;
    def nonneg: int and . >= 0;
    if type != "object" then ["a config tem de ser um objeto"] else [
      (if (.N_WF != null) and ((.N_WF | nonneg) | not) then "N_WF: inteiro ≥ 0 (vagas da LATAM no Mundial)" else empty end),
      (if has("min_solved") and ((.min_solved | nonneg) | not) then "min_solved: inteiro ≥ 0" else empty end),
      (if has("max_per_school") and ((.max_per_school | int and . >= 1) | not) then "max_per_school: inteiro ≥ 1" else empty end),
      (if ((.region_slot_unfilled // "overall") | IN("overall", "none") | not) then "region_slot_unfilled: \"overall\" (vai ao geral) ou \"none\"" else empty end),
      (if has("login_regex") and (.login_regex | type) != "string" then "login_regex: texto" else empty end),
      (if (.regions | type == "array" and length > 0 and all(.[]; type == "object" and ((.code // "") | test("^[a-z]{2}$")))) | not
       then "regions: lista de {code (2 letras minúsculas), name, title?}" else empty end),
      (if (.regions | type) == "array" and ([.regions[].code] | length) != ([.regions[].code] | unique | length) then "regions: código repetido" else empty end),
      (if has("school_alias") and ((.school_alias | type == "object" and all(.[]; type == "string")) | not) then "school_alias: {\"país:sigla\": \"país:sigla\"}" else empty end),
      (if has("awards") and ((.awards | type == "object" and all(.[]; nonneg)) | not) then "awards: {gold, silver, bronze} inteiros ≥ 0" else empty end),
      (if has("exclude") and (.exclude | type) != "array" then "exclude: lista" else empty end),
      (if has("preassigned") and (.preassigned | type) != "array" then "preassigned: lista" else empty end)
    ] end' "$cfg" 2>/dev/null)" || errs='["config não é JSON válido"]'
  re="$(jq -r '.login_regex // "^team([a-z]{2})([a-z]{2})"' "$cfg" 2>/dev/null)"
  if ! CL_RE="$re" LC_ALL=C gawk 'BEGIN { re = ENVIRON["CL_RE"]; if (match("x", re)) {} }' 2>/dev/null; then
    errs="$(jq -c --arg r "$re" '. + ["login_regex: não compila (\($r))"]' <<<"$errs")"
  fi
  printf '%s' "$errs"
}

if [[ "${1:-}" == --check ]]; then
  [[ -s "${2:-}" ]] || { echo '{"errors":["config vazia"]}' >&2; exit 2; }
  e="$(wf_check "$2")"; [[ "$e" == "[]" ]] && exit 0
  jq -cn --argjson e "$e" '{errors:$e}' >&2; exit 2
fi
C="${1:-}"; CFG="${2:-}"; OUT="${3:-/dev/stdout}"
[[ -n "$C" && -s "$CFG" ]] || { echo "uso: classify-mundial.sh <contest> <config.json> [out]" >&2; exit 1; }
E="$(wf_check "$CFG")"
[[ "$E" == "[]" ]] || { jq -cn --argjson e "$E" '{errors:$e}' >&2; exit 2; }
source "$HERE/classify-common.sh"
cl_init "$C" || exit 1
LOC="$(cl_locale)"

jq -r --arg L "$LOC" 'def loc($x; $d): if ($x | type) == "object" then ($x[$L] // $x.en // $x.pt // $d) elif $x == null then $d else $x end;
  .regions[] | [.code, loc(.name; .code), loc(.title; "")] | join("\t")' "$CFG" > "$W/regions.tsv"
cut -f1 "$W/regions.tsv" > "$W/regcodes.txt"
jq -r "$CL_NORM_JQ"'(.school_alias // {}) | to_entries[] | [(.key | cl_skey), (.value | cl_skey)] | join("\t")' "$CFG" > "$W/alias.tsv"
jq -r '(.exclude // [])[] | if type == "object" then (.login // "") else tostring end | select(length > 0)' "$CFG" > "$W/excl.txt"
jq -r "$CL_NORM_JQ"'(.preassigned // [])[] | if type == "object" then . else {login:tostring} end
  | [(.login // ""), ((.school // "") | if . == "" then "" else cl_skey end)] | join("\t")' "$CFG" > "$W/pre.in"
read -r NWF MS MAXPS UNF GOLD SILVER BRONZE < <(jq -r '[(.N_WF // -1), (.min_solved // 1), (.max_per_school // 1),
  (.region_slot_unfilled // "overall"), ((.awards // {}).gold // 4), ((.awards // {}).silver // 4), ((.awards // {}).bronze // 4)]
  | map(tostring) | join(" ")' "$CFG")
RE="$(jq -r '.login_regex // "^team([a-z]{2})([a-z]{2})"' "$CFG")"

cl_rows
awk -F'\t' -v XF="$W/excl.txt" 'BEGIN { while ((getline l < XF) > 0) X[l] = 1; close(XF) } !($3 in X)' "$W/rows.tsv" > "$W/rows2.tsv" \
  && mv -f "$W/rows2.tsv" "$W/rows.tsv"
cl_attrs "$RE" "$W/regcodes.txt" "$W/alias.tsv"; rc=$?
(( rc == 0 )) || exit "$rc"
# ranking: login · place · total · escola · país · região · time · escola(texto)
awk -F'\t' -v OFS='\t' -v AT="$W/attrs.tsv" '
  BEGIN { while ((getline l < AT) > 0) { split(l, a, "\t"); S[a[1]] = a[4]; CY[a[1]] = a[3]; RG[a[1]] = a[2] } close(AT) }
  ($3 in S) { print $3, $2, ($8 + 0), S[$3], CY[$3], RG[$3], $6, ($5 != "" ? $5 : $7) }' "$W/rows.tsv" > "$W/rank.tsv"

: > "$W/cls.tsv"; : > "$W/blk.tsv"; : > "$W/aw.tsv"; : > "$W/wn.tsv"; : > "$W/pre.tsv"
LC_ALL=C gawk -F'\t' -v OFS='\t' -v NWF="$NWF" -v MS="$MS" -v MAXPS="$MAXPS" -v UNF="$UNF" \
    -v GOLD="$GOLD" -v SILVER="$SILVER" -v BRONZE="$BRONZE" -v RGF="$W/regions.tsv" -v PRF="$W/pre.in" \
    -v CLF="$W/cls.tsv" -v BLF="$W/blk.tsv" -v AWF="$W/aw.tsv" -v WNF="$W/wn.tsv" -v POF="$W/pre.tsv" '
function promote(i, via, det) {
  PR[i] = via; NSEQ++; SC[SCH[i]]++
  print NSEQ, via, L[i], P[i], TOT[i], SCH[i], CTY[i], REG[i], RNAME[REG[i]], TEAM[i], UNIV[i], det > CLF
}
function elig(i) { return !((i in PR) || (i in PRE)) && TOT[i] >= MS && SC[SCH[i]] < MAXPS }
function medal(name, lo, hi,   i, cnt) {   # posições (lo, hi]: empate divide a posição — a faixa pode crescer
  cnt = 0
  for (i = 1; i <= n; i++) if (P[i] > lo && P[i] <= hi) { cnt++; print "medal", name, L[i], P[i], TEAM[i], UNIV[i] > AWF }
  if (cnt > hi - lo) print "award_tie", name, cnt, hi - lo > WNF
}
BEGIN { while ((getline l < RGF) > 0) { split(l, a, "\t"); NRG++; RC[NRG] = a[1]; RNAME[a[1]] = a[2]; RTITLE[a[1]] = a[3] } close(RGF) }
{ n++; L[n] = $1; P[n] = $2 + 0; TOT[n] = $3 + 0; SCH[n] = $4; CTY[n] = $5; REG[n] = $6; TEAM[n] = $7; UNIV[n] = $8; IDX[$1] = n }
END {
  while ((getline l < PRF) > 0) { split(l, a, "\t"); k = a[1]; if (k == "") continue
    if (k in IDX) { i = IDX[k]; if (i in PRE) continue; PRE[i] = 1; SC[SCH[i]]++
      print L[i], P[i], TOT[i], SCH[i], CTY[i], REG[i], RNAME[REG[i]], TEAM[i], UNIV[i] > POF }
    else if (a[2] != "") SC[a[2]]++ }
  close(PRF)
  if (NWF < 0) { print "n_wf_missing" > WNF; NWF = 0 }
  # ---- 1. o campeão de cada região ----
  slots1 = (NWF < NRG) ? NWF : NRG
  if (NWF < NRG) print "n_wf_below_regions", NWF, NRG > WNF
  u1 = 0; miss = 0
  for (r = 1; r <= NRG; r++) { c = RC[r]
    if (r > slots1) break
    got = 0
    for (i = 1; i <= n; i++) if (REG[i] == c && elig(i)) { promote(i, "wf-region", "#" P[i] " · " RNAME[c]); got = 1; break }
    if (got) u1++
    else { miss++; print "wf_region_unfilled", c > WNF }
  }
  print "wf-region", "region", slots1, u1 > BLF
  # ---- 2. o geral: N_WF − campeões (a vaga de região sem time vem p/ cá, salvo region_slot_unfilled = none) ----
  slots2 = NWF - slots1 + ((UNF == "overall") ? miss : 0)
  if (slots2 < 0) slots2 = 0
  u2 = 0; last = 0
  for (i = 1; i <= n && u2 < slots2; i++) if (elig(i)) { promote(i, "wf-overall", "#" P[i]); u2++; last = i }
  if (slots2 > 0 && u2 == slots2 && last)
    for (j = last + 1; j <= n; j++) { if (!elig(j)) continue
      if (P[j] == P[last]) print "tie_boundary", "wf-overall", P[last], L[last], L[j] > WNF
      break }
  print "wf-overall", "overall", slots2, u2 > BLF
  # ---- prêmios (informativos) ----
  for (i = 1; i <= n; i++) if (P[i] == 1) print "champion", "", L[i], P[i], TEAM[i], UNIV[i] > AWF
  medal("gold", 0, GOLD); medal("silver", GOLD, GOLD + SILVER); medal("bronze", GOLD + SILVER, GOLD + SILVER + BRONZE)
  for (r = 1; r <= NRG; r++) { c = RC[r]
    for (i = 1; i <= n; i++) if (REG[i] == c) {
      for (j = i; j <= n && P[j] == P[i]; j++) if (REG[j] == c) print "regional", c, L[j], P[j], TEAM[j], UNIV[j] > AWF
      break } }
}' "$W/rank.tsv" || { echo "classify-mundial: o motor falhou" >&2; exit 1; }

jq -n --arg contest "$C" --slurpfile cfg "$CFG" --rawfile cls "$W/cls.tsv" --rawfile blk "$W/blk.tsv" --rawfile aw "$W/aw.tsv" \
   --rawfile wn "$W/wn.tsv" --rawfile pre "$W/pre.tsv" --rawfile rg "$W/regions.tsv" --slurpfile w0 <(cl_warnings_json) '
  def rows($t): $t | split("\n") | map(select(length > 0) | split("\t"));
  def num: if . == "" or . == null then null else tonumber end;
  ($cfg[0]) as $C
  | (rows($rg) | map({key:.[0], value:{name:.[1], title:.[2]}}) | from_entries) as $R
  | (rows($cls) | map({seq:(.[0] | tonumber), via:.[1], login:.[2], place:(.[3] | num), total:(.[4] | num), school:.[5], country:.[6],
                       region:.[7], sede:.[8], team:.[9], univ:.[10], detail:.[11]} | with_entries(select(.value != null and .value != "")))) as $list
  | (rows($blk) | map({id:.[0], type:.[1], slots:(.[2] | tonumber), used:(.[3] | tonumber)})) as $blocks
  | (rows($aw)) as $A
  | def aw($k): [ $A[] | select(.[0] == $k) | {login:.[2], place:(.[3] | tonumber), team:.[4], univ:.[5]} ];
  {contest:$contest, algorithm:"latam-mundial", generated_at:(now | floor), N_WF:$C.N_WF,
   classified:$list, total:($list | length),
   by_rule:($list | group_by(.via) | map({key:.[0].via, value:length}) | from_entries),
   blocks:$blocks,
   unused:($blocks | map(select(.slots > .used) | {key:.id, value:(.slots - .used)}) | from_entries),
   awards:{informative:true, champion:aw("champion"),
           medals:{gold:[ $A[] | select(.[0] == "medal" and .[1] == "gold") | {login:.[2], place:(.[3] | tonumber), team:.[4], univ:.[5]} ],
                   silver:[ $A[] | select(.[0] == "medal" and .[1] == "silver") | {login:.[2], place:(.[3] | tonumber), team:.[4], univ:.[5]} ],
                   bronze:[ $A[] | select(.[0] == "medal" and .[1] == "bronze") | {login:.[2], place:(.[3] | tonumber), team:.[4], univ:.[5]} ]},
           regional:[ $A[] | select(.[0] == "regional") | {region:.[1], name:$R[.[1]].name, title:$R[.[1]].title, login:.[2],
                                                             place:(.[3] | tonumber), team:.[4], univ:.[5]} ]},
   pre:(rows($pre) | map({login:.[0], place:(.[1] | tonumber), total:(.[2] | tonumber), school:.[3], country:.[4], region:.[5],
                          sede:.[6], team:.[7], univ:.[8]})),
   via_order:["wf-region", "wf-overall"],
   warnings:(($w0[0] // []) + (rows($wn) | map(. as $w | {code:$w[0]} + (
       if $w[0] == "wf_region_unfilled" then {data:{region:$w[1]}}
       elif $w[0] == "award_tie" then {data:{medal:$w[1], teams:($w[2] | tonumber), places:($w[3] | tonumber)}}
       elif $w[0] == "tie_boundary" then {data:{block:$w[1], place:($w[2] | tonumber), last:$w[3], next:$w[4]}}
       elif $w[0] == "n_wf_below_regions" then {data:{N_WF:($w[1] | tonumber), regions:($w[2] | tonumber)}}
       else {} end))))}' > "$OUT"
