#!/bin/bash
# smoke-sites-tab.gjs.sh — o painel "Evento › Sedes & escolas" em três modos (web/contest/admin/sites-tab.js),
# com a API simulada. Afirma:
#   • abre no modo guardado se a árvore couber; senão no mais simples que couber (e avisa);
#   • modo que não cabe fica DESABILITADO com o motivo; subir de modo sempre funciona;
#   • a prévia (rgAssign — a regra do servidor) reage ao "começa com" e à atribuição colada;
#   • renomear uma sede leva junto os times GRAVADOS com o nome velho, e a prévia MOSTRA antes de salvar;
#   • salvar = UM POST {tree, mode, expect_sig, assign}; 409 regions_changed vira aviso de recarregar;
#   • árvore com recorte abre no Avançado (o editor de sempre) e os outros modos ficam desabilitados.
set -u
command -v gjs >/dev/null 2>&1 || { echo "sites-tab: gjs ausente — pulando"; exit 0; }
WEB="$(cd "$(dirname "$(readlink -f "$0")")/../../web" && pwd)"
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
JS="$(mktemp --suffix=.js)"; trap 'rm -f "$JS"' EXIT
{ cat <<'EOF'
function N(tag){ this.tagName=tag; this.nodeType=1; this.children=[]; this.attrs={}; this.style={}; this.dataset={}; this._ev={}; this.parentNode=null; this._text=''; }
N.prototype.append=function(){ for (const k of arguments) { if (k && typeof k==='object') { k.parentNode=this; this.children.push(k); } else if (k!=null && k!=='') this.children.push({nodeType:3,text:String(k)}); } };
N.prototype.appendChild=function(k){ this.append(k); return k; };
N.prototype.setAttribute=function(k,v){ this.attrs[k]=String(v); };
N.prototype.addEventListener=function(t,f){ (this._ev[t]=this._ev[t]||[]).push(f); };
N.prototype.fire=function(t){ return Promise.all((this._ev[t]||[]).map(f=>f({target:this, preventDefault(){}}))); };
N.prototype.all=function(){ const o=[]; for (const c of this.children) if (c.nodeType===1) { o.push(c); o.push(...c.all()); } return o; };
Object.defineProperty(N.prototype,'className',{set(v){this.attrs['class']=v},get(){return this.attrs['class']||''}});
Object.defineProperty(N.prototype,'innerHTML',{set(v){this.children=[]},get(){return ''}});
Object.defineProperty(N.prototype,'textContent',{set(v){this._text=String(v);this.children=[]},
  get(){ let t=this._text; for (const c of this.children) t+= c.nodeType===3 ? c.text : c.textContent; return t; }});
Object.defineProperty(N.prototype,'value',{set(v){this._v=String(v)},get(){ return this._v!==undefined ? this._v : (this.attrs.value||''); }});
globalThis.document={ createElement:(t)=>new N(t), createTextNode:(t)=>({nodeType:3,text:String(t),textContent:String(t)}) };
globalThis.setTimeout=(f)=>f();
function T(pt){ return pt; }
class ApiError extends Error { constructor(s,m,c,d){ super(m); this.status=s; this.code=c; this.data=d||{}; } }
let STATE, POSTS=[], NEXT=null;
async function apiGet(path){ if (path.includes('/contest/admin/config')) return {teams_meta:[]};
  if (path.includes('map=1')) return {map: STATE.map}; return {tree: STATE.tree, sig: 'sig1', mode: STATE.mode, summary:{}}; }
async function apiPost(path, body){ POSTS.push({path, body}); if (NEXT) { const e=NEXT; NEXT=null; throw e; } return {saved:true, failed:[]}; }
async function makeTeamsEditor(){ return { el: new N('div'), getValue: () => [] }; }
async function timeOverridesPanel(){ return new N('div'); }
EOF
  strip "$WEB/shared/dom.js"; strip "$WEB/shared/regions-match.js"; strip "$WEB/shared/contest-config/regions.js"
  strip "$WEB/contest/admin/sites-model.js"
  echo 'const SM={ RULE_TYPES, ruleRegex, rulesRegex, nodeRules, fitSimple, toSimple, fromSimple, fitRules, toRules, fromRules, simplestMode, ruleError, renameAssignments };'
  strip "$WEB/contest/admin/sites-tab.js"
  cat <<'EOF'
let pass=0, fail=0; const ck=(m,ok,d)=>{ if (ok) { print('  ok: '+m); pass++; } else { print('  FAIL: '+m+' :: '+(d||'')); fail++; } };
const J=(x)=>JSON.stringify(x);
const btn=(p,txt)=>p.all().filter((n)=>n.tagName==='button' && n.textContent.trim().startsWith(txt))[0];
const inputs=(p)=>p.all().filter((n)=>n.tagName==='input');
(async () => {
  // 1) árvore simples (Curitiba ^ctba, POA ^poa); modo guardado "rules" cabe → abre em rules; Avançado sempre ok
  STATE={ tree:[{name:'Curitiba',regex:'^ctba'},{name:'POA',regex:'^poa'}], mode:'rules',
          map:[{login:'ctba1',site:'Curitiba',flag:'r'},{login:'ctba2',site:'Curitiba',flag:'r'},{login:'poa1',site:'POA',flag:'r'},{login:'xx9',site:'Curitiba',flag:'x'},{login:'zz1',site:null,flag:'-'}] };
  const t=makeSitesTab('c1', {}); await t.load(); const P=t.panel;
  ck('abre no modo GUARDADO (Intermediário) porque a árvore cabe', btn(P,'Intermediário').className==='btn');
  await btn(P,'Simples').fire('click');
  ck('Simples habilitado e clicável', btn(P,'Simples').className==='btn' && !btn(P,'Simples').disabled);
  ck('prévia: 4 de 5 com sede (xx9 gravado em Curitiba conta)', P.textContent.includes('4 de 5 times com sede'), P.textContent.slice(0,300));
  // "começa com" de POA ganha "zz"
  const pf=inputs(P).filter((n)=>n.value==='poa')[0]; pf.value='poa, zz'; await pf.fire('input');
  ck('prévia reage ao "começa com": 5 de 5', P.textContent.includes('5 de 5 times com sede'));
  // renomear Curitiba → CWB leva o gravado (xx9) junto, e a prévia mostra antes de salvar
  const nm=inputs(P).filter((n)=>n.value==='Curitiba')[0]; nm.value='CWB'; await nm.fire('input'); await nm.fire('change');
  ck('renomear: a prévia avisa "1 time(s) gravados mudam de nome junto"', P.textContent.includes('«Curitiba» → «CWB»: 1 time(s) gravados'), P.textContent.slice(-400));
  // colar lista: zz1 → POA
  const ta=P.all().filter((n)=>n.tagName==='textarea')[0]; ta.value='zz1\nninguem';
  const sels=P.all().filter((n)=>n.tagName==='select'); const sel=sels.find((s)=>s.children.some((o)=>o.attrs && o.attrs.value==='POA'));
  sel.value='POA'; await btn(P,'Atribuir').fire('click');
  ck('colar: os dois vão (membro de time não tem pasta — o servidor decide); "ninguem" avisado como sem pasta', P.textContent.includes('2 login(s) atribuído(s)') && P.textContent.includes('sem pasta no contest') && P.textContent.includes(': ninguem'));
  await btn(P,'Salvar sedes').fire('click');
  const b=POSTS[POSTS.length-1].body;
  ck('salvar = UM POST com a árvore nova, o modo, o sig lido e as atribuições (renomeio + colado)',
    POSTS[POSTS.length-1].path.includes('/contest/admin/regions?contest=c1') && b.mode==='simple' && b.expect_sig==='sig1'
    && J(b.tree.map((n)=>[n.name,n.regex]))===J([['CWB','^ctba'],['POA','^(poa|zz)']])
    && J(b.assign.sort((x,y)=>x.login<y.login?-1:1))===J([{login:'ninguem',region:'POA'},{login:'xx9',region:'CWB'},{login:'zz1',region:'POA'}]), J(b));
  // 409
  NEXT=new ApiError(409,'mudou','regions_changed',{sig:'sig2'});
  const nm2=inputs(P)[0]; nm2.value='CWB2'; await nm2.fire('input');
  await btn(P,'Salvar sedes').fire('click');
  ck('409 regions_changed: aviso de recarregar', P.textContent.includes('mudaram em outra aba ou pela CLI'));
  // 2) árvore com recorte: só o Avançado; Simples/Intermediário desabilitados com o motivo
  STATE={ tree:[{name:'Brasil',regex:'^br',subregions:[{name:'DF',regex:'^brdf'}]},{name:'Fem',view:true,regex:'^f'}], mode:'simple', map:[{login:'brdf1',site:'DF',flag:'r'}] };
  const t2=makeSitesTab('c2', {}); await t2.load(); const P2=t2.panel;
  ck('árvore com recorte: modo guardado (Simples) não cabe → abre no Avançado e avisa', btn(P2,'Avançado').className==='btn' && P2.textContent.includes('não cabe mais no modo guardado'));
  ck('Simples e Intermediário desabilitados com o motivo', btn(P2,'Simples').disabled && btn(P2,'Simples').attrs.title.includes('Não cabe neste modo: a árvore tem subregiões') && btn(P2,'Intermediário').disabled);
  ck('prévia do Avançado: Brasil › DF com 1', P2.textContent.includes('1 de 1 times com sede'));
  // 2b) Avançado com árvore que cabe no Intermediário: editar o JSON (acrescentar um recorte) desabilita o
  //     Intermediário NA HORA — senão voltar p/ ele perderia a regex do recorte
  const bubble=async (n,t)=>{ for (let x=n; x; x=x.parentNode) await x.fire(t); };
  STATE={ tree:[{name:'G',subregions:[{name:'S',regex:'^s'}]}], mode:'tree', map:[{login:'s1',site:'S',flag:'r'}] };
  const t4=makeSitesTab('c4', {}); await t4.load(); const P4=t4.panel;
  ck('Avançado (guardado) com a árvore cabendo no Intermediário: Intermediário habilitado', btn(P4,'Avançado').className==='btn' && !btn(P4,'Intermediário').disabled);
  const ta4=P4.all().filter((n)=>n.tagName==='textarea')[0];
  ta4.value='[{"name":"G","subregions":[{"name":"S","regex":"^s"}]},{"name":"V","view":true,"regex":"^v"}]'; await bubble(ta4,'input');
  ck('…JSON ganha um recorte: Intermediário DESABILITADO na hora, com o motivo', btn(P4,'Intermediário').disabled && btn(P4,'Intermediário').attrs.title.includes('recortes'), btn(P4,'Intermediário').attrs.title);
  // 3) grupos › sedes: Intermediário; regra nova com erro de regex aparece inline
  STATE={ tree:[{name:'Sul',subregions:[{name:'CTBA',regex:'^ctba'}]}], mode:'', map:[{login:'ctba1',site:'CTBA',flag:'r'}] };
  const t3=makeSitesTab('c3', {}); await t3.load(); const P3=t3.panel;
  ck('grupos › sedes abre no Intermediário (o mais simples que cabe)', btn(P3,'Intermediário').className==='btn' && btn(P3,'Simples').disabled);
  await btn(P3,'+ regra').fire('click');
  const v=inputs(P3).filter((n)=>(n.attrs.placeholder||'').startsWith('valores'))[1]; v.value='são'; await v.fire('input');
  ck('regra com texto não-ASCII: o erro aparece na linha (traduzido)', P3.textContent.includes('só caracteres ASCII'), P3.textContent.slice(-300));
  print(''); print('RESULT: '+pass+' passed, '+fail+' failed'); imports.system.exit(fail>0?1:0);
})().catch((e)=>{ print('ERRO: '+e+'\n'+e.stack); imports.system.exit(2); });
EOF
} > "$JS"
gjs "$JS"
