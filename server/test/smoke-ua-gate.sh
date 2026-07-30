#!/bin/bash
# smoke-ua-gate.sh — GATE DE NAVEGADOR POR SEDE (lib/ua-gate.sh).
#
# A imagem de prova de cada sede manda um UA com um pedaço do login do time
# (teambrspso001 -> "brspso"). Confere a ordem de resolução inteira: isentos, conta de papel,
# by_regex, override por sede, captura no login, fallback/legado e mode:off — e que o resolvedor
# em LOTE (usado pelo painel de Máquinas) concorda com o individual (usado no login).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CONTESTSDIR="$TMP/contests"
C="$CONTESTSDIR/prova"; mkdir -p "$C/users"
: > "$C/conf"
printf '[{"name":"Campinas","regex":"^teambrspcp"},{"name":"Sorocaba","regex":"^teambrspso"}]' > "$C/regions.json"
mk(){ mkdir -p "$C/users/$1"; jq -cn --arg l "$1" --arg r "${2:-}" \
  '{login:$l,fullname:$l} + (if $r=="" then {} else {team:{region:$r}} end)' > "$C/users/$1/account.json"; }
mk teambrspso001; mk teambrspcp007 Campinas; mk conv55; mk cclconv9; mk time-reserva-07
mk juiz1.admin; mk nada99
cat > "$C/ua-gate.json" <<'EOF'
{ "mode":"enforce",
  "from_login":{"regex":"^team([a-z]{6})[0-9]{3}$","expect":"\\1"},
  "by_region":{"Campinas":"brspcp-especial"},
  "by_regex":[{"regex":"^conv","expect":"convidado"}],
  "exempt":["^ccl","time-reserva-07"] }
EOF
source "$ROOT/api/v1/lib/ua-gate.sh"

pass=0; fail=0
ck(){ if eval "$2"; then printf '  ok: %s\n' "$1"; ((pass++)); else printf '  FAIL: %s\n' "$1"; ((fail++)); fi; }
exp(){ ug_expected prova "$1"; }

echo "== ordem de resolução =="
ck "captura no login (teambrspso001 -> brspso)" '[[ "$(exp teambrspso001)" == brspso ]]'
ck "override por SEDE vence a captura"          '[[ "$(exp teambrspcp007)" == brspcp-especial ]]'
ck "by_regex (conv55 -> convidado)"             '[[ "$(exp conv55)" == convidado ]]'
ck "isento por regex (^ccl) fica sem gate"      '[[ -z "$(exp cclconv9)" ]]'
ck "isento literal (time-reserva-07)"           '[[ -z "$(exp time-reserva-07)" ]]'
ck "conta de papel nunca é barrada"             '[[ -z "$(exp juiz1.admin)" ]]'
ck "login que não casa nada: sem gate"          '[[ -z "$(exp nada99)" ]]'

echo "== match (substring, case-insensitive) =="
ck "UA da sede certa passa"        'ug_ok prova teambrspso001 "Mozilla/5.0 MOJ-BRSPSO-img/1"'
ck "UA de casa é barrado"          '! ug_ok prova teambrspso001 "Mozilla/5.0 Chrome/120"'
ck "UA vazio é barrado"            '! ug_ok prova teambrspso001 ""'
ck "isento entra com qualquer UA"  'ug_ok prova cclconv9 "curl/8"'

echo "== resolvedor em LOTE == (painel de Máquinas; tem de concordar com o individual)"
MAP="$(ug_expected_map prova '["teambrspso001","teambrspcp007","conv55","cclconv9","juiz1.admin","nada99"]')"
for l in teambrspso001 teambrspcp007 conv55 cclconv9 juiz1.admin nada99; do
  ck "lote($l) == individual" '[[ "$(jq -r --arg l "'"$l"'" ".[\$l]" <<<"$MAP")" == "$(exp '"$l"')" ]]'
done

echo "== mode:off =="
jq -c '.mode="off"' "$C/ua-gate.json" > "$C/x" && mv "$C/x" "$C/ua-gate.json"
ck "mode:off não barra ninguém"  'ug_ok prova teambrspso001 "Chrome"'
ck "mode:off zera o esperado"    '[[ -z "$(exp teambrspso001)" ]]'

echo "== sem ua-gate.json: cai no LOGIN_UA_SUBSTRING legado =="
rm -f "$C/ua-gate.json"; printf 'LOGIN_UA_SUBSTRING=MOJ-KIOSK\n' > "$C/conf"
ck "legado vira o esperado"          '[[ "$(exp teambrspso001)" == MOJ-KIOSK ]]'
ck "legado barra quem não tem"       '! ug_ok prova teambrspso001 "Chrome/120"'
ck "legado passa quem tem"           'ug_ok prova teambrspso001 "x MOJ-KIOSK y"'
ck "legado também vale no lote"      '[[ "$(jq -r ".teambrspso001" <<<"$(ug_expected_map prova "[\"teambrspso001\"]")")" == MOJ-KIOSK ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
