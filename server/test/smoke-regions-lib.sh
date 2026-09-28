#!/bin/bash
# smoke-regions-lib.sh — lib/regions.sh como os consumidores vão usá-la (o casamento em si é o
# smoke-regions-match.gjs.sh, que compara com o gêmeo JS). Afirma:
#   • 2000 contas × 60 nós: mapa em < 2 s (o jq recompilava a regex por login: 1,4 s só p/ um consumidor);
#   • população = os DIRS (participante compartilhado sem account.json entra), sem contas de papel e sem
#     .removed-users;
#   • o cache só é refeito quando precisa: submissão (history/metrics) NÃO refaz; conta nova, sede gravada
#     mudada, regions.json mudado/apagado e registrations.json mudado (desmaterializar apaga account.json) SIM;
#   • rg_site_of / rg_members / rg_nodes.
set -u
TD="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"; ROOT="$TD/.."
command -v gawk >/dev/null 2>&1 || { echo "regions-lib: gawk ausente — FALHA"; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export CONTESTSDIR="$T"
source "$ROOT/api/v1/lib/regions.sh"
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 ${3:-}"; ((fail++)); fi; }
C="$T/big"; mkdir -p "$C/users" "$C/var"
# 68 nós: 4 países × (1 supersede × 12 sedes) + 3 recortes com 3 filhos (4·(1+1+12) + 3·(1+3))
jq -n '[range(4) as $p | {name: "P\($p)", regex: "^t\($p)", subregions: [{name: "S\($p)", regex: "^t\($p)[0-9]",
          subregions: [range(12) as $s | {name: "P\($p)-\($s)", regex: "^t\($p)\($s)x"}]}]}]
      + [range(3) as $v | {name: "V\($v)", view: true, regex: "^t[0-9]*\($v)x", subregions: [range(3) as $w | {name: "V\($v)-\($w)", regex: "^t\($w)\($v)x"}]}]' \
  > "$C/regions.json"
echo "== 2000 contas × $(jq '[.. | objects | select(has("name"))] | length' "$C/regions.json") nós =="
for i in $(seq 0 1999); do l="t$(( i % 4 ))$(( i % 12 ))x$i"; mkdir -p "$C/users/$l"; done
for i in $(seq 0 99); do l="t$(( i % 4 ))$(( i % 12 ))x$i"; printf '{"login":"%s","team":{"region":"P%d-%d"}}' "$l" $(( (i + 1) % 4 )) $(( i % 12 )) > "$C/users/$l/account.json"; done
mkdir -p "$C/users/big.admin" "$C/users/x.cstaff" "$C/users/.removed-users/velho"
t0=$EPOCHREALTIME; rg_build big; rc=$?; dt="$(gawk -v a="$t0" -v b="$EPOCHREALTIME" 'BEGIN{printf "%.2f", b-a}')"
ck "mapa em ${dt}s (< 2 s), rc 0" '(( rc == 0 )) && gawk -v d="$dt" "BEGIN{exit !(d < 2)}"'
M="$C/var/regions-map.tsv"
ck "2000 linhas: sem .admin/.cstaff/.removed-users" '[[ "$(wc -l < "$M")" == 2000 ]] && ! grep -qE "^(big\.admin|x\.cstaff|\.removed-users)	" "$M"'
ck "100 gravadas vencem (x), 1900 pela regex numa folha (r)" '[[ "$(cut -f4 "$M" | sort | uniq -c | tr -s " " | tr "\n" "/")" == " 1900 r/ 100 x/" ]]'
ck "rg_site_of: gravada (P1-0) × regex (P0-0)" '[[ "$(rg_site_of big t00x0)" == "P1-0" && "$(rg_site_of big t00x1200)" == "P0-0" ]]'
ck "rg_site_of de quem não existe = vazio" '[[ -z "$(rg_site_of big ninguem)" ]]'
i00="$(jq '[.[] | select(.name == "P0-0")][0].i' "$C/var/regions-nodes.json")"; iP0="$(jq '[.[] | select(.name == "P0")][0].i' "$C/var/regions-nodes.json")"
ck "rg_members: a sede P0-0 ⊂ o país P0 (pai = soma dos filhos)" '[[ -z "$(comm -23 <(rg_members big "$i00" | sort) <(rg_members big "$iP0" | sort))" && "$(rg_members big "$iP0" | wc -l)" -gt "$(rg_members big "$i00" | wc -l)" ]]'
ck "rg_nodes aponta o nodes.json (68 nós, sem órfã)" '[[ "$(jq length "$(rg_nodes big)")" == 68 ]]'

