#!/bin/bash
# smoke-settings-groups.gjs.sh — Central › Regras agrupa o editor de configurações por ÍNDICE dos filhos
# (web/contest/admin/settings-tab.js GROUPS × web/shared/contest-config/settings-editor.js). Tirar ou pôr
# um campo no meio do editor desloca tudo e o campo cai na seção errada, sem erro nenhum (SHOWCODE em
# 18/09, ALLOWLATEUSER em 28/09 — os dois renumeraram à mão). Afirma, montando o editor de verdade:
#   • todo filho do editor está em exatamente UMA seção (nenhum sobra p/ "Outras opções", nenhum repete);
#   • os campos-âncora caem na seção certa (login/secreto/gate na de acesso, log/editor na do time,
#     veredicto manual/linguagens/pool no julgamento, anônimo/penalidade/balões no placar, fuso na janela);
#   • o "auto-cadastro (late users)" não existe mais.
set -u
command -v gjs >/dev/null 2>&1 || { echo "settings-groups: gjs ausente — pulando"; exit 0; }
WEB="$(cd "$(dirname "$(readlink -f "$0")")/../../web" && pwd)"
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
# GROUPS do settings-tab.js: [{label (pt), idx}] — lido do fonte (o array mora dentro do closure da aba)
GROUPS_JSON="$(python3 - "$WEB/contest/admin/settings-tab.js" <<'PY'
import re, sys, json
s = open(sys.argv[1]).read()
blk = s[s.index('const GROUPS = () => ['):]; blk = blk[:blk.index('];')]
out = [{'label': m.group(1), 'idx': [int(x) for x in m.group(2).split(',') if x.strip()]}
       for m in re.finditer(r"label: T\('([^']*)'.*?idx: \[([0-9, ]*)\]", blk)]
print(json.dumps(out))
PY
)"
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
const makeLangPicker=()=>({ el:Object.assign(new N('div'),{_text:'[lang-picker]'}), get:()=>[] });
const makeJudgePicker=()=>({ el:Object.assign(new N('div'),{_text:'[judge-picker]'}), get:()=>[] });
const toLocalDT=()=>''; const dtToEpoch=()=>0;
EOF
  strip "$WEB/shared/dom.js"; strip "$WEB/shared/contest-config/settings-editor.js"
  printf 'const GROUPS=%s;\n' "$GROUPS_JSON"
  cat <<'EOF'
let pass=0, fail=0; const ck=(m,ok,d)=>{ if (ok) { print('  ok: '+m); pass++; } else { print('  FAIL: '+m+' :: '+(d||'')); fail++; } };
const ed=makeSettingsEditor({ value:{}, mode:'admin', contestMode:'icpc' });
const kids=ed.el.children;
ck('GROUPS lido do settings-tab.js (5 seções)', GROUPS.length===5, JSON.stringify(GROUPS));
const all=GROUPS.flatMap(g=>g.idx), seen=new Set(all);
ck('nenhum índice repetido', seen.size===all.length);
const orphan=[...kids.keys()].filter(i=>!seen.has(i));
ck('todo filho do editor está numa seção (nada sobra p/ "Outras opções"; '+kids.length+' filhos)', orphan.length===0,
   'sobram: '+orphan.map(i=>i+'='+kids[i].textContent.slice(0,40)).join(' | '));
ck('nenhum índice aponta além do editor', all.every(i=>i<kids.length), 'max='+Math.max(...all)+' filhos='+kids.length);
const sec=(txt)=>{ const i=[...kids.keys()].find(k=>kids[k].textContent.includes(txt)); const g=GROUPS.find(g=>g.idx.includes(i)); return g ? g.label : ('(índice '+i+' sem seção)'); };
const want=[['Login habilitado','Acesso'],['SUPER SECRETO','Acesso'],['Gate de login por substring','Acesso'],
  ['ver o log de julgamento','O que o time vê'],['Editor de código no browser','O que o time vê'],['pedidos de impressão','O que o time vê'],
  ['Veredicto manual','Julgamento'],['Nº de juízes que validam','Julgamento'],['Linguagens permitidas','Julgamento'],['Máquinas de juiz','Julgamento'],
  ['Placar anônimo','Placar'],['Penalidade','Placar'],['Placar completo','Placar'],['Balões durante o freeze','Placar'],['Célula "resolveu"','Placar'],
  ['Fuso horário da prova','Identidade'],['Abertura do login','Identidade']];
for (const [txt, g] of want) { const got=sec(txt); ck('"'+txt+'" → '+g, got.includes(g), got); }
ck('o "auto-cadastro (late users)" não existe mais', !ed.el.textContent.includes('auto-cadastro') && ed.getValue().allow_late===undefined);
print(''); print('RESULT: '+pass+' passed, '+fail+' failed');
imports.system.exit(fail>0?1:0);
EOF
} > "$JS"
gjs "$JS"
