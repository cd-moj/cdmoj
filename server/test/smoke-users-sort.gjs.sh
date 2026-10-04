#!/bin/bash
# smoke-users-sort.gjs.sh — ordenação por coluna em "Pessoas › Contas" (web/contest/admin/users-tab.js).
# Monta a aba com a API simulada e clica nos cabeçalhos. Afirma:
#   • sem clique, a ordem é a do servidor (nada muda para quem não ordena);
#   • Login: ordem natural ("aluno2" antes de "aluno10"), 2º clique inverte, com ▲/▼ no cabeçalho;
#   • Nome: ignora caixa e acento ("Álvaro" entre "alice" e "bruno");
#   • Email: conta sem email vai para o FIM nas duas direções;
#   • ordena ANTES do corte de 300: com 305 contas, o 1º da ordem real aparece mesmo fora dos 300;
#   • o filtro de texto re-renderiza mantendo a ordenação escolhida.
set -u
command -v gjs >/dev/null 2>&1 || { echo "users-sort: gjs ausente — pulando"; exit 0; }
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
let USERS_API=[];                              // a API simulada: GET /contest/admin/users devolve USERS_API
async function apiGet(){ return { users: USERS_API }; }
async function apiPost(){ return {}; }
function parseUsers(){ return []; } function parseRichCsv(){ return null; } function downloadCsv(){}
const NAME_COLON="\u2236"; function colonQ(q){ return String(q||"").replace(/:/g, NAME_COLON); } function colonNote(){ return ""; } function skipReason(r){ return r; }
const PRIV=/\.(admin|judge|cjudge|staff|cstaff|mon)$/;
function mkBool(){ return document.createElement('input'); }
function makeConvertCard(){ return { el: document.createElement('div'), show(){} }; }
EOF
  strip "$WEB/shared/dom.js"; strip "$WEB/contest/admin/users-tab.js"
  cat <<'EOF'
let pass=0, fail=0; const ck=(m,ok,d)=>{ if (ok) { print('  ok: '+m); pass++; } else { print('  FAIL: '+m+' :: '+(d||'')); fail++; } };
const J=(x)=>JSON.stringify(x);
// primeira coluna de cada linha = o login (o texto antes dos selos)
const rows=(t)=>t.panel.all().filter(n=>n.tagName==='tbody')[0].children.map(tr=>tr.children[0].children[0].text);
const col=(t,i)=>t.panel.all().filter(n=>n.tagName==='tbody')[0].children.map(tr=>tr.children[i].textContent);
const head=(t,txt)=>t.panel.all().filter(n=>n.tagName==='th' && n.textContent.startsWith(txt))[0];
(async () => {
  USERS_API=[
    {login:'aluno10', fullname:'bruno', email:'b@x'},
    {login:'aluno2',  fullname:'Álvaro', email:''},
    {login:'aluno1',  fullname:'alice', email:'c@x'},
    {login:'prof.admin', fullname:'', email:'a@x', admin:true},
  ];
  const t=makeUsersTab('c'); await t.load();
  ck('sem clique: ordem do servidor', J(rows(t))===J(['aluno10','aluno2','aluno1','prof.admin']), J(rows(t)));
  await head(t,'Login').fire('click');
  ck('Login ▲: ordem natural (aluno2 antes de aluno10)', J(rows(t))===J(['aluno1','aluno2','aluno10','prof.admin']), J(rows(t)));
  ck('cabeçalho mostra ▲', head(t,'Login').textContent==='Login ▲', head(t,'Login').textContent);
  await head(t,'Login').fire('click');
  ck('2º clique inverte (▼)', J(rows(t))===J(['prof.admin','aluno10','aluno2','aluno1']) && head(t,'Login').textContent==='Login ▼', J(rows(t)));
  await head(t,'Nome').fire('click');
  ck('Nome: sem caixa/acento, vazio no fim', J(col(t,1))===J(['alice','Álvaro','bruno','']), J(col(t,1)));
  ck('trocar de coluna volta a ▲ e tira a seta da anterior', head(t,'Nome').textContent==='Nome ▲' && head(t,'Login').textContent==='Login', head(t,'Login').textContent);
  await head(t,'Email').fire('click');
  ck('Email ▲: sem email no fim', J(col(t,2))===J(['a@x','b@x','c@x','']), J(col(t,2)));
  await head(t,'Email').fire('click');
  ck('Email ▼: sem email CONTINUA no fim', J(col(t,2))===J(['c@x','b@x','a@x','']), J(col(t,2)));
  // filtro re-renderiza mantendo a ordenação
  const q=t.panel.all().filter(n=>n.tagName==='input' && n.attrs.type==='search')[0];
  q.value='aluno'; await q.fire('input');
  ck('filtro mantém a ordenação (Email ▼)', J(rows(t))===J(['aluno1','aluno10','aluno2']), J(rows(t)));
  // ordena antes do corte de 300
  USERS_API=[]; for (let i=1;i<=305;i++) USERS_API.push({login:'u'+i, fullname:'', email:''});
  const t2=makeUsersTab('c2'); await t2.load();
  ck('305 contas: mostra 300', rows(t2).length===300, rows(t2).length);
  await head(t2,'Login').fire('click'); await head(t2,'Login').fire('click');
  ck('Login ▼ com 305: o 1º é u305, que estava fora dos 300', rows(t2)[0]==='u305' && rows(t2).length===300, rows(t2)[0]);
  print(''); print('RESULT: '+pass+' passed, '+fail+' failed');
  imports.system.exit(fail>0?1:0);
})().catch(e=>{ print('ERRO: '+e+'\n'+e.stack); imports.system.exit(2); });
EOF
} > "$JS"
gjs "$JS"
