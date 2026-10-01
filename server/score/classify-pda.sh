#!/usr/bin/env bash
#
# classify-pda.sh — motor `latam-pda`: promoção da regional LATAM (LAR) ao CAMPEONATO LATINO-AMERICANO (PDA),
# regra "2026-2027 ICPC Latin America – Promotion Rules" (docs/CLASSIFICACAO.md, seção latam-pda). Standalone,
# molde do classify-br.sh: nunca grava no contest (quem persiste é o handler admin/classify).
#
#   classify-pda.sh <contest> <config.json> [out]        prévia/cálculo → JSON
#   classify-pda.sh --check <config.json>                só valida a config (rc 0 | rc 2 + {errors})
#   classify-pda.sh --geo <entrada.json>                 só a alocação geográfica (teste de exatidão):
#                                                        {N, allocated, regions:[cód], schools:{cód:n},
#                                                         fractions_prev:{cód:f}} → {regions:{…}, …}
#   classify-pda.sh --waitlist <contest> <config.json> [out]   só a LISTA DE ESPERA contra o estado do estágio
#                                                        (config.waitlist_state {promoted:[{key,school?,country?,
#                                                         region?}], skip:[login]}, que o handler monta)
# rc: 0 ok · 1 uso/IO · 2 config inválida · 3 RECUSA de dado (login fora do padrão de região/país).
#
# Dados (todos pelas fontes únicas de score/classify-common.sh):
#   • participante = todo time no placar (sem convidados e sem desclassificados), menos `exclude[]`;
#   • região e país = as duas capturas de `login_regex` (padrão ^team([a-z]{2})([a-z]{2})); região fora de
#     `regions[]` ou login fora do padrão = RECUSA (exclua o login ou corrija a regra) — o motor não adivinha;
#   • escola = "<país>:<sigla normalizada>" › `school_alias`; feminina = faixa 3/2/1 dos recortes "Times
#     femininos" (só mulheres = faixa 3).
#
# A ordem dos passos (cada um vê os promovidos dos anteriores):
#   P1 desempenho (N/2, ≤ max_per_school por escola) → P2 países (teto min(N/4, X) − 1, X = países
#   participantes ainda sem time, calculado uma vez; ≥ min_solved) → P3 instituição-sede (se nenhuma escola-sede
#   tem time: 1 vaga ao melhor de qualquer escola sem time) → P4 geográfica (o algoritmo do PDF, em INTEIROS) →
#   femininas padrão (`female[]`, sem a regra geral) → blocos da edição (`edition_blocks[]`, na ordem).
# "Regra geral" = a escola ainda não tem time (o 2º time de uma escola só no P1). Os `preassigned[]` (overrides
# add do handler) já contam como promovidos (escola, país, região), mas não ocupam vaga de N.
set -u
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

# ---------------------------------------------------------------------------------------------------------------
# a ALOCAÇÃO GEOGRÁFICA (PDF, "Algorithm to assign the Geographic Representation Slots"), em INTEIROS:
#   q_R = escolas_R × (N − allocated); nslots_R = q_R div nLatam; fração_R += (q_R mod nLatam) / nLatam.
# O PDF divide duas vezes (slotsRatio = nLatam/(N − allocated), depois escolas_R/slotsRatio) e o ponto flutuante
# dá 10,999… onde a conta exata é 11. Depois: enquanto allocated < N, a(s) região(ões) com a MAIOR fração (empate
# com eps 1e-9 = TODAS levam) ganham 1 vaga e zeram a fração — pode passar de N (overflow). Frações > 0 seguem p/
# o ano seguinte (fractions_out). Entrada: NRG regiões RC[1..NRG], NS[c] escolas, PREV[c] fração herdada.
PDA_GEO_AWK='
function geo_alloc(N0, alloc0,    r, c, q, ns, alloc, mx, eps) {
  eps = 1e-9; alloc = alloc0; GREM = N0 - alloc0; GNL = 0; GOVER = 0; GSTUCK = 0
  for (r = 1; r <= NRG; r++) { c = RC[r]; GNL += NS[c] + 0 }
  for (r = 1; r <= NRG; r++) { c = RC[r]; GQ[c] = 0; GN[c] = 0; GE[c] = 0; GFP[c] = PREV[c] + 0; FR[c] = PREV[c] + 0 }
  if (GREM > 0 && GNL > 0) {
    for (r = 1; r <= NRG; r++) { c = RC[r]; q = (NS[c] + 0) * GREM; ns = int(q / GNL)
      GQ[c] = q; GN[c] = ns; alloc += ns; FR[c] += (q - ns * GNL) / GNL }
  }
  for (r = 1; r <= NRG; r++) { c = RC[r]; GF2[c] = FR[c] }
  while (GREM > 0 && GNL > 0 && alloc < N0) {
    mx = -1; for (r = 1; r <= NRG; r++) { c = RC[r]; if (FR[c] > mx) mx = FR[c] }
    if (mx <= eps) { GSTUCK = 1; break }
    for (r = 1; r <= NRG; r++) { c = RC[r]; if (FR[c] >= mx - eps) { GE[c]++; FR[c] = 0; alloc++ } }
  }
  if (alloc > N0) GOVER = alloc - N0
  for (r = 1; r <= NRG; r++) { c = RC[r]; GS[c] = GN[c] + GE[c]; if (FR[c] <= eps) FR[c] = 0 }
  return alloc
}'

