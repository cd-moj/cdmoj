#!/bin/bash
# smoke-docs-tab.gjs.sh — a área "📄 Documentos" (web/contest/admin/docs-tab.js: admin e juiz-chefe) com o
# módulo REAL, API/editor falsos e um DOM falso que dispara eventos (25/09/2026):
#   · documento gerado com .odt ganha o botão "✎ .odt" (e ele pede fmt=odt); sem .odt, não;
#   · os TEMPLATES (capa, info sheet) usam o editor do MOJ (createEditor, modo markdown) com UMA ABA por
#     idioma (as fichas .stmt-chip da gestão de problemas); a capa ABRE com o texto padrão (vem da API);
#     trocar de aba não perde o digitado; o estado "padrão/editado" e a capa em PDF são do idioma da aba;
#   · Salvar manda SÓ os idiomas alterados (nada mudou = nada enviado); "voltar ao padrão" manda "".
# Sem gjs: pula (rc 0).
set -u
command -v gjs >/dev/null 2>&1 || { echo "docs-tab: gjs ausente — pulando"; exit 0; }
WEB="$(cd "$(dirname "$(readlink -f "$0")")/../../web" && pwd)"
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
JS="$(mktemp --suffix=.js)"; trap 'rm -f "$JS"' EXIT
{ cat <<'EOF'
function N(tag){ this.tagName=tag; this.nodeType=1; this.children=[]; this.attrs={}; this.style={}; this._ev={}; this.parentNode=null; this._text=''; }
N.prototype.append=function(){ for (const k of arguments) { if (k && typeof k==='object') { k.parentNode=this; this.children.push(k); } else if (k!=null) this.children.push({nodeType:3,text:String(k)}); } };
N.prototype.appendChild=function(k){ this.append(k); return k; };
N.prototype.remove=function(){ const p=this.parentNode; if (p) { const i=p.children.indexOf(this); if (i>=0) p.children.splice(i,1); this.parentNode=null; } };
N.prototype.setAttribute=function(k,v){ this.attrs[k]=String(v); };
N.prototype.addEventListener=function(t,f){ (this._ev[t]=this._ev[t]||[]).push(f); };
N.prototype.fire=async function(t){ for (const f of (this._ev[t]||[])) await f({target:this}); };
N.prototype.click=function(){ return this.fire('click'); };
N.prototype.all=function(){ const o=[]; for (const c of this.children) if (c.nodeType===1) { o.push(c); o.push(...c.all()); } return o; };
Object.defineProperty(N.prototype,'className',{set(v){this.attrs['class']=v},get(){return this.attrs['class']||''}});
Object.defineProperty(N.prototype,'innerHTML',{set(v){this.children=[]},get(){return ''}});
Object.defineProperty(N.prototype,'textContent',{set(v){this._text=String(v);this.children=[]},
  get(){ let t=this._text; for (const c of this.children) t+= c.nodeType===3 ? c.text : c.textContent; return t; }});
Object.defineProperty(N.prototype,'value',{set(v){this._v=String(v)},get(){ return this._v!==undefined ? this._v : (this.attrs.value||''); }});
for (const p of ['checked','disabled','hidden']) Object.defineProperty(N.prototype,p,{set(v){this['_'+p]=!!v},get(){return !!this['_'+p]}});
globalThis.document={ createElement:(t)=>new N(t), createTextNode:(t)=>({nodeType:3,text:String(t),textContent:String(t)}), body:new N('body') };
let LANG='pt'; function T(pt,en,es){ if(LANG==='es') return es!=null?es:(en!=null?en:pt); return LANG==='en' ? (en!=null?en:pt) : pt; }
let DATA=null, POSTS=[], FETCHES=[];
async function apiGet(p){ return JSON.parse(JSON.stringify(DATA)); }
async function apiPost(p,b){ POSTS.push(JSON.parse(JSON.stringify(b))); return {}; }
const getToken=()=>'tk', fileToBase64=async()=>'', fmtDate=(x)=>'d'+x, fmtKB=(x)=>x+'B';
globalThis.fetch=async(u)=>{ FETCHES.push(u); return { ok:true, status:200, blob:async()=>({}) }; };
globalThis.URL={ createObjectURL:()=>'blob:x', revokeObjectURL:()=>{} };
globalThis.setTimeout=(f)=>{ f(); return 1; };
globalThis.alert=()=>{}; let ASK=true; globalThis.confirm=()=>ASK; globalThis.window={ open:()=>null };
// o editor do MOJ, falso: registra cada editor com o texto inicial e o modo
const EDS=[];
async function createEditor(m,{doc='',cm}={}){ const n=document.createElement('pre'); n.textContent=doc; m.append(n); let v=doc;
  const ed={ cm, mount:m, init:doc, getValue:()=>v, setValue:(x)=>{ v=x; n.textContent=x; } }; EDS.push(ed); return ed; }
EOF
  strip "$WEB/shared/dom.js"; strip "$WEB/contest/admin/docs-tab.js"
  cat <<'EOF'
let pass=0, fail=0; const ck=(m,ok,d)=>{ if (ok) { print('  ok: '+m); pass++; } else { print('  FAIL: '+m+' :: '+(d||'')); fail++; } };
const flush=async()=>{ for (let i=0;i<40;i++) await Promise.resolve(); };
DATA={ docs:[{type:'contest',lang:'pt',html_bytes:10,pdf_bytes:100,odt_bytes:50,generated_at:1,published:false,uploaded:false},
             {type:'times',lang:'pt',html_bytes:5,pdf_bytes:10,odt_bytes:0,generated_at:1,published:false,uploaded:false}],
  config:{}, problems:[], langs:['pt','en','es'],
  templates:{ cover:{pt:'# PT capa padrão',en:'# EN capa do contest',es:'# ES capa'}, info_sheet:{pt:'info pt',en:'info en',es:'info es'} },
  custom:{ cover:{pt:false,en:true,es:false}, info_sheet:{pt:false,en:false,es:false} }, cover_uploaded:{pt:false,en:true,es:false} };
const btn=(root,txt)=>root.all().filter(n=>n.tagName==='button' && n.textContent===txt);
(async()=>{
  const tab=makeDocsTab('c'); await tab.load(); await flush();
  const P=tab.panel;
  const odt=btn(P,'✎ .odt');
  ck('documento com .odt ganha o botão "✎ .odt" (só ele: a folha de TL não tem)', odt.length===1, String(odt.length));
  await odt[0].click(); await flush();
  ck('o botão baixa com fmt=odt', FETCHES.some(u=>u.includes('type=contest') && u.includes('lang=pt') && u.includes('fmt=odt')), JSON.stringify(FETCHES));
  const boxes=P.all().filter(n=>n.className==='subcard' && n.textContent.includes('Capa do caderno'));
  const cover=boxes[boxes.length-1];
  const chips=cover.all().filter(n=>n.tagName==='button' && n.className.startsWith('stmt-chip'));
  ck('capa: uma aba por idioma (PT, EN, ES), PT ativa', chips.map(c=>c.textContent).join(',')==='PT,EN,ES' && chips[0].className.includes('active'), chips.map(c=>c.textContent+':'+c.className).join(' '));
  const edPT=EDS.find(e=>e.init==='# PT capa padrão');
  ck('capa PT ABRE com o texto padrão, no editor do MOJ (markdown)', !!edPT && edPT.cm==='markdown' && cover.textContent.includes('texto padrão do MOJ'));
  await chips[1].click(); await flush();
  const chipsEN=cover.all().filter(n=>n.tagName==='button' && n.className.startsWith('stmt-chip'));
  const edEN=EDS.find(e=>e.init==='# EN capa do contest');
  ck('aba EN: editor próprio com o texto do contest, estado "editado", e a capa em PDF enviada', !!edEN && chipsEN[1].className.includes('active')
     && cover.textContent.includes('texto editado neste contest') && cover.textContent.includes('PDF de capa enviado'));
  ck('trocar de aba esconde o editor do outro idioma (sem perder)', edPT.mount.style.display==='none' && !edEN.mount.style.display);
  const save=btn(cover,'Salvar')[0];
  const n0=POSTS.length; await save.click(); await flush();
  ck('Salvar sem mudança não manda nada', POSTS.length===n0 && P.textContent.includes('Nada mudou'));
  edPT.setValue('# PT capa editada'); edEN.setValue('# EN nova');
  await save.click(); await flush();
  const b=POSTS[POSTS.length-1];
  ck('Salvar manda só os idiomas alterados (PT e EN, não ES)', b.action==='config' && b.cover_pt==='# PT capa editada' && b.cover_en==='# EN nova' && !('cover_es' in b), JSON.stringify(b));
  // depois do save a tela recarrega (load) — o reset vale p/ a aba ativa, que volta a ser PT
  const cover2=P.all().filter(n=>n.className==='subcard' && n.textContent.includes('Capa do caderno')).pop();
  await btn(cover2,'voltar ao padrão')[0].click(); await flush();
  ck('"voltar ao padrão" manda o idioma da aba vazio', JSON.stringify(POSTS[POSTS.length-1])===JSON.stringify({action:'config', cover_pt:''}), JSON.stringify(POSTS[POSTS.length-1]));
  const info=P.all().filter(n=>n.className==='subcard' && n.textContent.includes('Texto do info sheet')).pop();
  ck('info sheet: mesmas abas e editor do MOJ', info.all().filter(n=>n.tagName==='button' && n.className.startsWith('stmt-chip')).length===3 && EDS.some(e=>e.init==='info pt' && e.cm==='markdown'));
  // exemplos em tabela: opt-in (padrão desmarcado); marcar grava samples_table:true na hora
  const cbs=P.all().filter(n=>n.tagName==='input' && n.attrs.type==='checkbox' && n.parentNode && n.parentNode.textContent.includes('exemplos do caderno em tabela'));
  ck('checkbox "exemplos do caderno em tabela" existe e nasce desmarcado', cbs.length===1 && !cbs[0].checked, String(cbs.length));
  cbs[0].checked=true; await cbs[0].fire('change'); await flush();
  ck('marcar manda {action:config, samples_table:true}', JSON.stringify(POSTS[POSTS.length-1])===JSON.stringify({action:'config', samples_table:true}), JSON.stringify(POSTS[POSTS.length-1]));
  DATA.config={samples_table:true}; const tabT=makeDocsTab('c'); await tabT.load(); await flush();
  const cbT=tabT.panel.all().filter(n=>n.tagName==='input' && n.attrs.type==='checkbox' && n.parentNode && n.parentNode.textContent.includes('exemplos do caderno em tabela'));
  ck('com samples_table no config, abre marcado', cbT.length===1 && cbT[0].checked);
  DATA.config={};
  LANG='en'; EDS.length=0; const tabEN=makeDocsTab('c'); await tabEN.load(); await flush();
  ck('em inglês', tabEN.panel.textContent.includes('Problem set cover') && tabEN.panel.textContent.includes('MOJ default text') && tabEN.panel.textContent.includes('Download the “✎ .odt”') && tabEN.panel.textContent.includes('problem set samples as a table'));
})().catch(e=>{ print('  FAIL: exceção '+e+'\n'+e.stack); fail++; }).finally(()=>{ print(''); print('RESULT: '+pass+' passed, '+fail+' failed'); if (fail) imports.system.exit(1); });
EOF
} > "$JS"
gjs "$JS"
