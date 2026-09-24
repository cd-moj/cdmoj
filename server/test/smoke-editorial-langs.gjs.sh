#!/bin/bash
# smoke-editorial-langs.gjs.sh — a barra de idiomas do EDITORIAL (aba Resolução do editor de problema)
# tem os chips "+ EN / + ES" como a do enunciado (pedido do Ribas, 24/09/2026): adicionar o editorial num
# idioma NÃO exige o enunciado traduzido. Antes a barra só listava idiomas que o enunciado já tinha, e
# sem nenhum ela chamava switchEdLang, que chamava renderEdLangBar de novo (laço mudo).
# Extrai renderEdLangBar/removeEdLang/stmtChip do editar.js e roda num DOM falso com o gjs.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
WEB="$ROOT/web"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "editorial-langs: gjs ausente — pulando"; exit 0; }
ex(){ awk -v a="$1" -v b="$2" 'index($0,a)==1{f=1} f&&index($0,b)==1&&!index($0,a){exit} f' "$WEB/problemas/editar.js"; }
{ cat <<'JS'
function FakeNode(tag){ this.tagName=String(tag).toUpperCase(); this.nodeType=1; this.children=[]; this.attrs={}; this._ev={}; this._cls=new Set(); this.hidden=false; this.style={}; }
FakeNode.prototype.append=function(){ for (const k of arguments) this.children.push(typeof k==='object'?k:{nodeType:3,text:String(k)}); };
FakeNode.prototype.setAttribute=function(k,v){ if(k==='class') this._cls=new Set(String(v).split(/\s+/).filter(Boolean)); this.attrs[k]=v; };
FakeNode.prototype.addEventListener=function(t,f){ (this._ev[t]=this._ev[t]||[]).push(f); };
FakeNode.prototype.click=function(){ for (const f of (this._ev.click||[])) f({}); };
Object.defineProperty(FakeNode.prototype,'className',{set(v){this.setAttribute('class',v)},get(){return [...this._cls].join(' ')}});
Object.defineProperty(FakeNode.prototype,'innerHTML',{set(v){ this.children=[]; }, get(){ return ''; }});
Object.defineProperty(FakeNode.prototype,'textContent',{set(v){ this.children=[{nodeType:3,text:String(v)}]; }, get(){ return this.children.map(c=>c.nodeType===3?c.text:c.textContent).join(''); }});
globalThis.document={ createElement:(t)=>new FakeNode(t), createTextNode:(t)=>({nodeType:3,text:String(t)}) };
function T(pt,en){ return pt; }
JS
  sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$WEB/shared/dom.js"
  cat <<'JS'
const NODES = { edLangBar: new FakeNode('div'), edRemove: new FakeNode('button') };
const $ = (id) => NODES[id];
const STMT_LANGS = ['pt', 'en', 'es'], STMT_SHORT = { pt: 'PT', en: 'EN', es: 'ES' }, stmtName = (l) => l;
let TRANS = {}, curEdLang = 'pt', transEdEd = {}, CONFIRM = true, PKG = 0;
globalThis.confirm = () => CONFIRM;
const updatePkgInfo = () => { PKG++; };
function addTransLang(l) { if (TRANS[l]) return; TRANS[l] = { title: '', enunciado_md: '', editorial_md: '', notes: {} }; renderEdLangBar(); }
function switchEdLang(l) { if (l !== 'pt' && !TRANS[l]) l = 'pt'; curEdLang = l; renderEdLangBar(); }
JS
  ex 'function stmtChip(' 'function renderStmtLangBar('
  ex 'function renderEdLangBar(' 'async function switchEdLang('
  cat <<'JS'
let PASS=0, FAIL=0; const ck=(n,c)=>{ if (c) PASS++; else { FAIL++; print('FALHOU: '+n); } };
const chips = () => NODES.edLangBar.children.filter(n => n.nodeType===1).map(n => n.textContent + (n._cls.has('active') ? '*' : ''));
renderEdLangBar();
ck('sem tradução: PT ativo + "+ EN" + "+ ES" (antes a barra sumia)', JSON.stringify(chips()) === JSON.stringify(['PT*', '+ EN', '+ ES']));
ck('em PT o "remover" fica escondido', NODES.edRemove.hidden === true);
NODES.edLangBar.children[1].click();
ck('clicar "+ EN": cria a tradução e ativa EN', !!TRANS.en && curEdLang === 'en' && JSON.stringify(chips()) === JSON.stringify(['PT', 'EN*', '+ ES']));
ck('"remover o editorial em EN" aparece', NODES.edRemove.hidden === false && NODES.edRemove.textContent.includes('EN'));
let setv = null; transEdEd.en = { setValue: (v) => { setv = v; } }; TRANS.en.editorial_md = 'x'; TRANS.en.enunciado_md = 'enunciado EN';
removeEdLang();
ck('remover: zera SÓ o editorial (a tradução e o enunciado ficam)', setv === '' && TRANS.en.editorial_md === '' && TRANS.en.enunciado_md === 'enunciado EN' && PKG === 1);
CONFIRM = false; TRANS.en.editorial_md = 'y'; removeEdLang();
ck('cancelar a confirmação não mexe', TRANS.en.editorial_md === 'y');
delete TRANS.en; renderEdLangBar();
ck('idioma ativo que sumiu cai no PT', curEdLang === 'pt' && JSON.stringify(chips()) === JSON.stringify(['PT*', '+ EN', '+ ES']));
print(`RESULT: ${PASS} passed, ${FAIL} failed`);
JS
} > "$W/t.js"
out="$(gjs "$W/t.js" 2>&1)"; printf '%s\n' "$out"
grep -q 'RESULT: [0-9]* passed, 0 failed' <<<"$out"
