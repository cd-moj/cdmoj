#!/bin/bash
# regions-audit.sh <contest> [--examples N] — O QUE MUDA com a regra única de sedes (lib/regions.sh), ANTES
# de os consumidores migrarem. Só lê; o único arquivo escrito é o cache var/regions-{nodes.json,map.tsv}.
#
# Compara a regra NOVA com as antigas que ainda estão no ar (emuladas aqui no gawk; a regex é a CRUA do
# regions.json, como os consumidores antigos a usam — as árvores reais só usam ^(a|b)[0-9], em que jq, JS e
# ERE concordam):
#   SEDE de cada login:
#     gate/materialize — gravada vence; senão o 1º nó em PRÉ-ORDEM (recorte incluso) cuja regex casa, sem
#                        diferenciar maiúsculas (o pai vence a folha);
#     etiquetas        — gravada vence; senão o 1º nó do TOPO cuja regex casa (diferencia maiúsculas).
#   MEMBROS de cada nó:
#     placar (filtro)  — a regex do próprio nó casa (sem maiúsculas) OU a gravada tem o nome dele;
#     estatística      — idem, diferenciando maiúsculas na regex.
#   CLASSIFICAÇÃO (score/classify-br.sh, região = config.region, padrão "Brasil"): quem entra no ranking da
#     região (a regex do nó da região, diferenciando maiúsculas) e a sede de cada um (a 1ª FOLHA não-recorte
#     da região cuja regex casa — a sede GRAVADA é ignorada) × o NOVO (pertença ao nó da região; a sede
#     canônica).
#   QUEM O STAFF VÊ (print-requests/staff-filters.json): `region:<nome>` =
#     etiquetas (senha!) — o nome é o da sede gravada OU a derivada das etiquetas;
#     impressão/fila   — o nome é o da sede GRAVADA;
#     NOVO             — o login está em algum nó com esse nome (recorte incluso); entradas regex não mudam.
# Saída: texto p/ gente (a decisão das fases F3), com N exemplos por diferença (padrão 8).
set -u
C="${1:-}"; [[ -n "$C" ]] || { echo "uso: $0 <contest> [--examples N]" >&2; exit 2; }
EX=8; [[ "${2:-}" == --examples ]] && EX="${3:-8}"
REGION="$(jq -r '.config.region // .region // empty' "$CONTESTSDIR/$C/classification.json" 2>/dev/null)"; REGION="${REGION:-Brasil}"
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
source "$HERE/../api/v1/lib/common.sh" 2>/dev/null || true
source "$HERE/../api/v1/lib/regions.sh"
D="$CONTESTSDIR/$C"; [[ -d "$D/users" ]] || { echo "contest sem users/: $D" >&2; exit 1; }
command -v gawk >/dev/null || { echo "gawk ausente" >&2; exit 1; }
rg_build "$C" || { echo "rg_build falhou" >&2; exit 1; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

# nós com a regex CRUA, na MESMA pré-ordem do rg_flatten (mesmos índices)
jq -r 'def flat($d; $v): .[]? | select(type == "object") | (($v or (.view == true))) as $vv
         | [$d, (if $vv then 1 else 0 end), ((.name // "") | tostring | gsub("[\t\n\r]"; " ")), ((.regex // "") | tostring | gsub("[\t\n\r]"; " "))],
           ((.subregions // []) | if type == "array" then flat($d + 1; $vv) else empty end);
       if type == "array" then flat(0; false) | map(tostring) | join("\t") else empty end' "$D/regions.json" 2>/dev/null > "$W/raw.tsv"
jq -r '.[] | [.i, .name, .key, (if .view then 1 else 0 end), (if .orphan then 1 else 0 end)] | map(tostring) | join("\t")' \
  "$D/var/regions-nodes.json" > "$W/new-nodes.tsv"
cp "$D/var/regions-map.tsv" "$W/map.tsv"
find "$D/users" -mindepth 2 -maxdepth 2 -name account.json -print0 | xargs -0 -r jq -r \
  '[(input_filename | split("/") | .[-2]), ((.team.region // "") | tostring | gsub("[\t\n\r]"; " ") | gsub("^ +| +$"; ""))] | join("\t")' \
  > "$W/explicit.tsv" 2>/dev/null
F="$(pr_dir "$C" 2>/dev/null || printf '%s/print-requests' "$D")/staff-filters.json"
if [[ -s "$F" ]]; then jq -r 'to_entries[] | .key as $k | .value[]? | [$k, tostring] | join("\t")' "$F" > "$W/staff.tsv"; else : > "$W/staff.tsv"; fi

gawk -F'\t' -v EX="$EX" -v C="$C" -v REGION="$REGION" '
function lc(s) { gsub(/^ +| +$/, "", s); return tolower(s) }
function addex(k, s) { if (++nex[k] <= EX) exs[k] = exs[k] "\n      " s }
FILENAME == ARGV[1] { n++; dep[n-1] = $1; vw[n-1] = $2; nm[n-1] = $3; rx[n-1] = $4; nv += $2; next }  # nós crus (i = n-1)
FILENAME == ARGV[2] { NN[$1] = $2; NO[$1] = $5; bykey[$3] = ($3 in bykey) ? bykey[$3] "," $1 : $1; next }
FILENAME == ARGV[3] { u++; L[u] = $1; SITE[$1] = $2; FL[$1] = $4; m = split($3, a, ","); for (k = 1; k <= m; k++) MEM[$1, a[k]] = 1; next }
FILENAME == ARGV[4] { EXP[$1] = $2; next }
FILENAME == ARGV[5] { st++; SL[st] = $1; ST[st] = $2; next }
END {
  printf "== %s: %d logins, %d nós (%d recortes) ==\n", C, u, n, nv
  # ⚠ nunca passe a uma função um elemento que pode não existir (lc(EXP[l])): o gawk 5.3 o cria num estado
  # interno que depois aborta ("fixtype: expected Node_val") — sempre `(l in EXP) ? … : ""`
  for (k = 1; k <= u; k++) { l = L[k]; cnt[FL[l]]++; LEXP[l] = (l in EXP) ? lc(EXP[l]) : ""; LNEW[l] = (SITE[l] >= 0) ? lc(NN[SITE[l]]) : "" }
  printf "  NOVO: gravada %d · gravada ÓRFÃ %d · regex numa folha %d · PAROU NO PAI %d · sem sede %d\n", cnt["x"], cnt["o"], cnt["r"], cnt["p"], cnt["-"]
  for (i in NO) if (NO[i] == 1) { norf++; orfs = orfs sprintf(" \"%s\"", NN[i]) }
  if (norf) printf "  sedes órfãs (nome gravado fora da árvore): %d —%s\n", norf, substr(orfs, 1, 600)
  # --- SEDE velha (laço nó × logins: cada regex compila uma vez)
  for (k = 1; k <= u; k++) { l = L[k]; if (LEXP[l] != "") { UG[l] = EXP[l]; BD[l] = EXP[l] } }
  IGNORECASE = 1
  for (i = 0; i < n; i++) { if (rx[i] == "") continue; r = rx[i]
    for (k = 1; k <= u; k++) { l = L[k]; if (!(l in UG) && l ~ r) UG[l] = nm[i] } }
  IGNORECASE = 0
  for (i = 0; i < n; i++) { if (rx[i] == "" || dep[i] != 0) continue; r = rx[i]
    for (k = 1; k <= u; k++) { l = L[k]; if (!(l in BD) && l ~ r) BD[l] = nm[i] } }
  for (k = 1; k <= u; k++) { l = L[k]; LBD[l] = (l in BD) ? lc(BD[l]) : ""; lug = (l in UG) ? lc(UG[l]) : ""
    if (lug != LNEW[l]) { dug++; addex("ug", sprintf("%-22s gate/materialize: %-30s NOVO: %s", l, "\"" UG[l] "\"", "\"" NN[SITE[l]] "\"")) }
    if (LBD[l] != LNEW[l]) { dbd++; addex("bd", sprintf("%-22s etiquetas: %-30s NOVO: %s", l, "\"" BD[l] "\"", "\"" NN[SITE[l]] "\"")) } }
  printf "\n  SEDE mudaria p/ %d login(s) no gate de UA/materialize e p/ %d nas etiquetas%s%s\n", dug, dbd, exs["ug"], exs["bd"]
  # --- MEMBROS por nó: placar (regex sem maiúsculas) e estatística (com) × novo
  for (i = 0; i < n; i++) {
    r = rx[i]; key = lc(nm[i]); o1 = o2 = nw = ad = rm = ad2 = rm2 = 0
    delete SC; delete STT
    IGNORECASE = 1; if (r != "") for (k = 1; k <= u; k++) if (L[k] ~ r) SC[k] = 1
    IGNORECASE = 0; if (r != "") for (k = 1; k <= u; k++) if (L[k] ~ r) STT[k] = 1
    for (k = 1; k <= u; k++) {
      l = L[k]; byname = (LEXP[l] != "" && LEXP[l] == key)
      sc = byname || (k in SC); stt = byname || (k in STT); nwv = ((l, i) in MEM)
      o1 += sc; o2 += stt; nw += nwv
      if (nwv && !sc) ad++; if (sc && !nwv) rm++; if (nwv && !stt) ad2++; if (stt && !nwv) rm2++
    }
    lab = (vw[i] ? "[recorte] " : "") nm[i] (r == "" ? " (sem regex)" : "")
    if (ad || rm) { dnodes++; addex("nd", sprintf("%-48s placar %4d → NOVO %4d  (+%d −%d)", lab, o1, nw, ad, rm)) }
    if (ad2 || rm2) { dst++; addex("st", sprintf("%-48s estatística %4d → NOVO %4d  (+%d −%d)", lab, o2, nw, ad2, rm2)) }
  }
  printf "\n  MEMBROS: %d nó(s) mudam no filtro do placar, %d na estatística%s%s\n", dnodes, dst, exs["nd"], exs["st"]
  # --- CLASSIFICAÇÃO (classify-br): região + sede = 1ª folha da região pela regex (cs), gravada ignorada
  ri = -1; for (i = 0; i < n; i++) if (dep[i] == 0 && nm[i] == REGION && vw[i] == 0) { ri = i; break }
  if (ri >= 0) {
    nl = 0; seenl[""] = 1
    for (i = ri + 1; i < n && dep[i] > 0; i++) {
      leaf = (i + 1 >= n || dep[i + 1] <= dep[i])
      if (vw[i] == 0 && leaf && rx[i] != "" && !(nm[i] in seenl)) { seenl[nm[i]] = 1; LR[++nl] = rx[i]; LN[nl] = nm[i] }
    }
    for (k = 1; k <= u; k++) {
      l = L[k]; oin = (rx[ri] != "" && l ~ rx[ri]); nin = ((l, ri) in MEM)
      if (oin != nin) { dcin++; addex("ci", sprintf("%-22s na região \"%s\": %s → NOVO %s", l, REGION, (oin ? "sim" : "não"), (nin ? "sim" : "não"))) }
      if (!oin || !nin) continue
      os = ""; for (j = 1; j <= nl; j++) if (l ~ LR[j]) { os = LN[j]; break }
      ns = (FL[l] == "p") ? "" : NN[SITE[l]]            # parou no pai = sem sede p/ a classificação
      if (lc(os) != lc(ns)) { dcs++; addex("cs", sprintf("%-22s sede na classificação: %-26s NOVO: %s", l, "\"" os "\"", "\"" ns "\"")) }
    }
    printf "\n  CLASSIFICAÇÃO (região \"%s\"): %d login(s) entram/saem da região, %d mudam de sede%s%s\n", REGION, dcin, dcs, exs["ci"], exs["cs"]
  } else printf "\n  CLASSIFICAÇÃO: sem nó \"%s\" no topo — nada a comparar\n", REGION
  # --- STAFF: quem cada um vê (region:<nome>; entradas regex valem igual nos três)
  for (x in MEM) { split(x, pp, SUBSEP); LK[pp[1], lc(NN[pp[2]])] = 1 }     # login × nome de nó em que ele está
  for (s = 1; s <= st; s++) { w = SL[s]; who[w] = 1; tk = ST[s]
    if (tk ~ /^region:/) { r = lc(substr(tk, 8)); RSET[w, r] = 1; RK[w] = RK[w] "\t" r; hasreg[w] = 1 } else RX[w] = RX[w] "\t" tk }
  IGNORECASE = 1
  for (w in who) {
    if (!hasreg[w]) continue
    m = split(substr(RX[w], 2), t, "\t"); nk = split(substr(RK[w], 2), kk, "\t"); o_bd = o_pr = o_nw = wide = narrow = 0
    for (k = 1; k <= u; k++) {
      l = L[k]; vx = 0; for (j = 1; j <= m; j++) if (t[j] != "" && l ~ t[j]) { vx = 1; break }
      vb = vx || ((w, LBD[l]) in RSET); vp = vx || (LEXP[l] != "" && (w, LEXP[l]) in RSET); vn = vx
      if (!vn) for (j = 1; j <= nk; j++) if ((l, kk[j]) in LK) { vn = 1; break }
      o_bd += vb; o_pr += vp; o_nw += vn; if (vn && !vb) wide++; if (vb && !vn) narrow++
    }
    if (o_nw != o_bd || o_nw != o_pr) {
      ds++; ws = (w ~ /\.cstaff$/) ? " ⚠ .cstaff (etiquetas COM senha)" : ""
      if (w ~ /\.cstaff$/ && wide) cwide++
      addex("sf", sprintf("%-20s etiquetas %4d · impressão %4d → NOVO %4d  (+%d −%d vs etiquetas)%s", w, o_bd, o_pr, o_nw, wide, narrow, ws))
    }
  }
  printf "\n  STAFF (region:<nome>): %d conta(s) passam a ver outro conjunto; %d .cstaff passam a ver MAIS (senhas nas etiquetas)%s\n", ds, cwide, exs["sf"]
}
' "$W/raw.tsv" "$W/new-nodes.tsv" "$W/map.tsv" "$W/explicit.tsv" "$W/staff.tsv"
