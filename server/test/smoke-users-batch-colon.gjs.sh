#!/bin/bash
# smoke-users-batch-colon.gjs.sh — o LOTE de contas (web/shared/users-batch.js + a prévia de users-tab.js), depois do
# relato do TCP 2026 (04/10/2026): `localhost:6767` e `HelloWorld"(print)"` "não entravam" e ninguém dizia por quê.
#   • aspa no MEIO do campo é texto (o CSV comia as aspas; aspa sem par juntava colunas); "a, b" segue valendo;
#   • linha com ':' sem cabeçalho é login:senha:nome:email — `localhost:6767` = login+senha (fmt 'colon');
#   • a PRÉVIA mostra como cada linha foi lida (senha •••• / "(= login)" / nome com ':' já como '∶') + o aviso;
#   • o resultado lista cada linha PULADA com o motivo e os nomes AJUSTADOS (de → para);
#   • a busca com ':' acha o nome gravado com '∶'.
set -u
command -v gjs >/dev/null 2>&1 || { echo "users-batch: gjs ausente — pulando"; exit 0; }
WEB="$(cd "$(dirname "$(readlink -f "$0")")/../../web" && pwd)"
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
JS="$(mktemp --suffix=.js)"; trap 'rm -f "$JS"' EXIT
{ cat <<'EOF'
function N(tag){ this.tagName=tag; this.nodeType=1; this.children=[]; this.attrs={}; this.style={}; this._ev={}; this.parentNode=null; this._text=''; }
N.prototype.append=function(){ for (const k of arguments) { if (k && typeof k==='object') { k.parentNode=this; this.children.push(k); } else if (k!=null) this.children.push({nodeType:3,text:String(k)}); } };
N.prototype.setAttribute=function(k,v){ this.attrs[k]=String(v); };
N.prototype.addEventListener=function(t,f){ (this._ev[t]=this._ev[t]||[]).push(f); };
N.prototype.fire=function(t){ return Promise.all((this._ev[t]||[]).map(f=>f({target:this, preventDefault(){}}))); };
N.prototype.all=function(){ const o=[]; for (const c of this.children) if (c.nodeType===1) { o.push(c); o.push(...c.all()); } return o; };
N.prototype.focus=function(){};
Object.defineProperty(N.prototype,'className',{set(v){this.attrs['class']=v},get(){return this.attrs['class']||''}});
Object.defineProperty(N.prototype,'innerHTML',{set(v){this.children=[]},get(){return ''}});
Object.defineProperty(N.prototype,'textContent',{set(v){this._text=String(v);this.children=[]},
  get(){ let t=this._text; for (const c of this.children) t+= c.nodeType===3 ? c.text : c.textContent; return t; }});
Object.defineProperty(N.prototype,'value',{set(v){this._v=String(v)},get(){ return this._v!==undefined ? this._v : (this.attrs.value||''); }});
globalThis.document={ createElement:(t)=>new N(t), createTextNode:(t)=>({nodeType:3,text:String(t),textContent:String(t)}) };
function T(pt){ return pt; }
let USERS_API=[], POSTED=[], BULK={};
async function apiGet(){ return { users: USERS_API }; }
async function apiPost(path, body){ POSTED.push([path, body]); return path.includes('users-bulk') ? BULK : {}; }
const PRIV=/\.(admin|judge|cjudge|staff|cstaff|mon)$/;
function mkBool(){ return document.createElement('input'); }
function makeConvertCard(){ return { el: document.createElement('div'), show(){} }; }
EOF
  strip "$WEB/shared/dom.js"; strip "$WEB/shared/users-batch.js"; strip "$WEB/contest/admin/users-tab.js"
  cat <<'EOF'
let pass=0, fail=0; const ck=(m,ok,d)=>{ if (ok) { print('  ok: '+m); pass++; } else { print('  FAIL: '+m+' :: '+(d||'')); fail++; } };
const J=(x)=>JSON.stringify(x);
(async () => {
  // --- parser ---------------------------------------------------------------------------------
  const rich = parseRichCsv('login,nome,univ\nt1,HelloWorld"(print)",UnB\nt2,"Univ, Darcy",X\nt3,abre"aspa,UFG');
  ck('aspa no meio do nome é texto', rich[0].fullname==='HelloWorld"(print)"', J(rich[0]));
  ck('campo entre aspas com vírgula segue valendo', rich[1].fullname==='Univ, Darcy' && rich[1].univ_short==='X', J(rich[1]));
  ck('aspa sem par NÃO junta as colunas seguintes', rich[2].fullname==='abre"aspa' && rich[2].univ_short==='UFG', J(rich[2]));
  const cl = parseUsers('localhost:6767\nHelloWorld"(print)"\nlogin1,Nome Um');
  ck('linha com ":" sem cabeçalho = login:senha (fmt colon)', cl[0].login==='localhost' && cl[0].password==='6767' && cl[0].fullname==='' && cl[0].fmt==='colon', J(cl[0]));
  ck('nome solto = fmt name, login do slug', cl[1].fullname==='HelloWorld"(print)"' && cl[1].fmt==='name' && cl[1].login==='helloworldprint', J(cl[1]));
  ck('colonQ: ":" acha o "∶"', colonQ('a:b')==='a∶b');
  ck('colonNote só com ":"', colonNote('a:b').includes('∶') && colonNote('ab')==='');
  ck('skipReason: motivo legível; desconhecido = inválido', skipReason('colon').includes(':') && skipReason('login_invalid').startsWith('login inválido') && skipReason('xyz')==='inválido');
  // --- prévia + resultado na aba ------------------------------------------------------------------
  USERS_API=[{login:'t3', fullname:'a∶b', email:''}, {login:'z', fullname:'outro', email:''}];
  const t=makeUsersTab('c'); await t.load();
  const ta=t.panel.all().filter(n=>n.tagName==='textarea')[0];
  const btn=(txt)=>t.panel.all().filter(n=>n.tagName==='button' && n.textContent===txt)[0];
  ta.value='localhost:6767\nHelloWorld"(print)"\nlogin,senha,nome'; await btn('Processar').fire('click');
  let tbodies=t.panel.all().filter(n=>n.tagName==='tbody');
  const prevT=tbodies[tbodies.length-1];
  const cells=(i)=>prevT.children[i].children.map(td=>td.textContent);
  ck('prévia: localhost = login+senha, nome "(= login)"', J(cells(0))===J(['localhost','••••','(= login)','']), J(cells(0)));
  ck('prévia: aspas intactas, senha "(gerada)"', cells(1)[2]==='HelloWorld"(print)"' && cells(1)[1]==='(gerada)', J(cells(1)));
  ck('prévia avisa da linha com ":" sem cabeçalho', t.panel.textContent.includes('é lida como login:senha:nome:email'));
  ta.value='login,nome\nt9,localhost:6767'; await btn('Processar').fire('click');
  tbodies=t.panel.all().filter(n=>n.tagName==='tbody');
  ck('prévia (CSV): nome com ":" já aparece com "∶" + ⚠', tbodies[tbodies.length-1].children[0].children[2].textContent==='localhost∶6767 ⚠');
  BULK={ counts:{created:1, updated:0, skipped:2, adjusted:1}, created:[{login:'t9',password:'p',fullname:'localhost∶6767'}],
         skipped:[{login:'t4',reason:'colon'},{login:'bad x',reason:'login_invalid'}], adjusted:[{login:'t9',field:'fullname',from:'localhost:6767',to:'localhost∶6767'}] };
  await btn('Enviar lote').fire('click'); for (let i=0;i<40;i++) await Promise.resolve();
  const body=POSTED.filter(p=>p[0].includes('users-bulk')).pop()[1];
  ck('envia o nome cru (o servidor ajusta)', body.users[0].fullname==='localhost:6767', J(body.users[0]));
  const txt=t.panel.textContent;
  ck('resultado lista os pulados com o motivo', txt.includes('Pulados:') && txt.includes('t4 — senha ou email com “:”') && txt.includes('bad x — login inválido'), txt.slice(-400));
  ck('resultado lista os nomes ajustados', txt.includes('Nomes ajustados:') && txt.includes('“localhost:6767” → “localhost∶6767”'));
  // --- busca ------------------------------------------------------------------------------------
  const q=t.panel.all().filter(n=>n.tagName==='input' && n.attrs.type==='search')[0];
  q.value='a:b'; await q.fire('input');
  tbodies=t.panel.all().filter(n=>n.tagName==='tbody');
  const listT=tbodies[0];
  ck('busca "a:b" acha o nome gravado "a∶b"', listT.children.length===1 && listT.children[0].textContent.includes('t3'), listT.children.length);
  print(''); print('RESULT: '+pass+' passed, '+fail+' failed');
  imports.system.exit(fail>0?1:0);
})().catch(e=>{ print('ERRO: '+e+'\n'+e.stack); imports.system.exit(2); });
EOF
} > "$JS"
gjs -m "$JS" 2>&1 || gjs "$JS"