echo "== o cache só é refeito quando precisa =="
stamp(){ stat -c %Y.%y "$M"; }
# o relógio do teste: tudo o que existe fica 2 min no passado e o cache 1 min — só o que mudar DEPOIS conta
# (a árvore e o roster NÃO: a identidade deles — inode/tamanho/mtime — fica gravada junto do mapa)
old(){ find "$C/users" -maxdepth 2 \( -name account.json -o -type d \) -exec touch -d '-2 min' {} +
       touch -d '-1 min' "$M" "$C/var/regions-nodes.json"; }
old; s0="$(stamp)"
l=t00x12; printf '1:A:C:Accepted:1:x\n' >> "$C/users/$l/history"; printf '{}' > "$C/users/$l/metrics.json.tmp"; mv "$C/users/$l/metrics.json.tmp" "$C/users/$l/metrics.json"
rg_map big >/dev/null; ck "submissão (history + metrics.json) NÃO refaz" '[[ "$(stamp)" == "$s0" ]]'
mkdir -p "$C/users/t00xnovo"; rg_map big >/dev/null
ck "conta nova (dir) refaz e entra" '[[ "$(stamp)" != "$s0" ]] && grep -q "^t00xnovo	" "$M"'
old; s0="$(stamp)"; printf '{"team":{"region":"P3-3"}}' > "$C/users/t00x12/account.json"; rg_map big >/dev/null
ck "sede gravada mudada refaz" '[[ "$(stamp)" != "$s0" && "$(rg_site_of big t00x12)" == "P3-3" ]]'
old; s0="$(stamp)"; jq '.[0].name = "Pais Zero"' "$C/regions.json" > "$C/r.tmp" && mv "$C/r.tmp" "$C/regions.json"; rg_map big >/dev/null
ck "regions.json mudado refaz" '[[ "$(stamp)" != "$s0" ]] && jq -e "any(.[]; .name == \"Pais Zero\")" "$C/var/regions-nodes.json" >/dev/null'
old; echo '{}' > "$C/registrations.json"; s0="$(stamp)"; rg_map big >/dev/null
ck "registrations.json mudado refaz (desmaterializar apaga account.json sem mexer em users/)" '[[ "$(stamp)" != "$s0" ]]'
old; cp -p "$C/regions.json" "$T/r.bak"; jq '.[1].name = "P1 novo"' "$C/regions.json" > "$C/r.tmp" && mv "$C/r.tmp" "$C/regions.json"
touch -d '-3 min' "$C/regions.json"; rg_map big >/dev/null; s0="$(stamp)"; mv "$T/r.bak" "$C/regions.json"; rg_map big >/dev/null
ck "regions.json DEVOLVIDO com mv (mtime antigo) também refaz" '[[ "$(stamp)" != "$s0" ]] && ! jq -e "any(.[]; .name == \"P1 novo\")" "$C/var/regions-nodes.json" >/dev/null'
old; s0="$(stamp)"; rm -f "$C/regions.json"; rg_map big >/dev/null
ck "regions.json apagado refaz: só as gravadas (órfãs), o resto sem sede" '[[ "$(stamp)" != "$s0" && "$(jq "[.[] | select(.orphan | not)] | length" "$C/var/regions-nodes.json")" == 0 && "$(rg_site_of big t00x0)" == "P1-0" && -z "$(rg_site_of big t01x1)" ]]'
old; s0="$(stamp)"; rg_map big >/dev/null; ck "…e depois disso não refaz à toa" '[[ "$(stamp)" == "$s0" ]]'

echo "== compartilhado: dir sem account.json entra; contest sem users/ não quebra =="
S="$T/sh"; mkdir -p "$S/users/aluno1" "$S/users/aluno2"; echo '[{"name":"Sala","regex":"^aluno"}]' > "$S/regions.json"
rg_build sh; ck "participante só com dir tem sede pela regex" '[[ "$(rg_site_of sh aluno1)" == Sala && "$(wc -l < "$S/var/regions-map.tsv")" == 2 ]]'
mkdir -p "$T/vazio"; ck "contest sem users/ nem regions.json: mapa vazio, rc 0" 'rg_build vazio && [[ ! -s "$T/vazio/var/regions-map.tsv" ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail > 0 ? 1 : 0 ))
