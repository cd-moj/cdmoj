#!/bin/bash
# smoke-bank-panel-private.gjs.sh — o opt-in de PRIVADOS no painel de busca+sorteio
# (web/shared/contest-config/bank-panel.js, o mesmo do wizard e das abas Problemas/Rodadas).
# Com a API simulada, afirma:
#   • padrão: meta e sorteio SEM include_private (só públicos);
#   • marcar "incluir privados" recarrega tags/coleções com include_private=1 e o sorteio o manda;
#   • privado sorteado leva o selo 🔒 (privado / compartilhado);
#   • "+ adicionar todos" com privado no meio pede confirmação (cancelar não adiciona nada);
#   • contest sem dono (private_included:false com o opt-in marcado) avisa "Só públicos".
set -u
command -v gjs >/dev/null 2>&1 || { echo "bank-panel-private: gjs ausente — pulando"; exit 0; }
WEB="$(cd "$(dirname "$(readlink -f "$0")")/../../web" && pwd)"
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
JS="$(mktemp --suffix=.js)"; trap 'rm -f "$JS"' EXIT
{ cat <<'EOF'
function N(tag){ this.tagName=tag; this.nodeType=1; this.children=[]; this.attrs={}; this.style={}; this._ev={}; this.parentNode=null; this._text=''; }
N.prototype.append=function(){ for (const k of arguments) { if (k && typeof k==='object') { k.parentNode=this; this.children.push(k); } else if (k!=null) this.children.push({nodeType:3,text:String(k)}); } };
N.prototype.setAttribute=function(k,v){ this.attrs[k]=String(v); };
N.prototype.addEventListener=function(t,f){ (this._ev[t]=this._ev[t]||[]).push(f); };
N.prototype.fire=function(t,ev){ return Promise.all((this._ev[t]||[]).map(f=>f(Object.assign({target:this, preventDefault(){}}, ev||{})))); };
N.prototype.all=function(){ const o=[]; for (const c of this.children) if (c.nodeType===1) { o.push(c); o.push(...c.all()); } return o; };
Object.defineProperty(N.prototype,'className',{set(v){this.attrs['class']=v},get(){return this.attrs['class']||''}});
Object.defineProperty(N.prototype,'innerHTML',{set(v){this.children=[]},get(){return ''}});
Object.defineProperty(N.prototype,'textContent',{set(v){this._text=String(v);this.children=[]},
  get(){ let t=this._text; for (const c of this.children) t+= c.nodeType===3 ? c.text : c.textContent; return t; }});
Object.defineProperty(N.prototype,'value',{set(v){this._v=String(v)},get(){ return this._v!==undefined ? this._v : (this.attrs.value||''); }});
globalThis.document={ createElement:(t)=>new N(t), createTextNode:(t)=>({nodeType:3,text:String(t),textContent:String(t)}) };
function T(pt){ return pt; }
let CONFIRM=true, ASKED=0; globalThis.confirm=()=>{ ASKED++; return CONFIRM; };
EOF
  strip "$WEB/shared/dom.js"; strip "$WEB/shared/difficulty.js"; strip "$WEB/shared/contest-config/bank-panel.js"
  cat <<'EOF'
let pass=0, fail=0; const ck=(m,ok,d)=>{ if (ok) { print('  ok: '+m); pass++; } else { print('  FAIL: '+m+' :: '+(d||'')); fail++; } };
const J=(x)=>JSON.stringify(x);
const tick=()=>new Promise(r=>Promise.resolve().then(()=>Promise.resolve().then(r)));
let META=[], DRAW=[], DRAWRES=null, ADDED=[];
const api={
  meta: async (q)=>{ META.push(q||{}); return { tags:[{tag:'#x',count:1}], collections:[] }; },
  draw: async (p)=>{ DRAW.push(p); return DRAWRES; },
  search: async ()=>({ problems:[] }),
};
const PRIV={id:'org#p',title:'Prova da org',private:true,access:'shared',bucket:'unknown',collections:[]};
const PUB={id:'pub1',title:'Público',private:false,access:'public',bucket:'unknown',collections:[]};
(async () => {
  const b=makeBankPanel({ api, onAdd:(it)=>ADDED.push(it.id), privateLabel:'incluir os privados do dono' });
  await tick();
  const all=()=>b.el.all();
  const box=all().filter(n=>n.tagName==='input' && n.attrs.type==='checkbox')[0];
  const drawBtn=all().filter(n=>n.tagName==='button' && n.textContent.includes('Sortear'))[0];
  const link=(txt)=>all().filter(n=>n.tagName==='a' && n.textContent.includes(txt))[0];
  ck('rótulo do opt-in vem da opção privateLabel', b.el.textContent.includes('🔒 incluir os privados do dono'));
  ck('meta inicial SEM include_private', META.length===1 && J(META[0])==='{}', J(META));
  ck('opt-in nasce desmarcado', !box.checked);
  DRAWRES={problems:[PUB],candidates:1,drawn:1,seed:5,private_included:false};
  await drawBtn.fire('click'); await tick();
  ck('sorteio padrão sem include_private', DRAW.length===1 && !('include_private' in DRAW[0]), J(DRAW[0]));
  box.checked=true; await box.fire('change'); await tick();
  ck('marcar recarrega tags/coleções com include_private=1', META.length===2 && META[1].include_private==='1', J(META));
  DRAWRES={problems:[PRIV,PUB],candidates:2,drawn:2,seed:9,private_included:true};
  await drawBtn.fire('click'); await tick();
  ck('sorteio com o opt-in manda include_private=1', DRAW[1].include_private==='1', J(DRAW[1]));
  ck('privado sorteado com selo 🔒 compartilhado', b.el.textContent.includes('🔒 compartilhado'));
  CONFIRM=false; await link('adicionar todos').fire('click');
  ck('adicionar todos com privado pede confirmação; cancelar não adiciona', ASKED===1 && ADDED.length===0, ASKED+' '+J(ADDED));
  CONFIRM=true; await link('adicionar todos').fire('click');
  ck('confirmar adiciona todos', J(ADDED)===J(['org#p','pub1']), J(ADDED));
  ADDED=[]; ASKED=0;
  DRAWRES={problems:[PUB],candidates:1,drawn:1,seed:3,private_included:false};
  await drawBtn.fire('click'); await tick();
  ck('sem privado no sorteio: adicionar todos não pergunta', (await link('adicionar todos').fire('click'), ASKED===0 && ADDED.length===1));
  ck('opt-in marcado mas contest sem dono: avisa "Só públicos"', b.el.textContent.includes('Só públicos'));
  box.checked=false; await box.fire('change'); await tick();
  ck('desmarcar recarrega a meta sem include', META.length===3 && J(META[2])==='{}', J(META));
  print(''); print('RESULT: '+pass+' passed, '+fail+' failed');
  imports.system.exit(fail>0?1:0);
})().catch(e=>{ print('ERRO: '+e+'\n'+e.stack); imports.system.exit(2); });
EOF
} > "$JS"
gjs "$JS"
