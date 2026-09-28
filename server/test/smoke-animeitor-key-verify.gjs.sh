#!/bin/bash
# smoke-animeitor-key-verify.gjs.sh — a mesa do telão (web/contest/animeitor/api-section.js) com a CHAVE DO
# MOJ e a CONFERÊNCIA (25/09/2026), com o módulo REAL, API falsa e um DOM falso que dispara eventos:
#   · chave do MOJ: a tela diz "nada a configurar" e a chave própria fica recolhida; nem o usuário aparece;
#   · chave própria: campos + "apagar e usar a chave do MOJ" (manda user/token vazios);
#   · URL digitada fora do servidor padrão: a tela explica que a chave do MOJ não vale lá;
#   · o estado ao vivo diz a conferência (validado / divergência) e "🔎 conferir agora" manda {action:"verify"};
#   · liberar o reveleitor CONFERE antes e põe o resultado na pergunta de confirmação;
#   · o selo da sede (animeitor.js › verifyBadge): validado × conferido × divergência;
#   · o inglês existe (T).
# Sem gjs: pula (rc 0).
set -u
command -v gjs >/dev/null 2>&1 || { echo "animeitor-key-verify: gjs ausente — pulando"; exit 0; }
WEB="$(cd "$(dirname "$(readlink -f "$0")")/../../web" && pwd)"
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
JS="$(mktemp --suffix=.js)"; trap 'rm -f "$JS"' EXIT
{ cat <<'EOF'
function N(tag){ this.tagName=tag; this.nodeType=1; this.children=[]; this.attrs={}; this.style={}; this._ev={}; this.parentNode=null; this._text=''; }
N.prototype.append=function(){ for (const k of arguments) { if (k && typeof k==='object') { k.parentNode=this; this.children.push(k); } else if (k!=null && k!=='') this.children.push({nodeType:3,text:String(k)}); } };
N.prototype.appendChild=function(k){ this.append(k); return k; };
N.prototype.remove=function(){ const p=this.parentNode; if (p) { const i=p.children.indexOf(this); if (i>=0) p.children.splice(i,1); this.parentNode=null; } };
N.prototype.setAttribute=function(k,v){ this.attrs[k]=String(v); };
N.prototype.addEventListener=function(t,f){ (this._ev[t]=this._ev[t]||[]).push(f); };
N.prototype.fire=async function(t){ for (const f of (this._ev[t]||[])) await f({target:this}); };
N.prototype.click=function(){ return this.fire('click'); };
N.prototype.all=function(){ const o=[]; for (const c of this.children) if (c.nodeType===1) { o.push(c); o.push(...c.all()); } return o; };
N.prototype.querySelector=function(sel){ const id=sel.replace(/^#/,''); return this.all().find((n)=>n.attrs.id===id) || null; };
Object.defineProperty(N.prototype,'className',{set(v){this.attrs['class']=v},get(){return this.attrs['class']||''}});
Object.defineProperty(N.prototype,'innerHTML',{set(v){this.children=[]},get(){return ''}});
Object.defineProperty(N.prototype,'textContent',{set(v){this._text=String(v);this.children=[]},
  get(){ let t=this._text; for (const c of this.children) t+= c.nodeType===3 ? c.text : c.textContent; return t; }});
Object.defineProperty(N.prototype,'value',{set(v){this._v=String(v)},get(){ return this._v!==undefined ? this._v : (this.attrs.value||''); }});
for (const p of ['checked','disabled','hidden','open']) Object.defineProperty(N.prototype,p,{set(v){this['_'+p]=!!v},get(){return !!this['_'+p]}});
globalThis.document={ createElement:(t)=>new N(t), createTextNode:(t)=>({nodeType:3,text:String(t),textContent:String(t)}), hidden:false };
globalThis.location={ origin:'https://c.moj.exemplo' };
let LANG='pt'; function T(pt,en,es){ if(LANG==='es') return es!=null?es:(en!=null?en:pt); return LANG==='en' ? (en!=null?en:pt) : pt; }
let DATA=null, POSTS=[], POSTR={}, ASKED=[];
async function apiGet(p){ return JSON.parse(JSON.stringify(DATA)); }
async function apiPost(p,b){ POSTS.push(JSON.parse(JSON.stringify(b))); const r=POSTR[b.action]; return r ? JSON.parse(JSON.stringify(r)) : {}; }
globalThis.confirm=(m)=>{ ASKED.push(m); return true; }; globalThis.prompt=()=>null; globalThis.alert=()=>{};
globalThis.setInterval=()=>1; globalThis.clearInterval=()=>{};
EOF
  strip "$WEB/shared/dom.js"; strip "$WEB/contest/animeitor/api-section.js"
  sed -n '/^function verifyBadge/,/^}/p' "$WEB/contest/animeitor/animeitor.js"
  cat <<'EOF'
let pass=0, fail=0; const ck=(m,ok,d)=>{ if (ok) { print('  ok: '+m); pass++; } else { print('  FAIL: '+m+' :: '+(d||'')); fail++; } };
const flush=async()=>{ for (let i=0;i<40;i++) await Promise.resolve(); };
const btn=(root,txt)=>root.all().find(n=>n.tagName==='button' && n.textContent.includes(txt));
const base=(o)=>Object.assign({ configured:true, has_cred:true, cred_source:'moj', moj_cred:true, default_url:'https://animeitor.naquadah.com.br',
  user:'', url:'https://animeitor.naquadah.com.br', event:'c', moj_base_url:'', enabled:false, feed:{clock_s:1,runs_s:2,verify_s:300},
  secret_contest:false, contests:null, reveal:{released:false}, managed:{event:'c', contests:[]}, status:{}, clock:null, feeder_alive_at:0, now:1000,
  verify:{}, proposal:{teams_total:1, contests:[]} }, o||{});
const NOW=Math.floor(Date.now()/1000);
(async()=>{
  DATA=base(); let s=makeApiSection('c',{}); await s.load(); let t=s.node.textContent;
  ck('chave do MOJ: "nada a configurar", a própria recolhida e nenhum usuário', t.includes('Chave do MOJ') && t.includes('não há nada a configurar') && t.includes('usar uma chave própria') && !t.includes('Chave própria:'), t.slice(0,400));
  ck('estado: ainda não conferido', t.includes('Conferência: ainda não conferido'));
  DATA=base({cred_source:'contest', user:'fulano'}); s=makeApiSection('c',{}); await s.load(); t=s.node.textContent;
  ck('chave própria: campos + botão de voltar à do MOJ', t.includes('Chave própria:') && !!btn(s.node,'apagar e usar a chave do MOJ'));
  POSTS=[]; await btn(s.node,'apagar e usar a chave do MOJ').click(); await flush();
  ck('voltar à do MOJ manda user/token vazios', JSON.stringify(POSTS[0])===JSON.stringify({action:'config',user:'',token:''}), JSON.stringify(POSTS));
  DATA=base({cred_source:'none', configured:false, has_cred:false, url:'https://outro.exemplo'}); s=makeApiSection('c',{}); await s.load(); t=s.node.textContent;
  ck('URL fora do padrão: explica que a chave do MOJ só vale no servidor padrão', t.includes('só vale no servidor padrão (https://animeitor.naquadah.com.br)'));
  DATA=base({verify:{at:NOW, state:'ok', ok:true, final:true, final_at:NOW, checked:120, runs:120, pending:0, uncovered:0}}); s=makeApiSection('c',{}); await s.load(); t=s.node.textContent;
  ck('estado: VALIDADO com as 120 submissões', t.includes('VALIDADO') && t.includes('tem as 120 submissões'), t.slice(-300));
  DATA=base({verify:{at:NOW, state:'diverge', ok:false, final:false, missing:2, wrong:1, extra:0, checked:10, runs:10}}); s=makeApiSection('c',{}); await s.load(); t=s.node.textContent;
  ck('estado: divergência com as contagens', t.includes('2 faltando, 1 diferentes, 0 a mais'));
  POSTS=[]; POSTR.verify={verify:{at:NOW, state:'ok', ok:true, final:false, checked:10, runs:10, pending:0, uncovered:0}, before:{missing:1, wrong:0, extra:0}};
  await btn(s.node,'conferir agora').click(); await flush(); t=s.node.textContent;
  ck('"conferir agora" manda {action:"verify"} e diz o antes', POSTS[0] && POSTS[0].action==='verify' && t.includes('antes: 1 faltando'), JSON.stringify(POSTS)+' '+t.slice(-300));
  POSTS=[]; ASKED=[]; POSTR.verify={verify:{at:NOW, state:'ok', ok:true, final:true, final_at:NOW, checked:10, runs:10, pending:0, uncovered:0}};
  await btn(s.node,'liberar os links de revelação').click(); await flush();
  ck('liberar o reveleitor CONFERE antes (verify, depois reveal-release)', POSTS.map(p=>p.action).join(',')==='verify,reveal-release', POSTS.map(p=>p.action).join(','));
  ck('…e a pergunta traz o resultado da conferência', ASKED.length===1 && ASKED[0].startsWith('Conferência: ✓ VALIDADO'), ASKED[0]);
  const b1=verifyBadge({at:NOW, final:true, final_at:NOW, ok:true}), b2=verifyBadge({at:NOW, ok:true, final:false}), b3=verifyBadge({at:NOW, ok:false, final:false}), b4=verifyBadge({});
  ck('selo da sede: validado · conferido · divergência · ainda não', b1.textContent.includes('Validado') && b2.textContent.includes('Conferido às') && b3.className==='error-box' && b4.textContent.includes('ainda não conferiu'));
  LANG='en'; DATA=base(); s=makeApiSection('c',{}); await s.load(); t=s.node.textContent;
  ck('em inglês', t.includes('MOJ key') && t.includes('there is nothing to configure') && t.includes('Check: not checked yet') && verifyBadge({at:NOW, final:true, ok:true}).textContent.includes('Validated'));
})().catch(e=>{ print('  FAIL: exceção '+e+'\n'+e.stack); fail++; }).finally(()=>{ print(''); print('RESULT: '+pass+' passed, '+fail+' failed'); if (fail) imports.system.exit(1); });
EOF
} > "$JS"
gjs "$JS"
