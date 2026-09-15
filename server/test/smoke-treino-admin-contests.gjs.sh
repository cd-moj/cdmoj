#!/bin/bash
# smoke-treino-admin-contests.gjs.sh — a aba 🏆 Contests do painel do treino (web/treino/admin/admin.js)
# renderiza o escopo, o dono resolvido (nome + link de perfil), os filtros em memória e as listas de
# permissão com trilha (quem liberou/quando). Roda o módulo REAL no gjs com DOM falso e API canned.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
W="$ROOT/web"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "treino-admin-contests(gjs): gjs ausente — pulando"; exit 0; }
PASS=0; FAIL=0
check(){ if [[ "$1" == "$2" ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: $3 (got '$1', want '$2')" >&2; fi; }
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
{ cat <<'JS'
function FakeNode(tag){ this.tagName=tag; this.nodeType=1; this.children=[]; this.attrs={}; this.dataset={}; this.style={}; this._ev={}; this._cls=new Set(); this._text=''; }
FakeNode.prototype.append=function(){ for (const k of arguments) { if (k==null||k==='') continue; this.children.push(typeof k==='object'?k:{nodeType:3,text:String(k)}); } };
FakeNode.prototype.appendChild=FakeNode.prototype.append;
FakeNode.prototype.setAttribute=function(k,v){ if(k==='class') this._cls=new Set(String(v).split(/\s+/).filter(Boolean)); this.attrs[k]=v; };
FakeNode.prototype.getAttribute=function(k){ return k in this.attrs ? this.attrs[k] : null; };
FakeNode.prototype.addEventListener=function(t,f){ (this._ev[t]=this._ev[t]||[]).push(f); };
FakeNode.prototype.fire=function(t){ for (const f of (this._ev[t]||[])) f({}); };
FakeNode.prototype.remove=function(){ if (this.parent) this.parent.children=this.parent.children.filter(c=>c!==this); };
FakeNode.prototype.focus=function(){};
FakeNode.prototype._all=function(){ const o=[]; for (const c of this.children) if (c.nodeType===1){ c.parent=this; o.push(c); o.push(...c._all()); } return o; };
FakeNode.prototype.querySelectorAll=function(sel){ if (sel[0]==='.') { const cls=sel.slice(1); return this._all().filter(n=>n._cls.has(cls)); } return this._all().filter(n=>n.tagName===sel); };
FakeNode.prototype.querySelector=function(sel){ return this.querySelectorAll(sel)[0]||null; };
Object.defineProperty(FakeNode.prototype,'className',{set(v){this.setAttribute('class',v)},get(){return [...this._cls].join(' ')}});
Object.defineProperty(FakeNode.prototype,'classList',{get(){ const s=this._cls; return { contains:(c)=>s.has(c), toggle:(c,on)=>{ if(on===undefined) on=!s.has(c); on?s.add(c):s.delete(c); return on; }, add:(c)=>s.add(c), remove:(c)=>s.delete(c) }; }});
Object.defineProperty(FakeNode.prototype,'textContent',{ set(v){this._text=String(v); this.children=[];}, get(){ let t=this._text; for(const c of this.children) t+= c.nodeType===3?c.text:(c.textContent||''); return t; }});
Object.defineProperty(FakeNode.prototype,'innerHTML',{ set(v){this._html=v; this.children=[];}, get(){ return this._html||''; }});
Object.defineProperty(FakeNode.prototype,'value',{get(){return this._v||''},set(v){this._v=String(v)}});
Object.defineProperty(FakeNode.prototype,'checked',{get(){return !!this._c},set(v){this._c=v}});
Object.defineProperty(FakeNode.prototype,'disabled',{get(){return !!this._d},set(v){this._d=v}});
globalThis.document={ createElement:(t)=>new FakeNode(t), createTextNode:(t)=>({nodeType:3,text:String(t)}), getElementById:()=>new FakeNode('div'), activeElement:null, body:new FakeNode('body') };
globalThis.location={ reload(){}, hash:'', search:'' }; globalThis.confirm=()=>true; globalThis.alert=()=>{};
globalThis.localStorage={ getItem:()=>null, setItem(){} }; globalThis.navigator={language:'pt-BR'};
// stubs dos imports do admin.js
const T=(pt,en)=>pt; const getToken=()=>'t'; const status=async()=>({logged_in:false}); const renderAuthArea=async()=>{};
const barChart=()=>new FakeNode('svg'), hBarChart=barChart, lineChart=barChart, heatmap=barChart, heatmapGrid=barChart, openHtmlReport=()=>{};
const fmtDate=(e)=>'D'+e; const avatarEl=(login,name)=>{ const n=new FakeNode('img'); n.setAttribute('alt',name||login); return n; };
const NOW=Math.floor(Date.now()/1000);
const CONTESTS={ contests:[
  {id:'c-a',name:'Prova do A',mode:'icpc',owner:'a.admin',owner_name:'Prof A',owner_has_photo:false,owner_is_admin:true,created_at:NOW-10,start:NOW-3600,end:NOW+3600,problems_count:3},
  {id:'c-m',name:'Lista do Maker',mode:'treino',owner:'maker',owner_name:'Maker Person',owner_has_photo:true,owner_is_admin:false,created_at:NOW-20,start:NOW-99999,end:NOW-9999,problems_count:1},
], count:2, scope:'all', me:'a.admin', is_superadmin:true };
const PERMS={ perms:{threshold:3,allow:['maker','ghost'],deny:['nobody'],allow_meta:{},deny_meta:{}},
  allow_info:[{login:'maker',name:'Maker Person',has_photo:false,by:'super.admin',by_name:'Super Admin',at:NOW-5,note:'monitor'},{login:'ghost',name:null,has_photo:false,by:null,by_name:null,at:null,note:''}],
  deny_info:[{login:'nobody',name:'No Body',has_photo:false,by:'a.admin',by_name:'Prof A',at:NOW-3,note:'spam'}], me:'a.admin' };
const POSTS=[];
const apiGet=async(path)=> path.startsWith('/treino/admin/contests') ? CONTESTS : path.startsWith('/treino/admin/contest-perms') ? PERMS : {};
const apiPost=async(path,body)=>{ POSTS.push(body); return PERMS; };
JS
  strip "$W/shared/dom.js"
  strip "$W/treino/admin/admin.js" | sed 's/^boot();$//'
  cat <<'JS'
// gjs sem mainloop: setTimeout nunca dispara — drena MICROTAREFAS (as awaits dos stubs de API)
const tick = async () => { for (let i = 0; i < 20; i++) await Promise.resolve(); };
(async () => {
  const tab = makeContestsTab(); tab.load(); await tick();
  const txt = tab.panel.textContent;
  const has = (s) => txt.includes(s);
  print('scope_super=' + has('super-admin'));
  print('owner_name=' + has('Prof A') + ' owner_login=' + has('a.admin') + ' owner_admin_pill=' + (tab.panel.querySelectorAll('.pill').length===1));
  const links = tab.panel.querySelectorAll('a').map(a=>a.attrs.href||'');
  print('profile_links=' + links.filter(h=>h.startsWith('/treino/stat/?user=')).length);
  print('count=' + txt.match(/(\d+ de \d+)/)[1]);
  print('remove_buttons=' + tab.panel.querySelectorAll('button').filter(b=>b.textContent==='Remover').length);
  print('perm_trail=' + (has('Maker Person') && has('Super Admin') && has('monitor') && has('spam')) + ' ghost=' + has('conta não existe'));
  // filtros em memória (sem rede): busca + situação
  const inputs = tab.panel.querySelectorAll('input'); const q = inputs.find(i=>(i.attrs.placeholder||'').startsWith('buscar'));
  q.value='maker'; q.fire('input'); print('q_maker=' + tab.panel.textContent.match(/(\d+ de \d+)/)[1]);
  q.value=''; q.fire('input');
  const sel = tab.panel.querySelectorAll('select'); const statusSel = sel.find(s=>s.children.some(o=>o.attrs.value==='ended'));
  statusSel.value='ended'; statusSel.fire('change'); print('ended=' + tab.panel.textContent.match(/(\d+ de \d+)/)[1] + ' ended_is_maker=' + tab.panel.textContent.includes('Lista do Maker') + ',' + !tab.panel.textContent.includes('Prova do A'));
  statusSel.value=''; statusSel.fire('change');
  // adicionar à allow manda a ação certa
  const login = inputs.find(i=>i.attrs.placeholder==='login'); login.value='fulano';
  const addBtn = tab.panel.querySelectorAll('button').find(b=>b.textContent.includes('Liberar')); addBtn._ev.click[0](); await tick();
  print('post_add=' + JSON.stringify(POSTS[0]));
  // como admin comum: só os próprios removem, e o aviso muda
  CONTESTS.is_superadmin=false; CONTESTS.scope='admin'; tab.load(); await tick();
  print('scope_admin=' + tab.panel.textContent.includes('outros administradores não aparecem') + ' remove_admin=' + tab.panel.querySelectorAll('button').filter(b=>b.textContent==='Remover').length);
})().catch(e => { print('ERRO ' + e + '\n' + (e.stack||'')); });
JS
} > "$T/tab.js"
out="$(timeout 60 gjs "$T/tab.js" 2>&1)" || { echo "$out" >&2; echo "treino-admin-contests(gjs): gjs falhou"; exit 1; }
grep -q '^ERRO' <<<"$out" && { echo "$out" >&2; exit 1; }
kv(){ sed -n "s/^.*\b$1=\([^ ]*\).*$/\1/p" <<<"$out" | head -1; }
check "$(kv scope_super)" true "aviso de super-admin"
check "$(kv owner_name)" true "dono resolvido p/ nome"
check "$(kv owner_login)" true "login do dono visível"
check "$(kv owner_admin_pill)" true "selo admin no dono .admin (1 só)"
check "$(kv profile_links)" 7 "links de perfil (2 donos + 3 pessoas das listas + 2 de quem liberou/bloqueou)"
check "$(sed -n 's/^count=\(.*\)$/\1/p' <<<"$out")" "2 de 2" "contador"
check "$(kv remove_buttons)" 2 "super-admin: Remover em todos"
check "$(kv perm_trail)" true "trilha: pessoa, quem liberou, nota"
check "$(kv ghost)" true "login sem conta marcado"
check "$(sed -n 's/^q_maker=\(.*\)$/\1/p' <<<"$out")" "1 de 2" "busca por dono filtra"
check "$(sed -n 's/^ended=\([0-9]* de [0-9]*\).*$/\1/p' <<<"$out")" "1 de 2" "situação encerrado filtra"
check "$(kv ended_is_maker)" "true,true" "…e sobra o encerrado"
check "$(kv post_add)" '{"action":"add","list":"allow","login":"fulano","note":""}' "Liberar manda action add"
check "$(kv scope_admin)" true "admin comum: aviso do escopo"
check "$(kv remove_admin)" 1 "admin comum: Remover só no seu"
echo "treino-admin-contests(gjs): $PASS ok, $FAIL falhas"; [[ $FAIL -eq 0 ]]
