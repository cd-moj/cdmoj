#!/bin/bash
# smoke-admin-nav.sh — a NAVEGAÇÃO do painel de admin do contest é consistente:
#   1. o catálogo de módulos do bash (lib/modules.sh MODULES=) == o do JS (modules.js MODULE_IDS);
#   2. PANEL_MODULE só cita módulos do catálogo e painéis que existem em GROUPS;
#   3. todo alvo do ALIAS resolve p/ o painel declarado com tudo ligado (gjs);
#   4. toda âncora `#grupo/painel` do web/ (JS e HTML) e todo `Grupo › Painel` do MANUAL-ADMIN
#      resolvem p/ um painel existente com tudo ligado — e os comuns também sem módulo nenhum;
#   5. todo TARGET da Central aponta p/ [grupo, painel] existente;
#   6. o shell (admin.js) tem fábrica MK p/ todo painel do nav.js e nada mais;
#   7. higiene: nenhum T('x','x') (mesmo texto nas duas línguas = tradução esquecida) nos painéis,
#      e painel com timer (everyVisible/setInterval) tem no máximo UM `panel.innerHTML = ''`
#      (o do esqueleto/erro inicial — regra do auto-refresh em lugar).
# Precisa de gjs p/ (3)-(5); sem ele essas partes são puladas (o resto é bash+python3).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; W="$ROOT/../web"; A="$W/contest/admin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${3:-}"; ((fail++)); fi; }

