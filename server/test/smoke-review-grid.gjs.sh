#!/bin/bash
# smoke-review-grid.gjs.sh — a tela "🔎 O que vai para revisão" (web/shared/contest-config/verdict-config.js,
# makeAutoVerdictEditor), a do juiz-chefe e a do admin (painel Juízes). Com o módulo REAL, apiGet/apiPost
# falsos e um DOM falso que dispara eventos:
#   · linhas = LETRA + TÍTULO (ao lado, o id curto sem a org; o completo no tooltip — pedido do Daniel Saad);
#   · a grade reflete as regras que o servidor manda (v1 já chega convertido); a coluna "todos os
#     problemas" é tri-estado e marca/desmarca a coluna; a caixa da linha marca/desmarca a linha;
#   · avisos: veredicto manual desligado, formato anterior, e N retidas que agora sairiam (botão liberar);
#   · Salvar manda {rules:{review, langs}} só com o que está marcado; "Nada em revisão" esvazia;
#   · o inglês existe (T).
# Sem gjs: pula (rc 0).
set -u
command -v gjs >/dev/null 2>&1 || { echo "review-grid: gjs ausente — pulando"; exit 0; }
WEB="$(cd "$(dirname "$(readlink -f "$0")")/../../web" && pwd)"
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
JS="$(mktemp --suffix=.js)"; trap 'rm -f "$JS"' EXIT
{ cat <<'EOF'
function N(tag){ this.tagName=tag; this.nodeType=1; this.children=[]; this.attrs={}; this.style={}; this._ev={}; this.parentNode=null; this._text=''; }
N.prototype.append=function(){ for (const k of arguments) { if (k && typeof k==='object') { k.parentNode=this; this.children.push(k); } else this.children.push({nodeType:3,text:String(k)}); } };
N.prototype.appendChild=function(k){ this.append(k); return k; };
N.prototype.insertBefore=function(k,ref){ k.parentNode=this; const i=this.children.indexOf(ref); if (i<0) this.children.push(k); else this.children.splice(i,0,k); return k; };
N.prototype.remove=function(){ const p=this.parentNode; if (p) { const i=p.children.indexOf(this); if (i>=0) p.children.splice(i,1); this.parentNode=null; } };
N.prototype.setAttribute=function(k,v){ this.attrs[k]=String(v); };
N.prototype.addEventListener=function(t,f){ (this._ev[t]=this._ev[t]||[]).push(f); };
N.prototype.fire=async function(t){ for (const f of (this._ev[t]||[])) await f({target:this}); };
N.prototype.all=function(){ const o=[]; for (const c of this.children) if (c.nodeType===1) { o.push(c); o.push(...c.all()); } return o; };
Object.defineProperty(N.prototype,'className',{set(v){this.attrs['class']=v},get(){return this.attrs['class']||''}});
Object.defineProperty(N.prototype,'innerHTML',{set(v){this.children=[]},get(){return ''}});
Object.defineProperty(N.prototype,'textContent',{set(v){this._text=String(v);this.children=[]},
  get(){ let t=this._text; for (const c of this.children) t+= c.nodeType===3 ? c.text : c.textContent; return t; }});
Object.defineProperty(N.prototype,'value',{set(v){this._v=String(v)},get(){
  if (this._v!==undefined) return this._v;
  if (this.tagName==='select') { const o=this.children.find(c=>c.attrs && c.attrs.selected!==undefined) || this.children[0]; return o ? o.attrs.value : ''; }
  return this.attrs.value || ''; }});
for (const p of ['checked','indeterminate','disabled','open']) Object.defineProperty(N.prototype,p,{set(v){this['_'+p]=!!v},get(){return !!this['_'+p]}});
globalThis.document={ createElement:(t)=>new N(t), createTextNode:(t)=>({nodeType:3,text:String(t),textContent:String(t)}) };
let LANG='pt'; function T(pt,en,es){ if(LANG==='es') return es!=null?es:(en!=null?en:pt); return LANG==='en' ? (en!=null?en:pt) : pt; }
let GETR=null, POSTS=[], POSTR={saved:true, releasable:0};
async function apiGet(p){ return JSON.parse(JSON.stringify(GETR)); }
async function apiPost(p,b){ POSTS.push({p, b:JSON.parse(JSON.stringify(b))}); return JSON.parse(JSON.stringify(POSTR)); }
let ASKED=0; globalThis.confirm=()=>{ ASKED++; return true; };
EOF
  strip "$WEB/shared/dom.js"; strip "$WEB/shared/contest-config/verdict-config.js"
  cat <<'EOF'
let pass=0, fail=0; const ck=(m,ok,d)=>{ if (ok) { print('  ok: '+m); pass++; } else { print('  FAIL: '+m+' :: '+(d||'')); fail++; } };
const flush=async()=>{ for (let i=0;i<30;i++) await Promise.resolve(); };
const C6=['Accepted','Wrong Answer','Time Limit Exceeded','Memory Limit Exceeded','Runtime Error','Compilation Error'];
GETR={version:2, state:'v1', verdicts:C6, items:[{id:'col#pz',letter:'A',title:'Zeta'},{id:'col#pa',letter:'B',title:'Árvore Six Seven'}],
  langs:['c','cpp','py'], manual_verdict:false, releasable:3,
  rules:{review:{'col#pz':['Time Limit Exceeded'],'col#pa':[]}, langs:[{lang:'py',problem:'*',verdicts:['Wrong Answer'],to:'review'}]}};
(async()=>{
  const box=makeAutoVerdictEditor('c'); await flush();
  const txt=box.textContent;
  const lbl=box.all().find(n=>n.tagName==='span' && n.attrs.title==='col#pz');
  ck('linha = letra + título; ao lado, o id curto (sem a org) e o completo no tooltip', txt.includes('A Zeta') && txt.includes('B Árvore Six Seven') && lbl && lbl.textContent==='A Zetapz', lbl ? lbl.textContent : txt.slice(0,300));
  ck('avisos: manual desligado + formato anterior', txt.includes('veredicto manual está DESLIGADO') && txt.includes('formato anterior'));
  ck('retidas que agora sairiam: 3, com botão Liberar', txt.includes('3 submissão(ões) retida(s)') && box.all().some(n=>n.tagName==='button' && n.textContent==='Liberar agora'));
  const table=box.all().find(n=>n.tagName==='table');
  const rows=table.all().filter(n=>n.tagName==='tr');   // thead, todos, A, B
  const boxes=(tr)=>tr.all().filter(n=>n.tagName==='input');
  const [allR, rA, rB]=[rows[1], rows[2], rows[3]];
  const colTLE=boxes(allR)[2], colAC=boxes(allR)[0];
  ck('grade reflete as regras: A·TLE marcado; coluna TLE tri-estado (1 de 2)', boxes(rA)[3].checked && colTLE.indeterminate && !colTLE.checked);
  ck('resumo conta 1 de 12', txt.includes('1 de 12 combinações'));
  colAC.checked=true; await colAC.fire('change');
  ck('"todos os problemas" marca a coluna AC inteira', boxes(rA)[1].checked && boxes(rB)[1].checked && colAC.checked);
  const rowB=boxes(rB)[0]; rowB.checked=true; await rowB.fire('change');
  ck('caixa da linha marca a linha B inteira', boxes(rB).slice(1).every(c=>c.checked) && rowB.checked);
  ck('exceções: 1, aberta', box.textContent.includes('Exceções por linguagem (1)') && box.all().find(n=>n.tagName==='details').open);
  const save=box.all().find(n=>n.tagName==='button' && n.textContent==='Salvar');
  await save.fire('click'); await flush();
  const b=POSTS[POSTS.length-1].b;
  ck('Salvar manda só o marcado, na ordem das classes', JSON.stringify(b.rules.review)===JSON.stringify({'col#pz':['Accepted','Time Limit Exceeded'],'col#pa':C6}), JSON.stringify(b));
  ck('…e a exceção', JSON.stringify(b.rules.langs)===JSON.stringify([{lang:'py',problem:'*',to:'review',verdicts:['Wrong Answer']}]), JSON.stringify(b.rules.langs));
  ck('depois de salvar: "✓ salvo", sem o aviso de retidas (releasable 0) nem o de formato anterior', box.textContent.includes('✓ salvo') && !box.textContent.includes('retida(s)') && !box.textContent.includes('formato anterior'));
  const none=box.all().find(n=>n.tagName==='button' && n.textContent==='Nada em revisão'); await none.fire('click');
  POSTR={saved:true, releasable:2}; await save.fire('click'); await flush();
  ck('"Nada em revisão" esvazia a grade', JSON.stringify(POSTS[POSTS.length-1].b.rules.review)==='{}');
  ck('salvou com 2 retidas que agora sairiam: o aviso volta', box.textContent.includes('2 submissão(ões) retida(s)'));
  const rel=box.all().find(n=>n.tagName==='button' && n.textContent==='Liberar agora');
  POSTR={released:2, left:1}; await rel.fire('click'); await flush();
  ck('Liberar pede confirmação e manda action:release', ASKED===1 && POSTS[POSTS.length-1].b.action==='release' && box.textContent.includes('2 liberada(s); 1 seguem'));
  LANG='en'; GETR.manual_verdict=true; GETR.state='v2'; GETR.releasable=0; const en=makeAutoVerdictEditor('c'); await flush();
  ck('em inglês', en.textContent.includes('What goes to review') && en.textContent.includes('All problems') && !en.textContent.includes('DESLIGADO'));
})().catch(e=>{ print('  FAIL: exceção '+e+'\n'+e.stack); fail++; }).finally(()=>{ print(''); print('RESULT: '+pass+' passed, '+fail+' failed'); if (fail) imports.system.exit(1); });
EOF
} > "$JS"
gjs "$JS"
