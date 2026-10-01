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
#   r3/comitê e redistribuição: MANUAIS (handler add) — aqui só sai o `unused` por regra.
set -u
C="${1:-}"; CFG="${2:-}"; OUT="${3:-/dev/stdout}"
[[ -n "$C" && -s "$CFG" ]] || { echo "uso: classify-br.sh <contest> <config.json> [out]" >&2; exit 1; }
# o comum aos motores: o placar pelo CABEÇALHO (até 30/09/2026 este motor contava as colunas do FIM, com
# `$NF` = guest — sem coorte unranked não há coluna guest, e ele lia o total errado e descartava quem tinha
# LastAC=1), a pertença das femininas e os avisos
source "$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/classify-common.sh"
cl_init "$C" || exit 1
[[ -s "$CD/regions.json" ]] || { echo "classify-br: sem regions.json" >&2; exit 1; }
REGION="$(jq -r '.region // "Brasil"' "$CFG")"

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
R1="$(jq -r '.r1 // 15' "$CFG")"
F3="$(jq -r '.r4.f3 // 3' "$CFG")"; F2="$(jq -r '.r4.f2 // 2' "$CFG")"; F1="$(jq -r '.r4.f1 // 1' "$CFG")"

# --- ranking da REGIÃO (place de COMPETIÇÃO recontado na região; sem convidado) -----------
cl_rows
awk -F'\t' '$3 == "1" { print $1 }' "$W/sites.tsv" > "$W/inr.txt"
cl_subset_places "$W/rows.tsv" "$W/inr.txt" | awk -F'\t' '{ print $2 "\t" $3 "\t" $5 "\t" $6 "\t" ($8 + 0) }' > "$W/rank.tsv"

# --- o MOTOR (awk: estado sequencial das regras) ------------------------------------------
awk -F'\t' -v R1="$R1" -v F3="$F3" -v F2="$F2" -v F1="$F1" \
    -v SF="$W/super.tsv" -v CS="$W/cfg-sedes.tsv" \
    -v CU="$W/cfg-super.tsv" -v FEMF="$W/fem.tsv" -v STF="$W/sites.tsv" '
BEGIN{
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
    if (!eligible(i)) continue
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
   --rawfile cls "$W/classified.tsv" --rawfile uns "$W/unused.tsv" --slurpfile wn <(cl_warnings_json) '
  ($cls | split("\n") | map(select(length>0) | split("\t"))
        | map({via:.[0], login:.[1], team:.[2], univ:.[3], sede:.[4],
               place:(.[5]|tonumber), total:(.[6]|tonumber), detail:.[7]})) as $list
  | ($uns | split("\n") | map(select(length>0) | split("\t"))
          | map({key:.[1], value:(.[2]|tonumber)}) | from_entries) as $unused
  | { contest:$contest, region:$region, generated_at:(now|floor),
      classified:($list | sort_by(.place)),
      by_rule:($list | group_by(.via) | map({key:.[0].via, value:length}) | from_entries),
      total:($list|length), unused:$unused, warnings:($wn[0] // []) }' > "$OUT"
