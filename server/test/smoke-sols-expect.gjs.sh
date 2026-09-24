#!/bin/bash
# smoke-sols-expect.gjs.sh — a tela da calibração MOSTRA o juízo do servidor (lib/calib-expect.sh) e não
# refaz a regra. Antes, o `solOk` do editor lia a string do veredicto: TLE+WA virava "ok", slow pontuado
# (`Wrong,Np`) virava "revisar" e wrong que nem compilou era "ok" (relato do Arthur Botelho, 22/09/2026).
# Extrai solsBlock/validatorBlock do editar.js + o web/problemas/readiness.js e roda num DOM falso (gjs).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
WEB="$ROOT/web"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "sols-expect: gjs ausente — pulando"; exit 0; }
ex(){ awk -v a="$1" -v b="$2" 'index($0,a)==1{f=1} f&&index($0,b)==1&&!index($0,a){exit} f' "$WEB/problemas/editar.js"; }
{ cat <<'JS'
function FakeNode(tag){ this.tagName=String(tag).toUpperCase(); this.nodeType=1; this.children=[]; this.attrs={}; this._ev={}; this._cls=new Set(); this.hidden=false; this.style={}; this.dataset={}; }
FakeNode.prototype.append=function(){ for (const k of arguments) if (k!=null && k!=='') this.children.push(typeof k==='object'?k:{nodeType:3,text:String(k)}); };
FakeNode.prototype.setAttribute=function(k,v){ if(k==='class') this._cls=new Set(String(v).split(/\s+/).filter(Boolean)); this.attrs[k]=v; };
FakeNode.prototype.addEventListener=function(t,f){ (this._ev[t]=this._ev[t]||[]).push(f); };
Object.defineProperty(FakeNode.prototype,'className',{set(v){this.setAttribute('class',v)},get(){return [...this._cls].join(' ')}});
Object.defineProperty(FakeNode.prototype,'innerHTML',{set(v){ this.children=[]; }, get(){ return ''; }});
Object.defineProperty(FakeNode.prototype,'textContent',{set(v){ this.children=[{nodeType:3,text:String(v)}]; }, get(){ return this.children.map(c=>c.nodeType===3?c.text:c.textContent).join(''); }});
globalThis.document={ createElement:(t)=>new FakeNode(t), createTextNode:(t)=>({nodeType:3,text:String(t)}) };
function T(pt,en){ return pt; }
const all=(n,pred,out=[])=>{ if(n&&n.nodeType===1){ if(pred(n)) out.push(n); n.children.forEach(c=>all(c,pred,out)); } return out; };
const byCls=(n,c)=>all(n,x=>x._cls.has(c));
JS
  sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$WEB/shared/dom.js"
  sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$WEB/problemas/readiness.js"
  cat <<'JS'
const OPEN_SOLS = new Set();
const testsTable = (t) => el('table', { class: 'soltests' });
const openCalibReport = () => {};
JS
  ex 'function validatorBlock(' '// quadro-resumo: tempo-limite'
  ex 'function solsBlock(' 'function validatorBlock('
  cat <<'JS'
let PASS=0, FAIL=0; const ck=(n,c)=>{ if (c) PASS++; else { FAIL++; print('FALHOU: '+n); } };
// ---- readiness.js
ck('ok = ✓ conforme (pill ok)', expectPill({state:'ok'}).cls==='ok' && expectPill({state:'ok'}).label.includes('conforme'));
ck('note = ≈ (pill warn) com explicação', expectPill({state:'note'}).cls==='warn' && !!expectPill({state:'note'}).title);
ck('bad = ✗ divergente', expectPill({state:'bad'}).cls==='no' && expectPill({state:'bad'}).label.includes('divergente'));
ck('norun = ✗ não rodou', expectPill({state:'norun'}).label.includes('não rodou'));
ck('sem expect = sem pílula', expectPill(undefined)===null && expectPill({state:'skip'})===null);
ck('wrong com TLE: diz o motivo e não lista o AC', (()=>{ const g=expectGot({state:'note',why:'failed_other',counts:{AC:2,TLE:1}}); return g.includes('TLE 1') && !g.includes('AC'); })());
ck('slow com WA: conta os testes errados', expectGot({state:'note',why:'tle_and_wrong',counts:{TLE:1,WA:2}}).includes('2 testes'));
ck('good acima do override: mostra tempo e TL', (()=>{ const g=expectGot({why:'over_tl',tmax:0.9,tl:0.5}); return g.includes('0.9s') && g.includes('0.5s'); })());
ck('o que cada categoria pede', ['good','pass','slow','wrong'].every(c=>expectWant(c).startsWith('esperado')) && expectWant('upcoming')==='');
ck('pendências com número', pendingLabel('sols_divergent:2')==='2 soluções divergentes' && pendingLabel('issues_open:1')==='1 issue aberta');
ck('pendência com lista de linguagens', pendingLabel('good_no_tl:c,py').endsWith('c,py'));
ck('pendência desconhecida = o próprio código', pendingLabel('xyz')==='xyz');
ck('resumo: conforme + outro motivo + sem resultado', (()=>{ const t=summaryText({total:4,bad:1,note:1,missing:['slow/a.c']}); return t.startsWith('3 de 4') && t.includes('1 divergente') && t.includes('1 sem resultado'); })());
ck('validador: inválidas', validatorText({state:'invalid',invalid:2,total:9})==='2 de 9 entradas INVÁLIDAS');
// ---- solsBlock: pílula e "esperado/obtido" vêm do expect do servidor
const h = { host:'j1', reports:[], sols:[
  {category:'slow', file:'lento.c', verdict:'Time Limit Exceeded,0p', tests:[{code:'TLE'},{code:'WA'}], expect:{state:'note',why:'tle_and_wrong',counts:{TLE:1,WA:1}}},
  {category:'wrong', file:'w.c', verdict:'Compilation Error', tests:[], expect:{state:'norun',why:'ce',counts:{}}},
  {category:'good', file:'g.c', verdict:'Accepted,100p', tests:[{code:'AC'}], expect:{state:'ok',why:'all_ac',counts:{AC:1}}},
  {category:'good', file:'velho.c', verdict:'Accepted,100p', tests:[]} ] };
const b = solsBlock(h);
const rows = byCls(b,'solrow');
const pillTxt = (r) => { const p=r.children[0]; return p.textContent; };
ck('4 linhas', rows.length===4);
ck('slow TLE+WA = ≈ (antes: ok escondendo o WA)', pillTxt(rows[0]).startsWith('≈'));
ck('wrong que não compilou = ✗ não rodou (antes: ok)', pillTxt(rows[1]).includes('não rodou'));
ck('good aceita = ✓', pillTxt(rows[2]).startsWith('✓'));
ck('sem expect = • neutro', pillTxt(rows[3])==='•');
const exps = byCls(b,'solexp');
ck('linha "esperado/obtido" nas que têm categoria', exps.length===4);
ck('"obtido" destacado quando não é ok', byCls(exps[0],'got').length===1 && byCls(exps[2],'got').length===0);
ck('texto do esperado da slow', exps[0].textContent.includes('estourar o tempo'));
// ---- validatorBlock
ck('juiz sem validador rodado = nada', validatorBlock({})===null);
const vn = validatorBlock({validator:{state:'none',total:0,invalid:0,tests:[]}});
ck('pacote sem validador = linha neutra', !!vn && vn.textContent.includes('sem validador'));
const vi = validatorBlock({validator:{state:'invalid',total:3,invalid:1,tests:[{name:'t1',code:'INVALID',msg:'FAIL n=1296 fora de [1,1000]'},{name:'t2',code:'OK'},{name:'t3',code:'OK'}]}});
ck('inválida: linha ✗ + detalhes com a mensagem da testlib', vi.textContent.includes('1 de 3') && all(vi,x=>x.tagName==='DETAILS').length===1 && vi.textContent.includes('1296'));
ck('só as reprovadas vão na tabela', byCls(vi,'vmsg').length===1);
print(`RESULT: ${PASS} passed, ${FAIL} failed`);
JS
} > "$W/t.js"
out="$(gjs "$W/t.js" 2>&1)"; printf '%s\n' "$out"
grep -q 'RESULT: [0-9]* passed, 0 failed' <<<"$out"
