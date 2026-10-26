#!/bin/bash
# smoke-tl-sim.gjs.sh — a caixa "Simulação do tempo-limite" da aba Limites do editor (renderTlSim, 26/10/2026). O
# servidor calcula (lib/tl-sim.sh) e a tela só MOSTRA: as tabelas por configuração (MOJ: fator; Kattis: resolução), a
# linha atual, as soluções que sairiam erradas e as "não medidas", a sugestão de cada método e o botão "aplicar", que
# só PREENCHE os campos (fator/parâmetros do Kattis e o método) e avisa que salvar recalibra. Estados: calibrando,
# sem dados, servidor anterior (sem o campo: caixa vazia). Extrai as funções do editar.js e roda num DOM falso (gjs).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
WEB="$ROOT/web"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "tl-sim.gjs: gjs ausente — pulando"; exit 0; }
ex(){ awk -v a="$1" -v b="$2" 'index($0,a)==1{f=1} f&&index($0,b)==1&&!index($0,a){exit} f' "$WEB/problemas/editar.js"; }
{ cat <<'JS'
function FakeNode(tag){ this.tagName=String(tag).toUpperCase(); this.nodeType=1; this.children=[]; this.attrs={}; this._ev={}; this._cls=new Set(); this.hidden=false; this.style={}; this.dataset={}; this.value=''; }
FakeNode.prototype.append=function(){ for (const k of arguments) if (k!=null && k!=='') this.children.push(typeof k==='object'?k:{nodeType:3,text:String(k)}); };
FakeNode.prototype.setAttribute=function(k,v){ if(k==='class') this._cls=new Set(String(v).split(/\s+/).filter(Boolean)); this.attrs[k]=v; };
FakeNode.prototype.addEventListener=function(t,f){ (this._ev[t]=this._ev[t]||[]).push(f); };
FakeNode.prototype.dispatchEvent=function(e){ (this._ev[e.type]||[]).forEach(f=>f(e)); };
Object.defineProperty(FakeNode.prototype,'className',{set(v){this.setAttribute('class',v)},get(){return [...this._cls].join(' ')}});
Object.defineProperty(FakeNode.prototype,'innerHTML',{set(v){ this.children=[]; }, get(){ return ''; }});
Object.defineProperty(FakeNode.prototype,'textContent',{set(v){ this.children=[{nodeType:3,text:String(v)}]; }, get(){ return this.children.map(c=>c.nodeType===3?c.text:c.textContent).join(''); }});
globalThis.document={ createElement:(t)=>new FakeNode(t), createTextNode:(t)=>({nodeType:3,text:String(t)}) };
globalThis.Event=function(t){ this.type=t; };
function T(pt,en){ return pt; }
const all=(n,pred,out=[])=>{ if(n&&n.nodeType===1){ if(pred(n)) out.push(n); n.children.forEach(c=>all(c,pred,out)); } return out; };
const IDS = {}; const $ = (id) => IDS[id] || (IDS[id] = new FakeNode('div'));
let MSG = ''; const setMsg = (t) => { MSG = t; };
let METHOD_APPLIED = 0; const applyTlMethod = () => { METHOD_APPLIED++; };
let CHANGES = []; ['cf_calibrafactor','cf_tlmethod','cf_kattis_a','cf_kattis_b','cf_kattis_r'].forEach(id => $(id).addEventListener('change', () => CHANGES.push(id)));
let LASTCALIB = null;
JS
  sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$WEB/shared/dom.js"
  ex 'const TL_LANG_NAME = ' 'const tlSecs = '
  ex 'const tlSecs = ' 'const tlSecs = ' | head -1
  ex '// SIMULAÇÃO DO TEMPO-LIMITE (o servidor calcula' 'function valRenderSig() {'
  cat <<'JS'
let PASS=0, FAIL=0; const ck=(n,c)=>{ if (c) PASS++; else { FAIL++; print('FALHOU: '+n); } };
const box = $('cf_tlsim_box');
// servidor anterior à simulação: nada
LASTCALIB = { hosts: [] }; renderTlSim();
ck('servidor sem tl_sim_state: caixa vazia', box.children.length === 0);
LASTCALIB = { tl_sim_state: 'calibrating', tl_sim: null }; renderTlSim();
ck('calibrando: espera o fim', box.textContent.includes('Disponível quando a calibração terminar'));
LASTCALIB = { tl_sim_state: 'no_data', tl_sim: null }; renderTlSim();
ck('sem dados: pede calibrar', box.textContent.includes('Calibre o problema'));
LASTCALIB = { tl_sim_state: 'error', tl_sim: null }; renderTlSim();
ck('erro na simulação: diz que não deu, sem pedir calibrar', box.textContent.includes('não pôde ser calculada') && !box.textContent.includes('Calibre'));
const sim = { hosts: ['j1','j2'], w: {c: 0.45, default: 0.45}, overrides: [],
  moj: { cf: 1.35, off: 0, interval: {min: 1.177778, min_by: 'pass/p.c', max: 4.4, max_by: 'slow/s.c'},
         rows: [ {cf: 1, current: false, tl: {c: 0.47, default: 0.47}, ok: false, fail: ['pass/p.c'], unmeasured: []},
                 {cf: 1.35, current: true, tl: {c: 0.6275, default: 0.6275}, ok: true, fail: [], unmeasured: []} ] },
  kattis: { a: 2, b: 1.5, r: 1,
            rows: [ {r: 0.2, current: false, tl: {c: 1, default: 1}, ok: true, fail: [], unmeasured: ['slow/k.c']},
                    {r: 1, current: true, tl: {c: 1, default: 1}, ok: false, fail: ['slow/s.c'], unmeasured: []} ] } };
LASTCALIB = { tl_sim_state: 'ok', tl_sim: sim,
  tl_suggest: { moj: {state: 'change', cf: 1.5, why: 'interval'}, kattis: {state: 'change', a: 2, b: 1.5, r: 0.2, why: 'largest_r'} } };
renderTlSim();
const txt = box.textContent, tables = all(box, n => n._cls.has('tlsummary'));
ck('as duas tabelas (MOJ e Kattis)', tables.length === 2);
ck('os juízes da medição', txt.includes('juízes j1, j2'));
ck('a linha atual marcada', all(box, n => n._cls.has('pill') && n.textContent === 'atual').length === 2);
ck('o TL por linguagem na linha', txt.includes('C 0.47s') && txt.includes('C 0.6275s'));
ck('as soluções que sairiam erradas', txt.includes('✗ pass/p.c') && txt.includes('✗ slow/s.c'));
ck('a não medida', txt.includes('não medido: slow/k.c'));
ck('o intervalo do fator, com piso e teto', txt.includes('de 1.177778 até abaixo de 4.4') && txt.includes('piso: pass/p.c') && txt.includes('teto: slow/s.c'));
ck('as sugestões', txt.includes('Sugestão: fator 1.5') && txt.includes('Sugestão: resolução 0.2 s, a maior'));
const btns = all(box, n => n.tagName === 'BUTTON');
ck('um botão aplicar por sugestão', btns.length === 2);
btns[0]._ev.click[0]();
ck('aplicar MOJ: preenche o fator e o método', $('cf_calibrafactor').value === '1.5' && $('cf_tlmethod').value === 'moj' && CHANGES.includes('cf_calibrafactor') && METHOD_APPLIED === 1);
ck('…e avisa que salvar recalibra (e só o método não)', MSG.includes('Salve para gravar o conf') && MSG.includes('recalibra'));
CHANGES = []; btns[1]._ev.click[0]();
ck('aplicar Kattis: os três parâmetros e o método', $('cf_kattis_r').value === '0.2' && $('cf_kattis_a').value === '2' && $('cf_kattis_b').value === '1.5' && $('cf_tlmethod').value === 'kattis' && CHANGES.length === 4);
LASTCALIB.tl_suggest = { moj: {state: 'conflict', cf: 1.35, why: 'conflict', pass: 'pass/p.c', slow: 'slow/s.c'},
                         kattis: {state: 'keep', a: 2, b: 1.5, r: 1, why: 'current_valid'} };
renderTlSim();
ck('conflito: nomeia a pass e a lenta, sem botão', box.textContent.includes('a pass/p.c precisa de mais tempo do que a slow/s.c') && all(box, n => n.tagName === 'BUTTON').length === 0);
ck('manter: sem botão', box.textContent.includes('manter a resolução atual (1 s)'));
LASTCALIB.tl_sim.overrides = ['default']; renderTlSim();
ck('TLOVERRIDE[default]: avisa que nada muda', box.textContent.includes('TLOVERRIDE[default] do conf decide'));
print('RESULT: ' + PASS + ' passed, ' + FAIL + ' failed');
if (FAIL) imports.system.exit(1);
JS
} > "$W/t.js"
gjs "$W/t.js"
