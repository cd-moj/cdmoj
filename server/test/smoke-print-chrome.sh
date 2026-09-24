#!/bin/bash
# smoke-print-chrome.sh — o CROMO do site (rodapé, alerta do juiz-chefe) nunca vai ao PAPEL.
#
# Relato do Daniel Saad (24/09/2026): as ETIQUETAS de credenciais saíam com a linha do rodapé
# ("MOJ <versão> · código-fonte · relatar um problema · contato / Bandeiras: …") no topo da 1ª folha —
# no diálogo de impressão do navegador E no do sistema (é conteúdo da página, não o cabeçalho do
# navegador) — e a grade Pimaco descia, cortando etiquetas. O rodapé (`shared/site-footer.js`, issue #20)
# entra com `main.after(foot)`, ENTRE o <main> e as folhas, e o `@media print` da página só escondia
# header/nav/main. O `#mojChiefAlert` (faixa fixa do juiz-chefe) é da mesma classe: sairia no topo de
# TODA folha. Estático (só lê arquivos): roda em qualquer lugar, inclusive dentro da imagem.
set -u
ROOT="${MOJ_SERVER_ROOT:-$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)}"
WEB="$(cd "$ROOT/.." && pwd)/web"
[[ -f "$WEB/shared/ui.css" ]] || WEB=/opt/moj/cdmoj/web
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:-}"; ((fail++)); fi; }

# conteúdo dos blocos `@media print { … }` de um arquivo (chaves aninhadas contadas)
print_css(){ python3 - "$1" <<'PY'
import re, sys
s = open(sys.argv[1], encoding='utf-8').read()
out = []
for m in re.finditer(r'@media\s+print\s*\{', s):
    i, d = m.end(), 1
    while i < len(s) and d:
        d += {'{': 1, '}': -1}.get(s[i], 0); i += 1
    out.append(s[m.end():i - 1])
print('\n'.join(out))
PY
}
# o seletor está numa regra que esconde (display:none) dentro do @media print?
hides(){ python3 - "$1" "$2" <<'PY'
import re, sys
css, sel = sys.argv[1], sys.argv[2]
for sels, body in re.findall(r'([^{}]+)\{([^{}]*)\}', css):
    if re.search(r'display\s*:\s*none', body) and sel in [x.strip() for x in sels.split(',')]:
        sys.exit(0)
sys.exit(1)
PY
}

echo "== ui.css: regra global de impressão =="
UI="$(print_css "$WEB/shared/ui.css")"
DBG="$UI"
ck "ui.css esconde .sitefoot na impressão"        'hides "$UI" .sitefoot'
ck "ui.css esconde #mojChiefAlert na impressão"   'hides "$UI" "#mojChiefAlert"'

echo "== etiquetas (contest/badges): a grade Pimaco não pode ser empurrada =="
B="$WEB/contest/badges/index.html"
BP="$(print_css "$B")"
DBG="$BP"
ck "etiquetas: o @media print esconde .sitefoot"       'hides "$BP" .sitefoot'
ck "etiquetas: o @media print esconde #mojChiefAlert"  'hides "$BP" "#mojChiefAlert"'
ps="$(grep -n 'id="sheets"' "$B" | head -1 | cut -d: -f1)"; pf="$(grep -n 'id="siteFooter"' "$B" | head -1 | cut -d: -f1)"
DBG="sheets=$ps siteFooter=$pf"
ck "etiquetas: o rodapé mora DEPOIS das folhas"        '[[ -n "$ps" && -n "$pf" && "$pf" -gt "$ps" ]]'

echo "== toda página que chama window.print() carrega o ui.css =="
while IFS= read -r js; do
  d="$(dirname "$js")"; h="$d/index.html"
  DBG="$h"
  ck "${js#"$WEB"/}: a página carrega /shared/ui.css" '[[ -f "$h" ]] && grep -q "/shared/ui.css" "$h"'
done < <(grep -rl 'window\.print()' "$WEB/contest" "$WEB/treino" "$WEB/shared" --include='*.js' 2>/dev/null \
         | grep -v '/vendor/' | xargs -r grep -L 'contentWindow' )

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
