#!/bin/bash
# smoke-b64-strip.sh — guarda a classe O(n²) do strip de data-url (incidente do import,
# 28/08/2026: `${var#data:*;base64,}` sobre 5,2 MB SEM o prefixo = varredura completa =
# ~2 min de CPU). Três garantias:
#   1. b64_strip_data_prefix: semântica (com/sem prefixo, prefixo malformado);
#   2. string GRANDE sem prefixo passa em <1 s (a guarda barata corta a varredura);
#   3. nenhum handler/lib regrediu para o idioma cru `${...#data:` (inventário estático).
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../api/v1"
source lib/common.sh 2>/dev/null
pass=0; failn=0
ok(){ echo "  ok: $1"; pass=$((pass+1)); }
bad(){ echo "  FALHOU: $1"; failn=$((failn+1)); }

echo "== semântica"
v="data:image/png;base64,QUJD"; b64_strip_data_prefix v
[[ "$v" == "QUJD" ]] && ok "strip com prefixo" || bad "strip com prefixo: '$v'"
v="QUJDsemprefixo"; b64_strip_data_prefix v
[[ "$v" == "QUJDsemprefixo" ]] && ok "sem prefixo intacto" || bad "sem prefixo: '$v'"
v="data:semvirgula-malformado"; b64_strip_data_prefix v
[[ "$v" == "data:semvirgula-malformado" ]] && ok "malformado intacto (não varre)" || bad "malformado: '$v'"

echo "== custo: 6 MB sem prefixo em <1 s (o caso do incidente era ~120 s)"
big="$(head -c 6000000 /dev/zero | tr '\0' 'A')"
t0=$EPOCHSECONDS
b64_strip_data_prefix big
dt=$(( EPOCHSECONDS - t0 ))
(( dt <= 1 )) && ok "6 MB em ${dt}s" || bad "6 MB levou ${dt}s"

echo "== inventário: o idioma cru não volta (fora o próprio helper)"
# comentários (linha começando em #) e o corpo do próprio helper (_v=) ficam de fora
crus="$(grep -rn '#data:\*;base64,' handlers/ lib/ 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#' | grep -v '_v=')"
if [[ -z "$crus" ]]; then ok "zero call sites crus"; else bad "call sites crus:"; printf '%s\n' "$crus"; fi

echo "== import.sh: corpo em arquivo, nunca em variável"
if grep -q 'read_body)' handlers/treino/contest-create/import.sh; then
  bad "import.sh voltou a usar read_body em variável"
else
  ok "import.sh sem read_body-em-variável"
fi

echo
echo "RESULT: $pass passed, $failn failed"
(( failn == 0 ))
