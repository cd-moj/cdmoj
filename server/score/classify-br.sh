#!/usr/bin/env bash
#
# classify-br.sh <contest> <config.json> [outfile]
#
# Motor das regras de classificação da 1ª FASE → FINAL BRASILEIRA (regulamento SBC),
# aplicadas EM ORDEM sobre o placar COMPLETO (var/placar-full.txt) + regions.json.
# Standalone (molde do report-gen): não é sourced pela API — o handler o executa.
# Emite JSON em outfile (ou stdout): NUNCA grava nada no contest (preview puro; quem
# persiste é o handler admin/classify no `apply`).
#
# config.json:
#   { region:"Brasil",                    # nó de 1º nível do regions.json
#     r1:15,                              # vagas da regra 1 (melhores gerais, ≤2/escola)
#     r4:{f3:3, f2:2, f1:1},              # vagas femininas (3♀ / ≥2♀ / ≥1♀)
#     sedes:{"SP, São Paulo":3, ...},     # vagas regra 2 por sede NORMAL
#     supersedes:{"Supersede da região Norte":1, ...} }  # vagas por supersede (≤1/sede membra)
#
# Regras (ver docs/CLASSIFICACAO.md):
#   r0: elegível = Total≥3, OU campeão da sede (1º dela no ranking) com Total≥2.
#   r1: caminha o ranking; ≤2 por ESCOLA (univ short); até r1 vagas.
#   r2: sede normal: melhores N da sede; supersede: melhores K entre as membras com ≤1 por
#       sede membra. Ambos: ≤1 por escola nesta regra E escola com time na r1 NÃO entra.
#   r4: femininas pelas listas /Times femininos/{3,2,1} do regions.json (BR): 3 melhores
#       com 3♀ → 2 com ≥2♀ → 1 com ≥1♀; sem limite de escola; não repete classificado.
#   r3/comitê e redistribuição: MANUAIS (overrides do handler) — aqui só sai o `unused` por regra.
#
# Overrides (o handler os põe na config; docs/CLASSIFICACAO.md, "Override manual"):
#   exclude:[login|{login,reason}]   — o time sai do cálculo (nem conta como campeão da sede);
#   preassigned:[{login,via}]        — já promovido à mão: o motor o pula (não lhe dá outra vaga) e não o
#                                      conta no limite de escola de regra nenhuma; sai em `pre` com os
#                                      dados do placar (posição, total, escola, sede).
#
# classify-br.sh --check <config.json> — só valida a config: rc 0, ou rc 2 com {errors:[…]} no stderr.
set -u
if [[ "${1:-}" == --check ]]; then
  [[ -s "${2:-}" ]] || { echo '{"errors":["config vazia"]}' >&2; exit 2; }
  errs="$(jq -c '
    def nonneg_int: type == "number" and . >= 0 and floor == .;
    def slots: type == "object" and all(.[]; nonneg_int);
    [ if type != "object" then "a config tem de ser um objeto {region, r1, r4, sedes, supersedes}" else
        (if has("region") and (.region | type) != "string" then "region: texto (nó de 1º nível do regions.json)" else empty end),
        (if has("r1") and ((.r1 | nonneg_int) | not) then "r1: inteiro ≥ 0" else empty end),
        (if has("r4") and ((.r4 | type == "object" and all(to_entries[]; (.key | test("^f[123]$")) and (.value | nonneg_int))) | not)
         then "r4: {f3, f2, f1} com inteiros ≥ 0" else empty end),
        (if has("sedes") and ((.sedes | slots) | not) then "sedes: {\"Sede\": vagas (inteiro ≥ 0)}" else empty end),
        (if has("supersedes") and ((.supersedes | slots) | not) then "supersedes: {\"Supersede\": vagas (inteiro ≥ 0)}" else empty end),
        (if has("exclude") and (.exclude | type) != "array" then "exclude: lista" else empty end),
        (if has("preassigned") and (.preassigned | type) != "array" then "preassigned: lista" else empty end)
      end ]' "$2" 2>/dev/null)" || errs='["config não é JSON válido"]'
  [[ "$errs" == "[]" ]] && exit 0
  jq -cn --argjson e "$errs" '{errors:$e}' >&2; exit 2
