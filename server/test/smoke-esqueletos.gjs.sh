#!/bin/bash
# smoke-esqueletos.gjs.sh — as funções PURAS do esqueleto de código (web/shared/editor-skeleton.js), usadas
# pelo editor do treino e pelo do contest (módulo `esqueletos`):
#   • padrão = o `template` de shared/languages.js; personalizado do contest vence; `off` e linguagem de
#     FUNÇÃO (function_langs) começam vazias;
#   • isSkeleton reconhece o esqueleto INTACTO (padrão de qualquer linguagem ou personalizado), nunca o vazio,
#     e ignora espaço nas pontas e \r\n;
#   • trocar de linguagem só troca o texto vazio ou intacto — código digitado fica;
#   • contestSkeletonCfg: módulo desligado ou servidor antigo (sem o campo) = null (comportamento de sempre).
set -u
command -v gjs >/dev/null 2>&1 || { echo "esqueletos.gjs: gjs ausente — pulando"; exit 0; }
WEB="$(cd "$(dirname "$(readlink -f "$0")")/../../web" && pwd)"
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
JS="$(mktemp --suffix=.js)"; trap 'rm -f "$JS"' EXIT
{ strip "$WEB/shared/languages.js"; strip "$WEB/shared/editor-skeleton.js"
  cat <<'EOF'
let pass=0, fail=0; const ck=(m,ok,d)=>{ if (ok) { print('  ok: '+m); pass++; } else { print('  FAIL: '+m+' :: '+(d||'')); fail++; } };
const J=(x)=>JSON.stringify(x);
const C = langById('c').template, PY = langById('py').template, JAVA = langById('java').template;

print('== skeletonFor ==');
ck('padrão = template do languages.js', skeletonFor('c') === C);
ck('linguagem sem template (apl) = vazio', skeletonFor('apl') === '');
ck('linguagem desconhecida = vazio', skeletonFor('xyz') === '');
const cfg = { templates: { c: '#include <stdio.h>\nint main(){ /* contest */ }\n', py: '' }, off: ['java'], functionLangs: ['cpp'] };
ck('personalizado do contest vence o padrão', skeletonFor('c', cfg) === cfg.templates.c);
ck('personalizado VAZIO = vazio (não cai no padrão)', skeletonFor('py', cfg) === '');
ck('off = vazio', skeletonFor('java', cfg) === '');
ck('linguagem de função = vazio (o main daria CE)', skeletonFor('cpp', cfg) === '');
ck('função vence até personalizado', skeletonFor('c', { templates: { c: 'x' }, functionLangs: ['c'] }) === '');
ck('o resto segue o padrão', skeletonFor('rs', cfg) === langById('rs').template);

print('== isSkeleton ==');
ck('vazio não é esqueleto', !isSkeleton('') && !isSkeleton('  \n'));
ck('padrão intacto de outra linguagem é esqueleto', isSkeleton(JAVA));
ck('espaço nas pontas e \\r\\n não contam', isSkeleton('\n\n' + C.replace(/\n/g, '\r\n') + '   '));
ck('código digitado não é', !isSkeleton(C.replace('return 0;', 'printf("1");\n    return 0;')));
ck('personalizado intacto é esqueleto (só com o cfg)', isSkeleton(cfg.templates.c, cfg) && !isSkeleton(cfg.templates.c));

print('== docOnLangChange ==');
ck('vazio troca pelo esqueleto da nova', docOnLangChange('', 'py') === PY);
ck('intacto troca', docOnLangChange(C, 'py') === PY);
ck('digitado fica', docOnLangChange('int main(){puts("oi");}', 'py') === 'int main(){puts("oi");}');
ck('intacto → linguagem de função = vazio', docOnLangChange(C, 'cpp', cfg) === '');
ck('personalizado intacto troca para o padrão de outra', docOnLangChange(cfg.templates.c, 'rs', cfg) === langById('rs').template);

print('== contestSkeletonCfg ==');
ck('módulo desligado = null', contestSkeletonCfg({ on: false }) === null);
ck('servidor antigo (sem o campo) = null', contestSkeletonCfg(undefined) === null);
const k = contestSkeletonCfg({ on: true, langs: { c: { mode: 'custom', code: 'X' }, java: { mode: 'off' }, py: { mode: 'lixo' } } }, ['cpp']);
ck('custom → templates, off → off, modo desconhecido ignorado', J(k) === J({ templates: { c: 'X' }, off: ['java'], functionLangs: ['cpp'] }), J(k));
ck('ligado sem personalização = só o padrão', J(contestSkeletonCfg({ on: true })) === J({ templates: {}, off: [], functionLangs: [] }));

print(''); print('RESULT: '+pass+' passed, '+fail+' failed');
imports.system.exit(fail>0?1:0);
EOF
} > "$JS"
gjs "$JS"
