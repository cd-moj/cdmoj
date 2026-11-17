#!/bin/bash
# smoke-wizard-spec.gjs.sh — o assistente de criação (web/treino/criar/criar.js) leva ao servidor TODO campo do passo 5,
# o settings-editor da criação (relato de 16/11/2026: as linguagens marcadas no assistente não iam no pedido e a lista
# nascia aceitando qualquer linguagem; o fuso, a regra do veredicto, o estilo do balão, os juízes da revisão e os balões
# no congelamento também ficavam pelo caminho). Monta o editor DE VERDADE só p/ ter as chaves do getValue() e roda o
# buildSpec/applyExport/applyTemplate tirados do fonte:
#   • cada chave do getValue() sai no spec com o valor escolhido (balões no congelamento: na seção do módulo `baloes`);
#   • chave nova no editor sem caso aqui = FAIL (o teste obriga a decidir para onde ela vai);
#   • com o módulo `baloes` desligado, os balões no congelamento não vão a lugar nenhum (a regra do `msec` no servidor);
#   • export e template → assistente → buildSpec devolvem os mesmos campos.
set -u
command -v gjs >/dev/null 2>&1 || { echo "wizard-spec: gjs ausente — pulando"; exit 0; }
WEB="$(cd "$(dirname "$(readlink -f "$0")")/../../web" && pwd)"
CJ="$WEB/treino/criar/criar.js"
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
JS="$(mktemp --suffix=.js)"; trap 'rm -f "$JS"' EXIT
{ cat <<'EOF'
function N(tag){ this.tagName=tag; this.nodeType=1; this.children=[]; this.attrs={}; this.style={}; this.dataset={}; this._ev={}; this.parentNode=null; this._text=''; }
N.prototype.append=function(){ for (const k of arguments) { if (k && typeof k==='object') { k.parentNode=this; this.children.push(k); } else if (k!=null) this.children.push({nodeType:3,text:String(k)}); } };
N.prototype.setAttribute=function(k,v){ this.attrs[k]=String(v); };
N.prototype.addEventListener=function(t,f){ (this._ev[t]=this._ev[t]||[]).push(f); };
Object.defineProperty(N.prototype,'className',{set(v){this.attrs['class']=v},get(){return this.attrs['class']||''}});
Object.defineProperty(N.prototype,'innerHTML',{set(v){this.children=[]},get(){return ''}});
Object.defineProperty(N.prototype,'textContent',{set(v){this._text=String(v);this.children=[]},
  get(){ let t=this._text; for (const c of this.children) t+= c.nodeType===3 ? c.text : c.textContent; return t; }});
Object.defineProperty(N.prototype,'value',{set(v){this._v=String(v)},get(){ return this._v!==undefined ? this._v : (this.attrs.value||''); }});
globalThis.document={ createElement:(t)=>new N(t), createTextNode:(t)=>({nodeType:3,text:String(t),textContent:String(t)}) };
function T(pt){ return pt; }
const makeLangPicker=(v)=>({ el:new N('div'), get:()=>v });
const makeJudgePicker=(v)=>({ el:new N('div'), get:()=>v });
EOF
  strip "$WEB/shared/dom.js"; strip "$WEB/shared/contest-config/util.js"; strip "$WEB/shared/contest-config/settings-editor.js"
  # do criar.js: os helpers do topo e as funções do boot() que montam/recebem o spec
  grep -E '^const (nextFullHour|b64utf8) = ' "$CJ"   # o nowEpoch vem do util.js
  sed -n '/^function newDraft(/,/^}/p; /^function autoLetter(/,/^}/p' "$CJ"
  echo "const perm = { login: 'prof', name: 'Prof' }; const ctx = { draft: newDraft(perm), editors: {}, resetEditors() { this.editors = {}; } };"
  sed -n '/^  function optsValue(/p; /^  function buildSpec(/,/^  }$/p; /^  function buildModules(/,/^  }$/p; /^  function modulesFromSpec(/,/^  }$/p; /^  function applyTemplate(/,/^  }$/p; /^  function applyExport(/,/^  }$/p; /^  function fromSpecProblem(/,/^  }$/p' "$CJ"
  cat <<'EOF'
let pass=0, fail=0; const ck=(m,ok,d)=>{ if (ok) { print('  ok: '+m); pass++; } else { print('  FAIL: '+m+' :: '+(d||'')); fail++; } };
const J=(x)=>JSON.stringify(x);
ck('buildSpec/applyExport/applyTemplate extraídos do criar.js', typeof buildSpec==='function' && typeof applyExport==='function' && typeof applyTemplate==='function');
// valor NÃO padrão de cada campo do passo 5 (o que o organizador escolheu)
const NONDEF = {
  priority: 'prova', locale: 'es', tz: 'America/Santiago', login_start: 1800000000, freeze: 1800009000,
  login_enabled: false, show_log: false, show_editor: false, show_tl: false, allow_backup: false, allow_print: false,
  score_anon: true, manual_verdict: true, secret: true, login_ua_substring: 'MOJBOX',
  balloons_during_freeze: true, balloon_style: 'fill', verdict_rule: 'worst', review_judges: 3,
  languages: ['riscv'], judges: ['j1'], score_full_users: ['prof'], penalty_minutes: 10, penalty_verdicts: ['wa'],
};
// onde cada campo aparece no spec (padrão: a mesma chave no topo)
const AT = { balloons_during_freeze: (s) => s.modules && s.modules.baloes ? s.modules.baloes.during_freeze : undefined };
const at = (s, k) => (AT[k] ? AT[k](s) : s[k]);
// as chaves do editor de verdade (criação, icpc: com penalidade; com abertura do login p/ a chave aparecer)
const keys = Object.keys(makeSettingsEditor({ value: { login_start: 1800000000 }, mode: 'create', canSuper: true, contestMode: 'icpc' }).getValue());
ck('o editor da criação tem as chaves de sempre (' + keys.length + ')', keys.includes('languages') && keys.includes('priority') && keys.length >= 20, J(keys));
const semCaso = keys.filter((k) => !(k in NONDEF));
ck('toda chave do editor tem caso neste teste (campo novo: diga para onde ele vai)', semCaso.length === 0, J(semCaso));
const o = {}; keys.forEach((k) => { if (k in NONDEF) o[k] = NONDEF[k]; });
function prep(mods) {
  ctx.draft = newDraft(perm); ctx.editors = { settings: { getValue: () => o } };
  ctx.draft.mode = 'icpc'; ctx.draft.modules = mods; ctx.draft.problems = [{ kind: 'bank', bank_id: 'org#p', name: '' }];
}
prep(['baloes']);
const spec = buildSpec(false);
for (const k of keys) ck('criação: "' + k + '" vai no pedido', J(at(spec, k)) === J(o[k]), 'spec=' + J(at(spec, k)) + ' escolhido=' + J(o[k]));
ck('balões no congelamento não vão no topo do pedido', !('balloons_during_freeze' in spec));
prep([]);
const specOff = buildSpec(false);
ck('módulo baloes desligado: balões no congelamento não vão a lugar nenhum', !('balloons_during_freeze' in specOff) && !(specOff.modules && specOff.modules.baloes), J(specOff.modules));
// cópia (export) e template voltam ao assistente com os mesmos campos (datas re-baseadas: só a presença)
const DATES = ['login_start', 'freeze'];
function roundTrip(label, apply, src) {
  prep(['baloes']); ctx.editors = {};
  apply(src, label);
  const s2 = buildSpec(false);
  for (const k of keys) {
    if (DATES.includes(k)) { ck(label + ': "' + k + '" volta (re-baseado)', typeof at(s2, k) === 'number' && at(s2, k) > 0, J(at(s2, k))); continue; }
    ck(label + ': "' + k + '" volta igual', J(at(s2, k)) === J(o[k]), 'volta=' + J(at(s2, k)) + ' original=' + J(o[k]));
  }
}
const exp = { ...spec, start: 1800006000, end: 1800018000 }; exp.login_start = 1800000000; exp.freeze = 1800012000;
roundTrip('export', applyExport, exp);
const tpl = { ...spec, duration: 18000, login_lead: 3600, freeze_before_end: 3600 }; delete tpl.start; delete tpl.end; delete tpl.login_start; delete tpl.freeze;
roundTrip('template', applyTemplate, tpl);
print(''); print('RESULT: '+pass+' passed, '+fail+' failed');
imports.system.exit(fail>0?1:0);
EOF
} > "$JS"
TZ=America/Sao_Paulo gjs "$JS"