echo "== 1. paridade do catálogo bash × JS =="
BASH_MODS="$(bash -c 'source "$1/api/v1/lib/modules.sh" 2>/dev/null; printf "%s\n" "${MODULES[@]}"' _ "$ROOT" | sort | tr '\n' ' ')"
JS_MODS="$(grep -o "MODULE_IDS = \[[^]]*\]" "$A/modules.js" | grep -o "'[a-z]*'" | tr -d "'" | sort | tr '\n' ' ')"
ck "MODULES (bash) == MODULE_IDS (js)" '[[ -n "$BASH_MODS" && "$BASH_MODS" == "$JS_MODS" ]]' "bash=[$BASH_MODS] js=[$JS_MODS]"
CAT_JS="$(grep -oE "^\s*\{ id: '[a-z]+', icon:" "$A/modules.js" | grep -o "'[a-z]*'" | tr -d "'" | sort | tr '\n' ' ')"
ck "MODULES() do js tem os mesmos ids (sem preset)" '[[ "$CAT_JS" == "$JS_MODS" ]]' "cat=[$CAT_JS]"

echo "== 2-6. nav.js (gjs) =="
if command -v gjs >/dev/null; then
  { printf 'function T(pt,en){ return pt; }\n'
    sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /' "$A/nav.js"
    # TARGET da Central e PANEL_MODULE/ids p/ o teste
    python3 - "$A/central-tab.js" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
m=re.search(r'const TARGET = \{(.*?)\n\};', s, re.S); body=m.group(1)
pairs=re.findall(r"(\w+): \['([a-z]+)', '([a-z]+)'\]", body)
print("const TARGET = {" + ",".join(f"{k}:['{g}','{p}']" for k,g,p in pairs) + "};")
PY
    cat <<'JS'
const ALL = new Set(['sedes','maquinas','rodadas','documentos','baloes','coortes','inscricoes','telao','classificacao']);
const NONE = new Set();
const ids = GROUPS().flatMap(g => g.panels.map(p => p.id));
print('unique_ids=' + (new Set(ids).size === ids.length));
print('panel_module_ok=' + Object.entries(PANEL_MODULE).every(([p, ms]) => ids.includes(p) && ms.every(m => ALL.has(m))));
let bad = [];
for (const [k, v] of Object.entries(ALIAS)) { const r = resolveHash('#' + k, ALL); if (r.grp.id + '/' + r.pan.id !== v) bad.push(k + '->' + r.grp.id + '/' + r.pan.id + '!=' + v); }
print('alias_ok=' + (bad.length === 0) + (bad.length ? ' ' + bad.join(' ') : ''));
bad = [];
for (const [k, [g, p]] of Object.entries(TARGET)) { const r = resolveHash('#' + g + '/' + p, ALL); if (r.grp.id !== g || r.pan.id !== p) bad.push(k + ':' + g + '/' + p); }
print('target_ok=' + (bad.length === 0) + (bad.length ? ' ' + bad.join(' ') : ''));
// comuns resolvem sem módulo nenhum; painel de módulo cai em modulos com notice
const common = GROUPS().filter(g => !EVENT_GROUPS.includes(g.id)).flatMap(g => g.panels.filter(p => !PANEL_MODULE[p.id]).map(p => g.id + '/' + p.id));
print('common_ok=' + common.every(h => { const r = resolveHash('#' + h, NONE); return r.grp.id + '/' + r.pan.id === h && !r.notice; }));
const modp = Object.keys(PANEL_MODULE);
print('hidden_notice_ok=' + modp.every(p => { const r = resolveHash('#evento/' + p, NONE); return r.pan.id === 'modulos' && r.notice && r.notice.modules.length; }));
print('ids=' + ids.join(','));
print('labels=' + GROUPS().flatMap(g => g.panels.map(p => g.label.replace(/^\S+\s/, '') + ' › ' + p.label)).join('|'));
JS
  } > "$T/nav.js"
  gjs "$T/nav.js" > "$T/nav.out" 2>"$T/nav.err" || { echo "  gjs falhou:"; tail -3 "$T/nav.err"; }
  kv(){ grep "^$1=" "$T/nav.out" | cut -d= -f2-; }
  ck "ids de painel únicos"                         '[[ "$(kv unique_ids)" == true ]]'
  ck "PANEL_MODULE cita painéis e módulos existentes" '[[ "$(kv panel_module_ok)" == true ]]'
  ck "todo ALIAS resolve p/ o alvo declarado"      '[[ "$(kv alias_ok)" == true* ]]' "$(kv alias_ok)"
  ck "todo TARGET da Central existe"               '[[ "$(kv target_ok)" == true* ]]' "$(kv target_ok)"
  ck "painéis comuns resolvem sem módulo"          '[[ "$(kv common_ok)" == true ]]'
  ck "painel de módulo desligado -> Módulos + aviso" '[[ "$(kv hidden_notice_ok)" == true ]]'
  IDS="$(kv ids)"
  # 4. âncoras cruas no web/ (fora do nav.js)
  ANCH="$(grep -rhoE "#(central|prova|pessoas|operacao|evento|maquinas)/[a-z]+" "$W" --include=*.js --include=*.html | grep -v "^$" | sort -u)"
  badA=""
  while read -r a; do [[ -n "$a" ]] || continue; p="${a##*/}"; [[ ",$IDS," == *",$p,"* ]] || badA+="$a "; done <<<"$ANCH"
  ck "âncoras #grupo/painel do web/ apontam p/ painel existente" '[[ -z "$badA" ]]' "$badA"
  # MANUAL: todo "Grupo › Painel" citado existe como rótulo (pt) do nav
  LABELS="$(kv labels)"
  MAN="$(LC_ALL=C.UTF-8 grep -oE "(Central|Prova|Pessoas|Operação|Evento|Máquinas) › [^ |*\`]([^|*\`.,;:()]{2,22})" "$ROOT/../docs/MANUAL-ADMIN.md" | sed -E 's/ (do|da|de|e|que|—|ou|só|na|no|para|com|é)( .*)?$//' | sort -u)"
  badM=""
  while read -r m; do [[ -n "$m" ]] || continue
    ok=0; IFS='|' read -ra LB <<<"$LABELS"; for l in "${LB[@]}"; do [[ "$m" == "$l"* || "$l" == "$m"* ]] && { ok=1; break; }; done
    (( ok )) || badM+="[$m] "; done <<<"$MAN"
  ck "MANUAL-ADMIN só cita 'Grupo › Painel' que existe" '[[ -z "$badM" ]]' "$badM"
  # 6. MK do shell == ids do nav
  MK="$(python3 - "$A/admin.js" <<'PY'
import re,sys; s=open(sys.argv[1]).read()
m=re.search(r'const MK = \{(.*?)\n\};', s, re.S); print(",".join(sorted(re.findall(r'^\s*([a-z]+): \(\)', m.group(1), re.M))))
PY
)"
  ck "admin.js MK tem exatamente os painéis do nav.js" '[[ "$MK" == "$(tr "," "\n" <<<"$IDS" | sort | paste -sd,)" ]]' "mk=$MK ids=$IDS"
else
  echo "  (sem gjs: partes 2-6 puladas)"
fi

echo "== 7. higiene dos painéis =="
# igual nas duas línguas é aceitável só p/ nome próprio/sigla/símbolo (allowlist explícita)
SAME="$(grep -nE "T\('([^']+)', *'\1'\)" "$A"/*.js | grep -vE "T\('(📖 Manual|id|individual|Logins|mlinux|Staff|Login|IP|CSV|OK|ok|UA|jplag|Brasil|BR|E-mail|Email|MAC|CPU|RAM|—|·|↻)', " || true)"
ck "nenhum T('x','x') nos painéis (tradução esquecida)" '[[ -z "$SAME" ]]' "$(head -3 <<<"$SAME")"
badT=""
for f in "$A"/*.js; do
  grep -qE "everyVisible\(|setInterval\(" "$f" || continue
  n="$(grep -c "panel.innerHTML = ''" "$f")"; n="${n//[^0-9]/}"
  (( ${n:-0} <= 1 )) || badT+="$(basename "$f")=$n "
done
ck "painel com timer: no máx. 1 panel.innerHTML='' (esqueleto)" '[[ -z "$badT" ]]' "$badT"
NOEMOJI="$(grep -hoE "el\('h2', \{[^}]*\}, T\('[A-Za-z]" "$A"/*.js || true)"
ck "todo h2 de painel começa com emoji" '[[ -z "$NOEMOJI" ]]' "$(head -3 <<<"$NOEMOJI")"

echo; echo "RESULT: $pass passed, $fail failed"; exit $(( fail > 0 ))