# ---------------------------------------------------------------------------------------------------------------
# --check: a config inteira (estrutura e tipos). Ids de bloco únicos e fora dos reservados (p1–p4 e as vias manuais).
pda_check(){ # <cfg> → stdout: array JSON de erros
  local cfg="$1" errs re
  errs="$(jq -c '
    def int: type == "number" and floor == .;
    def nonneg: int and . >= 0;
    def strs: type == "array" and all(.[]; type == "string");
    def label_ok: . == null or type == "string" or (type == "object" and all(to_entries[]; (.key | test("^(pt|en|es)$")) and (.value | type) == "string" or .key == "short"));
    def ms($p): if type != "object" then "\($p): objeto" elif has("min_solved") and ((.min_solved | nonneg) | not) then "\($p).min_solved: inteiro ≥ 0" else empty end;
    ["p1","p2","p3","p4","manual","lista","reserva","comite"] as $reserved
    | if type != "object" then ["a config tem de ser um objeto"] else [
      (if (.N | int and . > 0 and (. % 4) == 0) | not then "N: inteiro > 0, múltiplo de 4" else empty end),
      (if has("max_per_school") and ((.max_per_school | int and . >= 1) | not) then "max_per_school: inteiro ≥ 1" else empty end),
      (if has("login_regex") and (.login_regex | type) != "string" then "login_regex: texto" else empty end),
      (if (.regions | type == "array" and length > 0 and all(.[]; type == "object" and ((.code // "") | test("^[a-z]{2}$")))) | not
       then "regions: lista de {code (2 letras minúsculas), name}" else empty end),
      (if (.regions | type) == "array" and ([.regions[].code] | length) != ([.regions[].code] | unique | length) then "regions: código repetido" else empty end),
      (if has("fractions_prev") and ((.fractions_prev | type == "object" and all(.[]; type == "number" and . >= 0 and . < 1)) | not)
       then "fractions_prev: {região: fração em [0, 1)}" else empty end),
      (if (.regions | type) == "array" then ([.regions[].code] as $rc | (.fractions_prev // {}) | if type == "object" then keys[] else empty end | select(. as $k | $rc | index($k) | not)
       | "fractions_prev: região desconhecida \(.)") else empty end),
      (if has("host_country") and ((.host_country | type == "string" and test("^[a-z]{2}$")) | not) then "host_country: 2 letras minúsculas" else empty end),
      (if has("host_schools") and ((.host_schools | strs) | not) then "host_schools: lista de \"país:sigla\"" else empty end),
      (if has("school_alias") and ((.school_alias | type == "object" and all(.[]; type == "string")) | not) then "school_alias: {\"país:sigla\": \"país:sigla\"}" else empty end),
      (if has("female_node") and (.female_node | type) != "string" then "female_node: texto" else empty end),
      (if has("participation") and .participation != "account" then "participation: só \"account\" (todo time no placar)" else empty end),
      ((.performance // {}) | ms("performance")), ((.host // {}) | ms("host")), ((.geo // {}) | ms("geo")),
      ((.countries // {}) | ms("countries")),
      (if (.countries | type) == "object" and ((.countries.cap // "min_minus_1") | IN("min_minus_1", "min_of_x_minus_1") | not)
       then "countries.cap: \"min_minus_1\" (min(N/4, X) − 1) ou \"min_of_x_minus_1\" (min(N/4, X − 1))" else empty end),
      (if (.geo | type) == "object" and (.geo.on_unfilled // "none") != "none" then "geo.on_unfilled: só \"none\" (a vaga sem time elegível fica sem uso)" else empty end),
      (if has("female") and ((.female | type) != "array") then "female: lista" else empty end),
      (if has("edition_blocks") and ((.edition_blocks | type) != "array") then "edition_blocks: lista" else empty end),
      ( [ ((.female // []) | if type == "array" then .[] | . + {type:"female", _std:true} else empty end),
          ((.edition_blocks // []) | if type == "array" then .[] else empty end) ] as $B
        | ($B | map(.id // "")) as $ids
        | (if ($ids | length) != ($ids | unique | length) then "blocos: id repetido" else empty end),
          ($B[] | (.id // "") as $id
            | if ($id | type) != "string" or ($id | test("^[a-z0-9-]{1,32}$") | not) then "bloco: id inválido (\($id))"
              elif ($reserved | index($id)) then "bloco \($id): id reservado"
              elif ((.label | label_ok) | not) then "bloco \($id): label = texto ou {pt,en,es,short}"
              elif .type == "female" then
                (if ((.scope // "") | IN("host_country", "host_school", "latam", "per_region") | not) then "bloco \($id): scope = host_country|host_school|latam|per_region" else empty end),
                (if ((.min_women // 3) | IN(1, 2, 3) | not) then "bloco \($id): min_women = 1, 2 ou 3" else empty end),
                (if ((.slots // 1) | nonneg | not) then "bloco \($id): slots inteiro ≥ 0" else empty end), ms("bloco \($id)")
              elif .type == "fixed" then
                (if ((.teams // []) | type == "array" and all(.[]; type == "object" and ((.ext // "") | test("^[a-z0-9][a-z0-9-]{0,47}$")) and ((.team // "") | type == "string" and length > 0))) | not
                 then "bloco \($id): teams = [{ext (minúsculas, dígitos e -), team, univ?, country?, region?}]" else empty end)
              elif .type == "country_participation" then
                (if ((.quotas // []) | type == "array" and length > 0 and all(.[]; nonneg)) | not then "bloco \($id): quotas = lista de inteiros ≥ 0" else empty end),
                (if ((.cycle_teams // {}) | type == "object" and all(.[]; nonneg)) | not then "bloco \($id): cycle_teams = {país: times}" else empty end),
                (if ((.cycle_institutions // {}) | type == "object" and all(.[]; nonneg)) | not then "bloco \($id): cycle_institutions = {país: instituições}" else empty end),
                ms("bloco \($id)")
              elif .type == "host_school" or .type == "reserve" then
                (if ((.slots // 0) | nonneg | not) then "bloco \($id): slots inteiro ≥ 0" else empty end), ms("bloco \($id)")
              else "bloco \($id): type = fixed|female|country_participation|host_school|reserve" end) ),
      (if has("waitlist") then (.waitlist | if type != "object" then "waitlist: objeto" else
         (if has("limit") and ((.limit | int and . >= 0) | not) then "waitlist.limit: inteiro ≥ 0" else empty end),
         ms("waitlist"),
         (if ((.tiers // []) | type == "array" and all(.[]; type == "object" and ((.id // "") | test("^[a-z0-9-]{1,32}$"))
               and ((.schools // []) | strs) and ((.countries // []) | strs))) | not
          then "waitlist.tiers = [{id, schools?:[\"país:sigla\"], countries?:[\"mx\"]}]" else empty end) end) else empty end),
      (if has("exclude") and (.exclude | type) != "array" then "exclude: lista" else empty end),
      (if has("preassigned") and (.preassigned | type) != "array" then "preassigned: lista" else empty end)
    ] end' "$cfg" 2>/dev/null)" || errs='["config não é JSON válido"]'
  # a regex do login tem de compilar no gawk (é ele que a usa)
  re="$(jq -r '.login_regex // "^team([a-z]{2})([a-z]{2})"' "$cfg" 2>/dev/null)"
  if ! CL_RE="$re" LC_ALL=C gawk 'BEGIN { re = ENVIRON["CL_RE"]; if (match("x", re)) {} }' 2>/dev/null; then
    errs="$(jq -c --arg r "$re" '. + ["login_regex: não compila (\($r))"]' <<<"$errs")"
  fi
  printf '%s' "$errs"
}

case "${1:-}" in
  --check)
    [[ -s "${2:-}" ]] || { echo '{"errors":["config vazia"]}' >&2; exit 2; }
    e="$(pda_check "$2")"; [[ "$e" == "[]" ]] && exit 0
    jq -cn --argjson e "$e" '{errors:$e}' >&2; exit 2;;
  --geo)
    [[ -s "${2:-}" ]] || { echo "uso: classify-pda.sh --geo <entrada.json>" >&2; exit 1; }
    GT="$(mktemp)" || exit 1
    jq -r '.fractions_prev as $f | .schools as $s | (.regions // [])[] | [., (($s // {})[.] // 0), (($f // {})[.] // 0)] | join("\t")' "$2" > "$GT" 2>/dev/null
    N0="$(jq -r '.N' "$2")"; A0="$(jq -r '.allocated // 0' "$2")"
    LC_ALL=C gawk -F'\t' -v N0="$N0" -v A0="$A0" "$PDA_GEO_AWK"'
      { NRG++; RC[NRG] = $1; NS[$1] = $2 + 0; PREV[$1] = $3 + 0 }
      END { a = geo_alloc(N0 + 0, A0 + 0)
        printf "{\"allocated\":%d,\"overflow\":%d,\"stuck\":%d,\"schools_latam\":%d,\"remaining\":%d,\"regions\":{", a, GOVER, GSTUCK, GNL, GREM
        for (r = 1; r <= NRG; r++) { c = RC[r]
          printf "%s\"%s\":{\"schools\":%d,\"q\":%d,\"nslots\":%d,\"extra\":%d,\"slots\":%d,\"fraction_prev\":%.12g,\"fraction\":%.12g,\"fraction_out\":%.12g}", (r > 1 ? "," : ""), c, NS[c], GQ[c], GN[c], GE[c], GS[c], GFP[c], GF2[c], FR[c] }
        printf "}}\n" }' "$GT"
    rc=$?; rm -f "$GT"; exit $rc;;
  --waitlist) MODE=waitlist; shift;;
  *) MODE=run;;
esac

C="${1:-}"; CFG="${2:-}"; OUT="${3:-/dev/stdout}"
[[ -n "$C" && -s "$CFG" ]] || { echo "uso: classify-pda.sh [--waitlist] <contest> <config.json> [out]" >&2; exit 1; }
E="$(pda_check "$CFG")"
[[ "$E" == "[]" ]] || { jq -cn --argjson e "$E" '{errors:$e}' >&2; exit 2; }
source "$HERE/classify-common.sh"
cl_init "$C" || exit 1
LOC="$(cl_locale)"

# --- config → arquivos (nada grande pelo argv) ------------------------------------------------------------------
jq -r --arg L "$LOC" '.regions[] | [.code, (if (.name | type) == "object" then (.name[$L] // .name.en // .name.pt // .code) else (.name // .code) end)] | join("\t")' "$CFG" > "$W/regions.tsv"
cut -f1 "$W/regions.tsv" > "$W/regcodes.txt"
jq -r "$CL_NORM_JQ"'(.school_alias // {}) | to_entries[] | [(.key | cl_skey), (.value | cl_skey)] | join("\t")' "$CFG" > "$W/alias.tsv"
jq -r "$CL_NORM_JQ"'(.host_schools // [])[] | cl_skey' "$CFG" > "$W/hosts.txt"
jq -r '.regions[].code as $c | [$c, ((.fractions_prev // {})[$c] // 0)] | join("\t")' "$CFG" > "$W/prev.tsv"
jq -r '(.exclude // [])[] | if type == "object" then (.login // "") else tostring end | select(length > 0)' "$CFG" > "$W/excl.txt"
# blocos depois do P4, na ordem: femininas padrão + blocos da edição
#   id · type · slots · scope · min_women · min_solved · general_rule · quotas(csv)
jq -r '[ ((.female // [])[] | . + {type:"female"}), (.edition_blocks // [])[] ][]
  | [.id, .type, ((.slots // (if .type == "female" then 1 else 0 end)) | tostring), (.scope // ""), ((.min_women // 3) | tostring),
     ((.min_solved // 0) | tostring), (if .general_rule == true then "1" else "0" end), ((.quotas // []) | map(tostring) | join(","))] | join("\t")' \
  "$CFG" > "$W/blocks.tsv"
# times fixos (pendentes): bloco · ext · time · escola-texto · chave-escola · país · região · conta(0/1)
jq -r "$CL_NORM_JQ"'(.edition_blocks // [])[] | select(.type == "fixed") | .id as $b | (if .counts_for_school == true then "1" else "0" end) as $k
  | (.teams // [])[] | [$b, .ext, (.team | gsub("[\t\n]"; " ")), ((.univ // "") | gsub("[\t\n]"; " ")),
     (if (.country // "") != "" and (.univ // "") != "" then ((.country | ascii_downcase) + ":" + (.univ | cl_norm)) else "" end),
     ((.country // "") | ascii_downcase), ((.region // "") | ascii_downcase), $k] | join("\t")' "$CFG" > "$W/fixed.tsv"
# tabela do ciclo: bloco · país · times · instituições (vazia = a prévia usa as contagens do contest e avisa)
jq -r '(.edition_blocks // [])[] | select(.type == "country_participation") | .id as $b | (.cycle_teams // {}) as $t | (.cycle_institutions // {}) as $i
  | (($t | keys) + ($i | keys) | unique)[] | [$b, ascii_downcase, (($t[.] // 0) | tostring), (($i[.] // 0) | tostring)] | join("\t")' "$CFG" > "$W/cycle.tsv"
# lista de espera: faixa · tipo(s|c) · valor
jq -r "$CL_NORM_JQ"'(.waitlist.tiers // [])[] | .id as $t | (((.schools // [])[] | [$t, "s", cl_skey]), ((.countries // [])[] | [$t, "c", ascii_downcase])) | join("\t")' "$CFG" > "$W/tiers.tsv"
jq -r '(.waitlist.tiers // [])[] | .id' "$CFG" > "$W/tierids.txt"
# promovidos à mão (overrides add) e, no modo --waitlist, o estado do estágio: chave · escola · país · região
jq -r "$CL_NORM_JQ"'(.preassigned // [])[] | if type == "object" then . else {login:tostring} end
  | [(.login // ""), ((.school // "") | if . == "" then "" else cl_skey end), ((.country // "") | ascii_downcase), ((.region // "") | ascii_downcase)] | join("\t")' "$CFG" > "$W/pre.in"
jq -r "$CL_NORM_JQ"'(.waitlist_state.promoted // [])[] | [(.key // .login // ""), ((.school // "") | if . == "" then "" else cl_skey end), ((.country // "") | ascii_downcase), ((.region // "") | ascii_downcase)] | join("\t")' "$CFG" > "$W/wlstate.tsv"
jq -r '(.waitlist_state.skip // [])[]' "$CFG" > "$W/skip.txt"
read -r N MAXPS HOSTC CAPMODE MS1 MS2 MS3 MS4 WLGR WLLIM WLMS < <(jq -r '[.N, (.max_per_school // 2), (.host_country // "mx"),
  ((.countries // {}).cap // "min_minus_1"), ((.performance // {}).min_solved // 0), ((.countries // {}).min_solved // 1),
  ((.host // {}).min_solved // 0), ((.geo // {}).min_solved // 0), (if (.waitlist // {}).general_rule == false then 0 else 1 end),
  ((.waitlist // {}).limit // 30), ((.waitlist // {}).min_solved // 0)] | map(tostring) | join(" ")' "$CFG")
RE="$(jq -r '.login_regex // "^team([a-z]{2})([a-z]{2})"' "$CFG")"

# --- placar, atributos, femininas --------------------------------------------------------------------------------
cl_rows
awk -F'\t' -v XF="$W/excl.txt" 'BEGIN { while ((getline l < XF) > 0) X[l] = 1; close(XF) } !($3 in X)' "$W/rows.tsv" > "$W/rows2.tsv" \
  && mv -f "$W/rows2.tsv" "$W/rows.tsv"
cl_attrs "$RE" "$W/regcodes.txt" "$W/alias.tsv"; rc=$?
(( rc == 0 )) || exit "$rc"
cl_female "$C" "$(jq -r '.female_node // "Times femininos"' "$CFG")"
# ranking: login · place · total · escola · país · região · time · escola(texto) · faixa feminina — na ordem do placar
awk -F'\t' -v OFS='\t' -v AT="$W/attrs.tsv" -v FE="$W/female.tsv" '
  BEGIN { while ((getline l < AT) > 0) { split(l, a, "\t"); S[a[1]] = a[4]; CY[a[1]] = a[3]; RG[a[1]] = a[2] } close(AT)
          while ((getline l < FE) > 0) { split(l, a, "\t"); F[a[1]] = a[2] } close(FE) }
  ($3 in S) { print $3, $2, ($8 + 0), S[$3], CY[$3], RG[$3], $6, ($5 != "" ? $5 : $7), (($3 in F) ? F[$3] : 0) }' "$W/rows.tsv" > "$W/rank.tsv"

# --- o MOTOR ------------------------------------------------------------------------------------------------------
: > "$W/cls.tsv"; : > "$W/blk.tsv"; : > "$W/geo.tsv"; : > "$W/cp.tsv"; : > "$W/wl.tsv"; : > "$W/info.tsv"; : > "$W/wn.tsv"; : > "$W/pre.tsv"
LC_ALL=C gawk -F'\t' -v OFS='\t' -v MODE="$MODE" -v N="$N" -v MAXPS="$MAXPS" -v HOSTC="$HOSTC" -v CAPMODE="$CAPMODE" \
    -v MS1="$MS1" -v MS2="$MS2" -v MS3="$MS3" -v MS4="$MS4" -v WLGR="$WLGR" -v WLLIM="$WLLIM" -v WLMS="$WLMS" \
    -v RGF="$W/regions.tsv" -v HF="$W/hosts.txt" -v PVF="$W/prev.tsv" -v BKF="$W/blocks.tsv" -v FXF="$W/fixed.tsv" \
    -v CYF="$W/cycle.tsv" -v TRF="$W/tiers.tsv" -v TIF="$W/tierids.txt" -v PRF="$W/pre.in" -v WSF="$W/wlstate.tsv" -v SKF="$W/skip.txt" \
    -v CLF="$W/cls.tsv" -v BLF="$W/blk.tsv" -v GEF="$W/geo.tsv" -v CPF="$W/cp.tsv" -v WLF="$W/wl.tsv" -v INF="$W/info.tsv" \
    -v WNF="$W/wn.tsv" -v POF="$W/pre.tsv" "$PDA_GEO_AWK"'
function promote(i, via, det) {
  PR[i] = via; NSEQ++
  SC[SCH[i]]++; CT[CTY[i]]++; RGN[REG[i]]++
  print NSEQ, via, L[i], P[i], TOT[i], SCH[i], CTY[i], REG[i], RNAME[REG[i]], TEAM[i], UNIV[i], det > CLF
}
function elig(i, gr, ms) {
  if ((i in PR) || (i in PRE)) return 0
  if (TOT[i] < ms) return 0
  if (gr == 1 && SC[SCH[i]] > 0) return 0
  if (gr == 2 && SC[SCH[i]] >= MAXPS) return 0
  return 1
}
# filtro do bloco (globais): FW = mínimo de competidoras; FS = escopo (all|host_country|host_school|region|country);
# FV = região/país do escopo
function okf(i) {
  if (FW > 0 && FB[i] < FW) return 0
  if (FS == "host_country" && CTY[i] != HOSTC) return 0
  if (FS == "host_school" && !(SCH[i] in HOSTS)) return 0
  if (FS == "region" && REG[i] != FV) return 0
  if (FS == "country" && CTY[i] != FV) return 0
  return 1
}
function det(i) { return "#" P[i] (DX != "" ? " · " DX : "") }
# melhores `slots` times elegíveis, na ordem do placar; empate na fronteira (o 1º que ficou de fora tem a posição
# do último que entrou) vira aviso
function run_block(id, slots, gr, ms,    used, i, last, j) {
  used = 0; last = 0
  for (i = 1; i <= n && used < slots; i++) {
    if (!elig(i, gr, ms) || !okf(i)) continue
    promote(i, id, det(i)); used++; last = i
  }
  if (slots > 0 && used == slots && last)
    for (j = last + 1; j <= n; j++) { if (!elig(j, gr, ms) || !okf(j)) continue
      if (P[j] == P[last]) print "tie_boundary", id, P[last], L[last], L[j] > WNF
      break }
  return used
}
function block_rec(id, type, slots, used) { print id, type, slots, used > BLF }
function tier_match(t, i) { return ((TID[t] SUBSEP "s" SUBSEP SCH[i]) in TM) || ((TID[t] SUBSEP "c" SUBSEP CTY[i]) in TM) }
function waitlist(    t, i, cnt) {
  cnt = 0
  for (t = 1; t <= NT && cnt < WLLIM; t++)
    for (i = 1; i <= n && cnt < WLLIM; i++) {
      if ((i in PR) || (i in PRE) || (L[i] in SKIP) || (i in WLD)) continue
      if (TOT[i] < WLMS || !tier_match(t, i)) continue
      if (WLGR && (SC[SCH[i]] > 0 || (SCH[i] in WLS))) continue
      cnt++; WLD[i] = 1; if (WLGR) WLS[SCH[i]] = 1
      print cnt, TID[t], L[i], P[i], TOT[i], SCH[i], CTY[i], REG[i], RNAME[REG[i]], TEAM[i], UNIV[i] > WLF
    }
}
BEGIN {
  while ((getline l < RGF) > 0) { split(l, a, "\t"); NRG++; RC[NRG] = a[1]; RNAME[a[1]] = a[2] } close(RGF)
  while ((getline l < HF) > 0) if (l != "") { HOSTS[l] = 1; NHOST++ } close(HF)
  while ((getline l < PVF) > 0) { split(l, a, "\t"); PREV[a[1]] = a[2] + 0 } close(PVF)
  while ((getline l < BKF) > 0) { nb++; split(l, a, "\t"); BID[nb] = a[1]; BTY[nb] = a[2]; BSL[nb] = a[3] + 0; BSC[nb] = a[4]
    BW[nb] = a[5] + 0; BMS[nb] = a[6] + 0; BGR[nb] = a[7] + 0; BQ[nb] = a[8] } close(BKF)
  while ((getline l < FXF) > 0) { nfx++; FXL[nfx] = l } close(FXF)
  while ((getline l < CYF) > 0) { split(l, a, "\t"); CYC[a[1], a[2]] = 1; CYT[a[1], a[2]] = a[3] + 0; CYI[a[1], a[2]] = a[4] + 0; CYN[a[1]]++; CYK[a[1], CYN[a[1]]] = a[2] } close(CYF)
  while ((getline l < TIF) > 0) if (l != "") { NT++; TID[NT] = l } close(TIF)
  while ((getline l < TRF) > 0) { split(l, a, "\t"); TM[a[1], a[2], a[3]] = 1 } close(TRF)
  while ((getline l < SKF) > 0) if (l != "") SKIP[l] = 1; close(SKF)
}
{ n++; L[n] = $1; P[n] = $2 + 0; TOT[n] = $3 + 0; SCH[n] = $4; CTY[n] = $5; REG[n] = $6; TEAM[n] = $7; UNIV[n] = $8; FB[n] = $9 + 0
  IDX[$1] = n; CPART[$5] = 1
  if (!(($6 SUBSEP $4) in SEENRS)) { SEENRS[$6, $4] = 1; NS[$6]++ }
  CPT[$5]++; if (!(($5 SUBSEP $4) in SEENCS)) { SEENCS[$5, $4] = 1; CPI[$5]++ } }
END {
  # promovidos ANTES do cálculo: overrides add (modo normal) ou o estado do estágio (modo --waitlist)
  src = (MODE == "waitlist") ? WSF : PRF
  while ((getline l < src) > 0) { split(l, a, "\t"); k = a[1]; if (k == "") continue
    if (k in IDX) { i = IDX[k]; if ((i in PRE) || (i in PR)) continue; PRE[i] = 1; SC[SCH[i]]++; CT[CTY[i]]++; RGN[REG[i]]++
      if (MODE != "waitlist") print L[i], P[i], TOT[i], SCH[i], CTY[i], REG[i], RNAME[REG[i]], TEAM[i], UNIV[i] > POF }
    else { if (a[2] != "") SC[a[2]]++; if (a[3] != "") CT[a[3]]++; if (a[4] != "") RGN[a[4]]++ } }
  close(src)
  if (MODE == "waitlist") { waitlist(); exit }

  # ---- P1 desempenho: N/2, ≤ MAXPS por escola ----
  FS = "all"; FW = 0; DX = ""
  u1 = run_block("p1", int(N / 2), 2, MS1); block_rec("p1", "performance", int(N / 2), u1)
  # ---- P2 países: teto calculado UMA vez; vaga a vaga ao melhor time de país sem time (≥ MS2) ----
  X = 0; for (c in CPART) if (CT[c] == 0) X++
  q4 = int(N / 4)
  if (CAPMODE == "min_of_x_minus_1") cap = (q4 < X - 1) ? q4 : X - 1
  else cap = ((q4 < X) ? q4 : X) - 1
  if (cap < 0) cap = 0
  u2 = 0
  for (k = 1; k <= cap; k++) {
    got = 0
    for (i = 1; i <= n; i++) { if (!elig(i, 1, MS2) || CT[CTY[i]] > 0) continue
      DX = toupper(CTY[i]); promote(i, "p2", det(i)); got = 1; break }
    if (!got) break
    u2++
  }
  DX = ""
  block_rec("p2", "countries", cap, u2)
  print "countries", X, cap, u2 > INF
  for (c in CPART) if (CT[c] == 0) { has = 0; for (i = 1; i <= n; i++) if (CTY[i] == c && TOT[i] >= MS2) { has = 1; break }
    if (!has) print "zero_solved", c > INF }
  # ---- P3 instituição-sede: se nenhuma escola-sede tem time, 1 vaga ao melhor de QUALQUER escola sem time ----
  u3 = 0
  if (NHOST == 0) { print "host_schools_empty" > WNF; print "host", "", 0 > INF }
  else {
    cond = 1; for (h in HOSTS) if (SC[h] > 0) cond = 0
    if (cond) { FS = "all"; u3 = run_block("p3", 1, 1, MS3) }
    print "host", cond, u3 > INF
    if (!cond) print "host_condition_false" > WNF
  }
  block_rec("p3", "host", (NHOST > 0 && cond) ? 1 : 0, u3)
  # ---- P4 geográfica ----
  alloc0 = u1 + u2 + u3
  if (alloc0 >= N) print "geo_no_room", alloc0, N > WNF
  galloc = geo_alloc(N, alloc0)
  if (GSTUCK) print "geo_stuck", galloc, N > WNF
  if (GOVER > 0) print "geo_tie_overflow", GOVER > WNF
  print "geo", GNL, GREM, alloc0, galloc, GOVER > INF
  u4 = 0; s4 = 0
  for (r = 1; r <= NRG; r++) { c = RC[r]
    FS = "region"; FV = c; DX = RNAME[c]
    fl = run_block("p4", GS[c], 1, MS4); u4 += fl; s4 += GS[c]
    if (fl < GS[c]) print "geo_unfilled", c, GS[c], fl > WNF
    print c, NS[c] + 0, GQ[c], GN[c], GE[c], GS[c], fl, sprintf("%.12g", GFP[c]), sprintf("%.12g", GF2[c]), sprintf("%.12g", FR[c]) > GEF }
  FS = "all"; FV = ""; DX = ""
  block_rec("p4", "geo", s4, u4)
  # ---- femininas padrão + blocos da edição, na ordem ----
  for (b = 1; b <= nb; b++) {
    id = BID[b]; ty = BTY[b]; used = 0; slots = BSL[b]
    if (ty == "female") {
      FW = BW[b]
      if (BSC[b] == "per_region") {
        slots = 0
        for (r = 1; r <= NRG; r++) { FS = "region"; FV = RC[r]; DX = RNAME[RC[r]]
          g = run_block(id, BSL[b], 0, BMS[b]); used += g; slots += BSL[b]
          if (g < BSL[b]) print "female_unfilled", id, RC[r], BSL[b], g > WNF }
      } else {
        if (BSC[b] == "host_school" && NHOST == 0) print "host_schools_empty", id > WNF
        FS = (BSC[b] == "latam") ? "all" : BSC[b]; DX = (BSC[b] == "host_country") ? toupper(HOSTC) : ""
        used = run_block(id, slots, 0, BMS[b])
        if (used < slots) print "female_unfilled", id, "", slots, used > WNF
      }
      FW = 0; FS = "all"; FV = ""; DX = ""
    } else if (ty == "fixed") {
      slots = 0
      for (x = 1; x <= nfx; x++) { split(FXL[x], fx, "\t"); if (fx[1] != id) continue
        slots++; used++; NSEQ++
        if (fx[8] == 1) { if (fx[5] != "") SC[fx[5]]++; if (fx[6] != "") CT[fx[6]]++; if (fx[7] != "") RGN[fx[7]]++ }
        print NSEQ, id, "ext:" fx[2], "", "", fx[5], fx[6], fx[7], (fx[7] in RNAME ? RNAME[fx[7]] : ""), fx[3], fx[4], "" > CLF }
    } else if (ty == "host_school") {
      if (NHOST == 0) print "host_schools_empty", id > WNF
      FS = "host_school"; used = run_block(id, slots, BGR[b], BMS[b]); FS = "all"
    } else if (ty == "country_participation") {
      # ranking de países: a tabela do RCD (times do ciclo, desempate por instituições); vazia = contagens do contest
      nq = split(BQ[b], Q, ","); m = 0; delete CC
      if (CYN[id] > 0) { srcp = "config"; for (k = 1; k <= CYN[id]; k++) { m++; CC[m] = CYK[id, k]; CTm[m] = CYT[id, CC[m]]; CIm[m] = CYI[id, CC[m]] } }
      else { srcp = "contest"; print "cycle_table_empty", id > WNF
        for (c in CPART) { m++; CC[m] = c; CTm[m] = CPT[c] + 0; CIm[m] = CPI[c] + 0 } }
      for (x = 2; x <= m; x++) for (y = x; y > 1; y--) {     # ordem: times ↓, instituições ↓, código ↑
        p = y - 1
        if (CTm[y] > CTm[p] || (CTm[y] == CTm[p] && (CIm[y] > CIm[p] || (CIm[y] == CIm[p] && CC[y] < CC[p])))) {
          t = CC[y]; CC[y] = CC[p]; CC[p] = t; t = CTm[y]; CTm[y] = CTm[p]; CTm[p] = t; t = CIm[y]; CIm[y] = CIm[p]; CIm[p] = t }
        else break }
      slots = 0
      for (x = 1; x <= m; x++) {
        qx = (x <= nq) ? Q[x] + 0 : 0
        if (x <= nq && x < m && CTm[x] == CTm[x + 1] && CIm[x] == CIm[x + 1] && (Q[x] + 0) != ((x + 1 <= nq) ? Q[x + 1] + 0 : 0))
          print "cycle_tie", id, CC[x], CC[x + 1] > WNF
        g = 0
        if (qx > 0) { FS = "country"; FV = CC[x]; DX = toupper(CC[x]); g = run_block(id, qx, 1, BMS[b]); slots += qx; used += g
          if (g < qx) print "country_quota_unfilled", id, CC[x], qx, g > WNF }
        print id, srcp, x, CC[x], CTm[x], CIm[x], qx, g > CPF
      }
      FS = "all"; FV = ""; DX = ""
    } else if (ty == "reserve") {
      print "reserve", id, slots > INF
    }
    block_rec(id, ty, slots, used)
  }
  waitlist()
}' "$W/rank.tsv" || { echo "classify-pda: o motor falhou" >&2; exit 1; }

# --- JSON ---------------------------------------------------------------------------------------------------------
if [[ "$MODE" == waitlist ]]; then
  jq -Rn --rawfile wl "$W/wl.tsv" '{waitlist: ($wl | split("\n") | map(select(length > 0) | split("\t")
    | {pos:(.[0] | tonumber), tier:.[1], login:.[2], place:(.[3] | tonumber), total:(.[4] | tonumber), school:.[5], country:.[6],
       region:.[7], sede:.[8], team:.[9], univ:.[10]}))}' > "$OUT"
  exit 0
fi
jq -n --arg contest "$C" --slurpfile cfg "$CFG" --rawfile cls "$W/cls.tsv" --rawfile blk "$W/blk.tsv" --rawfile geo "$W/geo.tsv" \
   --rawfile cp "$W/cp.tsv" --rawfile wl "$W/wl.tsv" --rawfile inf "$W/info.tsv" --rawfile wn "$W/wn.tsv" --rawfile pre "$W/pre.tsv" \
   --rawfile rg "$W/regions.tsv" --slurpfile w0 <(cl_warnings_json) '
  def rows($t): $t | split("\n") | map(select(length > 0) | split("\t"));
  def num: if . == "" or . == null then null else tonumber end;
  ($cfg[0]) as $C
  | (rows($rg) | map({key:.[0], value:.[1]}) | from_entries) as $RN
  | (rows($cls) | map({seq:(.[0] | tonumber), via:.[1], login:.[2], place:(.[3] | num), total:(.[4] | num), school:.[5], country:.[6],
                       region:.[7], sede:.[8], team:.[9], univ:.[10], detail:.[11]}
                      | with_entries(select(.value != null and .value != "")))) as $list
  | (rows($blk) | map({id:.[0], type:.[1], slots:(.[2] | tonumber), used:(.[3] | tonumber)})) as $blocks
  | (rows($inf)) as $I
  | ([ $C.female // [], $C.edition_blocks // [] ] | add | map(select(.label != null) | {key:.id, value:.label}) | from_entries) as $labels
  | ([ "p1", "p2", "p3", "p4" ] + ([ $C.female // [], $C.edition_blocks // [] ] | add | map(select(.type != "reserve") | .id))) as $order
  | (rows($wn) | map(. as $w | {code:$w[0]} + (
        if $w[0] == "tie_boundary" then {data:{block:$w[1], place:($w[2] | tonumber), last:$w[3], next:$w[4]}}
        elif $w[0] == "geo_unfilled" then {data:{region:$w[1], slots:($w[2] | tonumber), filled:($w[3] | tonumber)}}
        elif $w[0] == "geo_tie_overflow" then {data:{overflow:($w[1] | tonumber)}}
        elif $w[0] == "geo_no_room" or $w[0] == "geo_stuck" then {data:{allocated:($w[1] | tonumber), N:($w[2] | tonumber)}}
        elif $w[0] == "female_unfilled" then {data:({block:$w[1], slots:($w[3] | tonumber), filled:($w[4] | tonumber)} + (if $w[2] != "" then {region:$w[2]} else {} end))}
        elif $w[0] == "country_quota_unfilled" then {data:{block:$w[1], country:$w[2], quota:($w[3] | tonumber), filled:($w[4] | tonumber)}}
        elif $w[0] == "cycle_tie" then {data:{block:$w[1], countries:[$w[2], $w[3]]}}
        elif $w[0] == "cycle_table_empty" or $w[0] == "host_schools_empty" then (if ($w[1] // "") != "" then {data:{block:$w[1]}} else {} end)
        else {} end))) as $wn2
  | (rows($geo) | map({code:.[0], name:$RN[.[0]], schools:(.[1] | tonumber), q:(.[2] | tonumber), nslots:(.[3] | tonumber),
                       extra:(.[4] | tonumber), slots:(.[5] | tonumber), filled:(.[6] | tonumber), fraction_prev:(.[7] | tonumber),
                       fraction:(.[8] | tonumber), fraction_out:(.[9] | tonumber)})) as $georows
  | (first($I[] | select(.[0] == "geo")) // null) as $g
  | (first($I[] | select(.[0] == "countries")) // ["", "0", "0", "0"]) as $ci
  | (first($I[] | select(.[0] == "host")) // ["", "", "0"]) as $hi
  | {contest:$contest, algorithm:"latam-pda", generated_at:(now | floor), N:$C.N,
     classified:$list, total:($list | length),
     by_rule:($list | group_by(.via) | map({key:.[0].via, value:length}) | from_entries),
     blocks:$blocks,
     unused:($blocks | map(select(.slots > .used and .type != "reserve") | {key:.id, value:(.slots - .used)}) | from_entries),
     countries:{participating_without_team:($ci[1] | tonumber), cap:($ci[2] | tonumber), used:($ci[3] | tonumber),
                zero_solved:[ $I[] | select(.[0] == "zero_solved") | .[1] ] | sort},
     host:{schools:($C.host_schools // []), condition:(if $hi[1] == "" then null else ($hi[1] == "1") end), used:($hi[2] | tonumber)},
     geo:(if $g == null then null else {schools_latam:($g[1] | tonumber), remaining:($g[2] | tonumber), allocated_before:($g[3] | tonumber),
          allocated_after:($g[4] | tonumber), overflow:($g[5] | tonumber), regions:$georows} end),
     fractions_out:($georows | map(select(.fraction_out > 0) | {key:.code, value:.fraction_out}) | from_entries),
     country_participation:(rows($cp) | group_by(.[0]) | map({key:.[0][0], value:{source:.[0][1],
         ranking:map({rank:(.[2] | tonumber), country:.[3], teams:(.[4] | tonumber), institutions:(.[5] | tonumber),
                      quota:(.[6] | tonumber), filled:(.[7] | tonumber)})}}) | from_entries),
     reserve:{slots:([ $I[] | select(.[0] == "reserve") | .[2] | tonumber ] | add // 0)},
     waitlist:(rows($wl) | map({pos:(.[0] | tonumber), tier:.[1], login:.[2], place:(.[3] | tonumber), total:(.[4] | tonumber),
                                school:.[5], country:.[6], region:.[7], sede:.[8], team:.[9], univ:.[10]})),
     pre:(rows($pre) | map({login:.[0], place:(.[1] | tonumber), total:(.[2] | tonumber), school:.[3], country:.[4], region:.[5],
                            sede:.[6], team:.[7], univ:.[8]})),
     labels:$labels, via_order:$order,
     warnings:(($w0[0] // []) + $wn2)}' > "$OUT"
