#!/bin/bash
# smoke-issues-panel.gjs.sh — a aba "🐞 Issues" do editor (web/problemas/issues.js) num DOM falso, com a
# API FALSA. Prende:
#   · sem id (problema não salvo): aviso e botão desabilitado;
#   · lista: abertas primeiro, fechadas escondidas atrás de um botão; onCount recebe as abertas;
#   · título/corpo HOSTIS saem como TEXTO (nada de html);
#   · abrir sem título não chama a API; com título manda {id, action:"open", title, body};
#   · recarregar a lista preserva o <details> aberto e o rascunho digitado na caixa;
#   · fechar manda {action:"close", n, body} com o texto da caixa;
#   · erro de rede no GET não apaga a lista.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
W="$ROOT/web"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "issues-panel: gjs ausente — pulando"; exit 0; }
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
{ cat <<'JS'
function FakeNode(tag){ this.tagName=String(tag).toUpperCase(); this.nodeType=1; this.children=[]; this.attrs={}; this._ev={}; this._cls=new Set(); this.style={}; this.value=''; this.disabled=false; this.open=false; this.onclick=null; }
FakeNode.prototype.append=function(){ for (const k of arguments) this.children.push(typeof k==='object'?k:{nodeType:3,text:String(k)}); };
FakeNode.prototype.setAttribute=function(k,v){ if(k==='class') this._cls=new Set(String(v).split(/\s+/).filter(Boolean)); if (k==='html') throw new Error('html proibido'); this.attrs[k]=v; };
FakeNode.prototype.addEventListener=function(t,f){ (this._ev[t]=this._ev[t]||[]).push(f); };
FakeNode.prototype.fire=async function(t){ for (const f of (this._ev[t]||[])) await f({}); };
FakeNode.prototype.click=async function(){ if (this.onclick) await this.onclick({}); await this.fire('click'); };
FakeNode.prototype.focus=function(){ this._focused=true; };
FakeNode.prototype._all=function(){ const o=[]; for (const c of this.children) if (c.nodeType===1){ o.push(c); o.push(...c._all()); } return o; };
Object.defineProperty(FakeNode.prototype,'className',{set(v){this.setAttribute('class',v)},get(){return [...this._cls].join(' ')}});
Object.defineProperty(FakeNode.prototype,'innerHTML',{set(v){ if (v) throw new Error('innerHTML com conteúdo'); this.children=[]; }, get(){ return ''; }});
Object.defineProperty(FakeNode.prototype,'textContent',{set(v){ this.children=[{nodeType:3,text:String(v)}]; }, get(){ return this.children.map(c=>c.nodeType===3?c.text:c.textContent).join(''); }});
globalThis.document={ createElement:(t)=>new FakeNode(t), createTextNode:(t)=>({nodeType:3,text:String(t)}) };
function T(pt,en){ return pt; }
JS
  strip "$W/shared/dom.js"; strip "$W/problemas/issues.js"
  cat <<'JS'
let PASS=0, FAIL=0; const ck=(n,c)=>{ if (c) PASS++; else { FAIL++; print('FALHOU: '+n); } };
let ID='', POSTS=[], GETS=0, GET_ERR=null, COUNT=null;
const now = Math.floor(Date.now()/1000);
let DATA = { id:'col#pa', open:1, issues:[
  { n:2, title:'<script>alert(1)</script>', body:'linha 1\n<b>linha 2</b>', state:'open', by:'bruno', at:now-600, updated_at:now-60,
    comments:[{by:'autor', at:now-60, body:'confirmo'}] },
  { n:1, title:'teste 7', body:'', state:'closed', by:'autor', at:now-9000, updated_at:now-3000, closed_by:'autor', closed_at:now-3000, comments:[] } ] };
const I = makeIssues({
  id: () => ID,
  apiGet: async (p) => { GETS++; if (GET_ERR) throw GET_ERR; return JSON.parse(JSON.stringify(DATA)); },
  apiPost: async (p, b) => { POSTS.push([p, b]); return { issue: { n: 3 } }; },
  onCount: (n) => { COUNT = n; },
});
const all = (n) => n._all();
const cards = () => all(I.panel).filter(n => n.tagName==='DETAILS' && n._cls.has('issue'));
const btn = (s) => all(I.panel).find(n => n.tagName==='BUTTON' && n.textContent.includes(s));
(async () => {
  await I.load();
  ck('sem id: aviso e botão "Abrir issue" desabilitado', I.panel.textContent.includes('Salve o problema') && btn('Abrir issue').disabled === true && GETS === 0);
  ID = 'col#pa'; await I.load();
  ck('com id: GET e botão liberado', GETS === 1 && btn('Abrir issue').disabled === false);
  ck('só a aberta aparece; onCount = 1', cards().length === 1 && COUNT === 1 && cards()[0].textContent.includes('#2'));
  ck('título e corpo hostis saem como TEXTO', cards()[0].textContent.includes('<script>alert(1)</script>') && cards()[0].textContent.includes('<b>linha 2</b>'));
  await btn('mostrar fechadas').click();
  ck('"mostrar fechadas (1)" mostra as duas', cards().length === 2);
  await btn('mostrar fechadas').click();
  // abrir: sem título não chama a API
  const [tIn] = all(I.panel).filter(n => n.tagName==='INPUT');
  const tArea = all(I.panel).find(n => n.tagName==='TEXTAREA' && n.attrs.placeholder && n.attrs.placeholder.startsWith('O que está errado'));
  tIn.value = '   '; await btn('Abrir issue').click();
  ck('abrir sem título: nenhuma chamada', POSTS.length === 0 && tIn._focused === true);
  tIn.value = 'TL apertado'; tArea.value = 'o py leva 0,9 s'; await btn('Abrir issue').click();
  ck('abrir: POST {id, action:open, title, body} e recarrega', POSTS.length === 1 && POSTS[0][0] === '/problems/issues'
     && JSON.stringify(POSTS[0][1]) === JSON.stringify({ id:'col#pa', action:'open', title:'TL apertado', body:'o py leva 0,9 s' }) && GETS === 2);
  ck('…e limpa o formulário', tIn.value === '' && tArea.value === '');
  // <details> aberto e rascunho sobrevivem ao recarregar
  let c = cards()[0]; c.open = true; await c.fire('toggle');
  let ta = all(c).find(n => n.tagName==='TEXTAREA'); ta.value = 'rascunho meu'; await ta.fire('input');
  await I.load();
  c = cards()[0]; ta = all(c).find(n => n.tagName==='TEXTAREA');
  ck('recarregar mantém o <details> aberto', c.open === true);
  ck('recarregar mantém o rascunho', ta.value === 'rascunho meu');
  // fechar com o texto da caixa
  await all(c).find(n => n.tagName==='BUTTON' && n.textContent.includes('Fechar')).click();
  ck('fechar: POST {action:close, n:2, body:<caixa>}', JSON.stringify(POSTS[1][1]) === JSON.stringify({ id:'col#pa', action:'close', n:2, body:'rascunho meu' }));
  // comentar vazio não chama a API
  c = cards()[0]; ta = all(c).find(n => n.tagName==='TEXTAREA'); ta.value = '  ';
  const nPosts = POSTS.length;
  await all(c).find(n => n.tagName==='BUTTON' && n.textContent.includes('Comentar')).click();
  ck('comentar vazio: nenhuma chamada', POSTS.length === nPosts);
  // erro de rede não apaga a lista
  GET_ERR = new Error('offline'); await I.load();
  ck('erro de rede: a lista fica e a mensagem aparece', cards().length === 1 && I.panel.textContent.includes('offline'));
  print(`RESULT: ${PASS} passed, ${FAIL} failed`);
})().catch(e => { print('ERRO: ' + e + '\n' + e.stack); print('RESULT: 0 passed, 1 failed'); });
JS
} > "$T/t.js"
out="$(gjs "$T/t.js" 2>&1)"; printf '%s\n' "$out"
grep -q 'RESULT: [0-9]* passed, 0 failed' <<<"$out"