fi
C="${1:-}"; CFG="${2:-}"; OUT="${3:-/dev/stdout}"
[[ -n "$C" && -s "$CFG" ]] || { echo "uso: classify-br.sh <contest> <config.json> [out]" >&2; exit 1; }
bash "$0" --check "$CFG" || exit 2
# o comum aos motores: o placar pelo CABEÇALHO (até 30/09/2026 este motor contava as colunas do FIM, com
# `$NF` = guest — sem coorte unranked não há coluna guest, e ele lia o total errado e descartava quem tinha
# LastAC=1), a pertença das femininas e os avisos
source "$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/classify-common.sh"
cl_init "$C" || exit 1
[[ -s "$CD/regions.json" ]] || { echo "classify-br: sem regions.json" >&2; exit 1; }
REGION="$(jq -r '.region // "Brasil"' "$CFG")"

# a REGIÃO tem de ser um nó de 1º nível do regions.json: sem ele ninguém entra e a classificação saía VAZIA, calada
# (auditoria do painel, 03/10/2026) — agora é erro de config com os nós que existem
if ! jq -e --arg R "$REGION" 'any(.[]; .name == $R)' "$CD/regions.json" >/dev/null 2>&1; then
  jq -cn --arg R "$REGION" --slurpfile g "$CD/regions.json" \
    '{errors:["region: \"" + $R + "\" não existe no 1º nível do regions.json (há: " + ([$g[0][] | .name] | join(", ")) + ")"]}' >&2
  exit 2
fi
# supersedes (nome → sedes membras) — filhos dos nós cujo nome está em config.supersedes
jq -r --arg R "$REGION" '
  .[] | select(.name == $R) | (.subregions // [])[]
  | select((.subregions // [])|length > 0)
  | .name as $sn | (.subregions // [])[] | [$sn, .name] | @tsv
' "$CD/regions.json" > "$W/super.tsv"
# listas femininas (categoria \t login): PERTENÇA aos recortes "Times femininos" › 3/2/1 (cl_female) — a
# faixa é a MAIOR; f3 = 3 competidoras, e as regras abaixo testam "≥" (f3 ou f2…), então basta ela
cl_female "$C" "Times femininos"
awk -F'\t' '{ print "f" $2 "\t" $1 }' "$W/female.tsv" | sort -u > "$W/fem.tsv"

# --- sede e região pela regra ÚNICA (lib/regions.sh) ------------------------------------------
# Quem está na REGIÃO = pertença ao nó da região (1º nó do topo, não-recorte, com esse nome); a SEDE de
# cada time = a sede canônica (a gravada vence; senão a regex mais funda) — "parou no pai" = sem sede.
# Até 28/09/2026: a regex do nó da região (diferenciando maiúsculas) e a 1ª folha pela regex, ignorando a
# sede gravada. A auditoria (server/bin/regions-audit.sh › CLASSIFICAÇÃO) mostrou zero diferença na LATAM.
source "$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/../api/v1/lib/regions.sh"
: > "$W/sites.tsv"
if RGM="$(rg_map "$C" 2>/dev/null)"; then
  jq -Rrn --slurpfile n "$CD/var/regions-nodes.json" --arg R "$REGION" '
    (first($n[0][] | select(.depth == 0 and (.view | not) and .name == $R) | .i) // -1) as $ri
    | inputs | split("\t") | (.[1] | tonumber) as $s
    | [ .[0], (if $s >= 0 and .[3] != "p" then $n[0][$s].name else "" end),
        (if $ri >= 0 and ((.[2] | split(",")) | index($ri | tostring)) != null then "1" else "0" end) ] | join("\t")' \
    "$RGM" > "$W/sites.tsv" 2>/dev/null || : > "$W/sites.tsv"
fi

# --- config → TSVs ------------------------------------------------------------------------
jq -r '(.sedes // {}) | to_entries[] | [.key, (.value|tostring)] | @tsv' "$CFG" > "$W/cfg-sedes.tsv"
jq -r '(.supersedes // {}) | to_entries[] | [.key, (.value|tostring)] | @tsv' "$CFG" > "$W/cfg-super.tsv"
# sede/supersede com vaga na config que NÃO existe na árvore: a vaga não ia a ninguém, calada — vira aviso
miss_s="$(jq -c --slurpfile g "$CD/regions.json" '[ $g[0] | .. | objects | select(has("name")) | .name ] as $all
  | [ (.sedes // {}) | keys[] | select(. as $k | $all | index($k) | not) ]' "$CFG" 2>/dev/null)"
[[ -n "$miss_s" && "$miss_s" != "[]" ]] && cl_warn sede_missing "$(jq -cn --argjson l "$miss_s" '{sites:$l}')"
miss_u="$(jq -c --slurpfile g "$CD/regions.json" --arg R "$REGION" '[ $g[0][] | select(.name == $R) | (.subregions // [])[] | .name ] as $all
  | [ (.supersedes // {}) | keys[] | select(. as $k | $all | index($k) | not) ]' "$CFG" 2>/dev/null)"
[[ -n "$miss_u" && "$miss_u" != "[]" ]] && cl_warn supersede_missing "$(jq -cn --argjson l "$miss_u" '{sites:$l}')"
R1="$(jq -r '.r1 // 15' "$CFG")"
F3="$(jq -r '.r4.f3 // 3' "$CFG")"; F2="$(jq -r '.r4.f2 // 2' "$CFG")"; F1="$(jq -r '.r4.f1 // 1' "$CFG")"

# --- ranking da REGIÃO (place de COMPETIÇÃO recontado na região; sem convidado) -----------
cl_rows
# overrides: excluídos saem da região (o ranking se reconta sem eles); preassigned = já promovidos à mão
jq -r '(.exclude // [])[] | if type == "object" then (.login // "") else tostring end | select(length > 0)' "$CFG" > "$W/excl.txt"
jq -r '(.preassigned // [])[] | if type == "object" then (.login // "") else tostring end | select(length > 0)' "$CFG" > "$W/pre.txt"
awk -F'\t' -v XF="$W/excl.txt" 'BEGIN { while ((getline l < XF) > 0) X[l] = 1; close(XF) }
  $3 == "1" && !($1 in X) { print $1 }' "$W/sites.tsv" > "$W/inr.txt"
cl_subset_places "$W/rows.tsv" "$W/inr.txt" | awk -F'\t' '{ print $2 "\t" $3 "\t" $5 "\t" $6 "\t" ($8 + 0) }' > "$W/rank.tsv"

# --- o MOTOR (awk: estado sequencial das regras) ------------------------------------------
awk -F'\t' -v R1="$R1" -v F3="$F3" -v F2="$F2" -v F1="$F1" \
    -v SF="$W/super.tsv" -v CS="$W/cfg-sedes.tsv" \
    -v CU="$W/cfg-super.tsv" -v FEMF="$W/fem.tsv" -v STF="$W/sites.tsv" \
    -v PF="$W/pre.txt" -v PO="$W/pre.tsv" '
BEGIN{
  while ((getline l < PF) > 0) PRE[l]=1
  close(PF)
  printf "" > PO
  while ((getline l < CS) > 0) { split(l, a, "\t"); vsede[a[1]]=a[2]+0 }
  close(CS)
  while ((getline l < CU) > 0) { split(l, a, "\t"); vsuper[a[1]]=a[2]+0 }
  close(CU)
  # sede -> supersede: SÓ pais com vaga no config (uma sede aparece sob o nó regional
  # "Nordeste" E sob "Supersede da região Nordeste" — o que vale é quem tem vaga)
  while ((getline l < SF) > 0) { split(l, a, "\t"); if (a[1] in vsuper) member[a[2]]=a[1] }
  close(SF)
  while ((getline l < FEMF) > 0) { split(l, a, "\t"); fem[a[2], a[1]]=1 }
  close(FEMF)
  while ((getline l < STF) > 0) { split(l, a, "\t"); SEDEOF[a[1]] = a[2] }
  close(STF)
}
{
  n++; place[n]=$1; login[n]=$2; univ[n]=$3; team[n]=$4; tot[n]=$5+0
  # sede canônica (lib/regions.sh); campeão = 1º da sede no ranking
  sd = (login[n] in SEDEOF) ? SEDEOF[login[n]] : ""
  sede[n]=sd
  if (sd != "" && !(sd in champ)) champ[sd]=n
  # já promovido à mão (override add): fora das regras; os dados do placar vão p/ `pre`
  if (login[n] in PRE) { cl[n]="pre"; printf "%s\t%s\t%s\t%s\t%d\t%s\n", login[n], team[n], univ[n], sd, place[n], tot[n] > PO }
}
function eligible(i) {
  if (tot[i] >= 3) return 1
  if (tot[i] >= 2 && sede[i] != "" && champ[sede[i]] == i) return 1
  return 0
}
function out(i, via, det) {
  cl[i]=via
  printf "%s\t%s\t%s\t%s\t%s\t%d\t%s\t%s\n", via, login[i], team[i], univ[i], sede[i], place[i], tot[i], det
}
END{
  # ---- regra 1: melhores gerais, ≤2 por escola -----------------------------------------
  used=0
  for (i=1; i<=n && used<R1; i++) {
    if (cl[i] != "" || !eligible(i)) continue
    if (schoolR1[univ[i]] >= 2) continue
    schoolR1[univ[i]]++; schoolHasR1[univ[i]]=1
    used++; out(i, "regra1", "#" place[i] " geral")
  }
  print "UNUSED\tregra1\t" (R1-used) > "/dev/stderr"
  # ---- regra 2: sedes normais ----------------------------------------------------------
  for (i=1; i<=n; i++) {
    if (cl[i] != "" || !eligible(i)) continue
    sd=sede[i]
    if (!(sd in vsede) || vsede[sd] <= 0) continue
    if (schoolHasR1[univ[i]] || schoolR2[univ[i]] >= 1) continue
    vsede[sd]--; schoolR2[univ[i]]++
    out(i, "regra2", "sede " sd)
  }
  for (sd in vsede) if (vsede[sd] > 0) u2 += vsede[sd]
  # ---- regra 2: supersedes (≤1 por sede membra) ----------------------------------------
  for (i=1; i<=n; i++) {
    if (cl[i] != "" || !eligible(i)) continue
    sd=sede[i]
    if (!(sd in member)) continue
    sp=member[sd]
    if (!(sp in vsuper) || vsuper[sp] <= 0) continue
    if (sedeSuper[sd]) continue
    if (schoolHasR1[univ[i]] || schoolR2[univ[i]] >= 1) continue
    vsuper[sp]--; sedeSuper[sd]=1; schoolR2[univ[i]]++
    out(i, "regra2", sp " (sede " sd ")")
  }
  for (sp in vsuper) if (vsuper[sp] > 0) u2 += vsuper[sp]
  print "UNUSED\tregra2\t" u2+0 > "/dev/stderr"
  # ---- regra 4: femininas (3♀ → ≥2♀ → ≥1♀); sem limite de escola -----------------------
  u4=0
  q=F3; for (i=1; i<=n && q>0; i++) if (cl[i]=="" && eligible(i) && fem[login[i],"f3"]) { q--; out(i, "regra4", "3 mulheres") }
  u4+=q
  q=F2; for (i=1; i<=n && q>0; i++) if (cl[i]=="" && eligible(i) && (fem[login[i],"f3"] || fem[login[i],"f2"])) { q--; out(i, "regra4", "2+ mulheres") }
  u4+=q
  q=F1; for (i=1; i<=n && q>0; i++) if (cl[i]=="" && eligible(i) && (fem[login[i],"f3"] || fem[login[i],"f2"] || fem[login[i],"f1"])) { q--; out(i, "regra4", "participação feminina") }
  u4+=q
  print "UNUSED\tregra4\t" u4 > "/dev/stderr"
}' "$W/rank.tsv" > "$W/classified.tsv" 2> "$W/unused.tsv"

# --- JSON final ---------------------------------------------------------------------------
jq -Rn --arg region "$REGION" --arg contest "$C" \
   --rawfile cls "$W/classified.tsv" --rawfile uns "$W/unused.tsv" --rawfile pre "$W/pre.tsv" \
   --slurpfile wn <(cl_warnings_json) '
  ($cls | split("\n") | map(select(length>0) | split("\t"))
        | map({via:.[0], login:.[1], team:.[2], univ:.[3], sede:.[4],
               place:(.[5]|tonumber), total:(.[6]|tonumber), detail:.[7]})) as $list
  | ($uns | split("\n") | map(select(length>0) | split("\t"))
          | map({key:.[1], value:(.[2]|tonumber)}) | from_entries) as $unused
  | ($pre | split("\n") | map(select(length>0) | split("\t"))
          | map({login:.[0], team:.[1], univ:.[2], sede:.[3], place:(.[4]|tonumber), total:(.[5]|tonumber)})) as $prel
  | { contest:$contest, region:$region, generated_at:(now|floor),
      classified:($list | sort_by(.place)),
      by_rule:($list | group_by(.via) | map({key:.[0].via, value:length}) | from_entries),
      total:($list|length), unused:$unused, pre:$prel, warnings:($wn[0] // []) }' > "$OUT"
