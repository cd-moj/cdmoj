#!/bin/bash
# smoke-contest-submit.gjs.sh — o ENVIO na página do contest (01/10/2026), rodando o renderSubmitInline REAL
# (fatiado de web/contest/contest.js) e a tabela de envios (web/contest/submissions-table.js) num DOM falso:
#   • o botão da linha trava NO CLIQUE, antes de ler o arquivo (fileToBase64) — clique duplo = um POST só;
#   • depois do envio o arquivo é LIMPO e a página recebe id/epoch/lang p/ a linha pendente aparecer na hora;
#   • o botão do EDITOR envia só o editor: arquivo esquecido na linha não vence mais o texto (editor vazio +
#     arquivo escolhido = aviso apontando o botão da linha); o mesmo código pede o 2º clique;
#   • a linha e o editor do MESMO problema compartilham o estado;
#   • tabela: a linha OTIMISTA aparece na hora (destacada), o servidor manda quando a traz, a recarga pós-envio
#     pula o microcache (parâmetro a mais) e o poll NÃO morre quando um GET falha com pendente na tela.
# Sem gjs: pula.
set -u
command -v gjs >/dev/null 2>&1 || { echo "contest-submit.gjs: gjs ausente — pulando"; exit 0; }
W="$(cd "$(dirname "$(readlink -f "$0")")/../../web" && pwd)"
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
slice(){ awk -v h="$1" 'index($0, h) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }
JS="$(mktemp --suffix=.js)"; trap 'rm -f "$JS"' EXIT
F="$W/contest/contest.js"
[[ -n "$(slice 'function renderSubmitInline(p) {' "$F")" ]] || { echo "FAIL: renderSubmitInline não encontrado em contest.js"; exit 1; }
{ cat <<'EOF'
function FakeNode(tag){ this.tagName=tag; this.nodeType=1; this.children=[]; this.attrs={}; this.style={}; this._text=''; this.dataset={}; this.ev={}; this.files=null; }
FakeNode.prototype.append=function(){ for (const k of arguments) this.children.push(k!==null&&typeof k==='object'?k:{nodeType:3,text:String(k)}); };
FakeNode.prototype.insertBefore=function(n){ this.children.push(n); };
FakeNode.prototype.setAttribute=function(k,v){ this.attrs[k]=String(v); };
FakeNode.prototype.getAttribute=function(k){ return k in this.attrs ? this.attrs[k] : null; };
FakeNode.prototype.addEventListener=function(k,f){ (this.ev[k] = this.ev[k] || []).push(f); };
FakeNode.prototype.fire=async function(k){ for (const f of (this.ev[k] || [])) await f({ preventDefault(){} }); };
FakeNode.prototype._all=function(){ const out=[]; for (const c of this.children) { if (c.nodeType===1) { out.push(c); out.push(...c._all()); } } return out; };
FakeNode.prototype.find=function(pred){ return this._all().filter(pred); };
Object.defineProperty(FakeNode.prototype,'className',{set(v){this.attrs['class']=v},get(){return this.attrs['class']||''}});
Object.defineProperty(FakeNode.prototype,'innerHTML',{set(v){this.children=[];this._html=v},get(){return this._html||''}});
Object.defineProperty(FakeNode.prototype,'textContent',{ set(v){this._text=String(v); this.children=[];},
  get(){ let t=this._text; for(const c of this.children) t+= c.nodeType===3?c.text:(c.textContent||''); return t; }});
// <select>.value = a 1ª opção enquanto ninguém escolheu (como o navegador); <input type=file>.value = '' limpa .files
Object.defineProperty(FakeNode.prototype,'value',{
  get(){ if (this._v != null) return this._v; if (this.tagName === 'select') { const o = this.children.find((c) => c.tagName === 'option'); return o ? o.attrs.value : ''; } return ''; },
  set(v){ this._v = String(v); if (this.tagName === 'input' && v === '') this.files = null; }});
globalThis.document={ createElement:(t)=>new FakeNode(t), createTextNode:(t)=>({nodeType:3,text:String(t),textContent:String(t)}),
  body: new FakeNode('body'), getElementById: () => null };
function T(pt){ return pt; } function uiLocale(){ return 'pt-BR'; }
// timers FALSOS (o "✓ Enviado" de 1,5 s e o poll da tabela)
let NOW = 1790000000000; const TIMERS = [];
globalThis.setTimeout = (f, ms) => { const t = { f, at: NOW + (ms || 0), ms, done: false }; TIMERS.push(t); return t; };
globalThis.clearTimeout = (t) => { if (t) t.done = true; };
const advance = (ms) => { NOW += ms; for (const t of TIMERS.slice()) if (!t.done && t.at <= NOW) { t.done = true; t.f(); } };
const pending = () => TIMERS.filter((t) => !t.done);
const M = new Map(); globalThis.localStorage = { getItem: (k) => (M.has(k) ? M.get(k) : null), setItem: (k, v) => M.set(k, String(v)) };
const deferred = () => { let res, rej; const p = new Promise((a, b) => { res = a; rej = b; }); return { p, res, rej }; };
EOF
  strip "$W/shared/dom.js"; strip "$W/shared/languages.js"; strip "$W/shared/editor-skeleton.js"; strip "$W/shared/submit-ux.js"
  cat <<'EOF'
// o mundo do contest.js que o renderSubmitInline usa
const CONTEST = 'c1', EDITOR_ONLY = false; let userinfo = { login: 'time01' }; let LANGS = LANGUAGES;
const POSTS = []; let postD = null;
async function apiPost(path, body) { POSTS.push({ path, body }); postD = deferred(); return postD.p; }
let b64D = null, B64N = 0; const fileToBase64 = (f) => { B64N++; b64D = deferred(); return b64D.p; };
const textToBase64 = (t) => 'T64:' + t;
function injectEditorCss() {}
async function loadSkeletons() { return null; }
let EDVAL = '';
async function createEditor(mount, opts) { return { getValue: () => EDVAL, refresh() {}, focus() {} }; }
const NOTED = []; function noteSubmitted(rec) { NOTED.push(rec); }
const BUS = []; function submitBus() { return { post: (m) => BUS.push(m) }; }
EOF
  slice 'function renderSubmitInline(p) {' "$F"
  # a tabela de envios (módulo próprio): stubs do ui.js/admin-ui.js
  cat <<'EOF'
let HIST = ''; let HIST_FAIL = false; const GETS = [];
async function apiGetText(path) { GETS.push(path); if (HIST_FAIL) throw new Error('HTTP 502'); return HIST; }
async function apiGet() { return {}; }
function getToken() { return 'tok'; }
function verdictClass(v) { return /Accepted/.test(v) ? 'v-ok' : 'v-pending'; }
function isPending(v) { return /Not Answered Yet|On queue|Running/i.test(v || ''); }
function fmtDate(e) { return String(e); }
function resumoText() { return ''; }
function openHtmlReport() {}
const sigOf = (...a) => JSON.stringify(a);
function swapIf(box, sig, build) { if (box.dataset.sig === sig) return; box.dataset.sig = sig; box.textContent = ''; box.append(build()); }
EOF
  strip "$W/contest/submissions-table.js"
  cat <<'EOF'
let pass=0, fail=0; const ck=(m,ok,d)=>{ if (ok) { print('  ok: '+m); pass++; } else { print('  FAIL: '+m+' :: '+(d||'')); fail++; } };
const flush = async () => { for (let i = 0; i < 12; i++) await null; };
const txt = (n) => n.textContent;
(async () => {
  const P = { problem_id: 'col#pa', short_name: 'A', full_name: 'Alfa', languages: ['c', 'cpp'] };
  const sw = renderSubmitInline(P);
  const row = sw.row;
  const [fileInput] = row.find((n) => n.tagName === 'input');
  const btn = row.find((n) => n.tagName === 'button' && txt(n) === 'Enviar')[0];
  const fileName = row.find((n) => n.tagName === 'span' && (n.attrs.style || '').includes('ellipsis'))[0];
  const steps = row.find((n) => (n.className || '').includes('submit-steps'))[0];

  print('== linha (arquivo) ==');
  btn.fire('click'); await flush();
  ck('sem arquivo: aviso, nenhum POST', POSTS.length === 0 && steps.find((n) => n.className === 'error-box').length === 1 && txt(steps).includes('Escolha um arquivo'));
  fileInput.files = [{ name: 'sol.py' }]; btn.fire('click'); await flush();
  ck('extensão fora da lista do problema: aviso, nenhum POST', POSTS.length === 0 && txt(steps).includes('só aceita: c, cpp'));
  fileInput.files = [{ name: 'sol.cpp' }]; fileName.textContent = 'sol.cpp'; B64N = 0;
  const c1 = btn.fire('click'); await flush();
  ck('trava NO CLIQUE, antes de ler o arquivo', btn.className.includes('is-sending') && btn.getAttribute('aria-disabled') === 'true' && b64D && POSTS.length === 0);
  btn.fire('click'); await flush();
  ck('clique duplo durante a leitura: ignorado (o arquivo é lido UMA vez)', POSTS.length === 0 && B64N === 1, B64N);
  b64D.res('Q1BQ'); await flush();
  ck('um POST, com o arquivo', POSTS.length === 1 && POSTS[0].body.filename === 'sol.cpp' && POSTS[0].body.code_b64 === 'Q1BQ' && POSTS[0].body.source === 'file'
     && POSTS[0].body.problem_id === 'col#pa', JSON.stringify(POSTS[0] && POSTS[0].body));
  postD.res({ submission_id: 'id1', status: 'queued', epoch: 1790000100, problem_id: 'col#pa', lang: 'CPP' }); await flush();
  ck('verde "✓ Enviado"', btn.className.includes('is-sent'));
  ck('arquivo LIMPO depois do envio', fileInput.value === '' && !fileInput.files && fileName.textContent === '');
  ck('a página recebe id/epoch/lang p/ a linha pendente', NOTED.length === 1 && NOTED[0].subid === 'id1' && NOTED[0].epoch === 1790000100 && NOTED[0].lang === 'CPP' && NOTED[0].problem === 'col#pa', JSON.stringify(NOTED));
  ck('status: hora + "A · C++" + onde acompanhar', txt(steps).includes('Enviado às') && txt(steps).includes('A · C++') && txt(steps).includes('Minhas submissões'), txt(steps));
  advance(1500);

  print('== editor: envia SÓ o editor ==');
  await sw.mountEditor(); await flush();
  const ed = sw.editorBlock;
  const edBtn = ed.find((n) => n.tagName === 'button' && txt(n) === 'Enviar solução')[0];
  const edSteps = ed.find((n) => (n.className || '').includes('submit-steps'))[0];
  fileInput.files = [{ name: 'velho.cpp' }]; EDVAL = '   ';
  edBtn.fire('click'); await flush();
  ck('editor vazio + arquivo na linha: aviso aponta o botão da linha, nenhum POST', POSTS.length === 1 && txt(edSteps).includes('velho.cpp') && txt(edSteps).includes('botão Enviar ao lado'), txt(edSteps));
  EDVAL = 'int main(){return 0;}';
  const c2 = edBtn.fire('click'); await flush();
  ck('com texto: manda o EDITOR (não o arquivo da linha)', POSTS.length === 2 && POSTS[1].body.filename === 'solution.c' && POSTS[1].body.code_b64 === 'T64:int main(){return 0;}' && POSTS[1].body.source === 'web', JSON.stringify(POSTS[1] && POSTS[1].body));
  ck('linha e editor compartilham o estado: o botão da linha fica inerte', btn.getAttribute('aria-disabled') === 'true' && !btn.className.includes('is-sending'));
  btn.fire('click'); await flush();
  ck('clique na linha durante o envio do editor: ignorado', POSTS.length === 2);
  postD.res({ submission_id: 'id2', epoch: 1790000200, lang: 'C' }); await flush();
  ck('o arquivo da linha continua escolhido (o editor não mexe nele)', fileInput.files && fileInput.files[0].name === 'velho.cpp');
  advance(1500);
  edBtn.fire('click'); await flush();
  ck('mesmo código ⇒ âmbar, sem POST', POSTS.length === 2 && edBtn.className.includes('is-confirm') && txt(edBtn).startsWith('Mesmo código do envio das'), txt(edBtn));
  const c3 = edBtn.fire('click'); await flush(); postD.res({ submission_id: 'id3' }); await flush();
  ck('2º clique envia', POSTS.length === 3);
  advance(1500);
  const e429 = Object.assign(new Error('Você já tem 3 envio(s)…'), { status: 429, code: 'submit_busy', data: { inflight: 3, max: 3 } });
  EDVAL = 'int main(){return 1;}';
  const c4 = edBtn.fire('click'); await flush(); postD.rej(e429); await flush();
  ck('429 do teto: mensagem legível na linha do editor', txt(edSteps).includes('3 envios esperando o veredicto') && !edBtn.className.includes('is-sent'), txt(edSteps));

  print('== tabela: linha otimista, recarga sem cache, poll que não morre ==');
  const tableEl = new FakeNode('div'), filterEl = new FakeNode('div');
  HIST = '1790000000:time01:col#pa:C:Accepted:1790000000:old1\n';
  const st = makeSubmissionsTable({ contest: 'c1', basic: { start_time: 1789990000 }, problems: [P], userinfo: {}, filterEl, tableEl });
  await st.load();
  const rows = () => tableEl.find((n) => n.tagName === 'tr').length - 1;
  ck('carrega 1 linha', rows() === 1);
  ck('sem pendente: sem poll', pending().filter((t) => t.ms >= 5000).length === 0);
  st.addPending({ subid: 'n1', problem: 'col#pa', lang: 'CPP', epoch: 1790000300 });
  ck('linha OTIMISTA aparece na hora, destacada e pendente', rows() === 2 && tableEl.find((n) => n.tagName === 'tr' && n.className === 'sub-new').length === 1
     && txt(tableEl).includes('Not Answered Yet'));
  st.addPending({ subid: 'n1', problem: 'col#pa', lang: 'CPP', epoch: 1790000300 });
  ck('addPending idempotente', rows() === 2);
  await st.load({ fresh: true });
  ck('recarga pós-envio pula o microcache (parâmetro a mais)', /&_=\d+$/.test(GETS[GETS.length - 1]), GETS[GETS.length - 1]);
  ck('servidor ainda sem a linha (cache velho): a otimista fica', st.submissions.some((s) => s.subid === 'n1' && s.optimistic));
  HIST += '1790000300:time01:col#pa:CPP:Not Answered Yet:1790000300:n1\n';
  await st.load();
  ck('servidor trouxe: vale a do servidor, sem duplicata', st.submissions.filter((s) => s.subid === 'n1').length === 1 && !st.submissions.find((s) => s.subid === 'n1').optimistic);
  ck('com pendente: poll agendado (5–10 s)', pending().some((t) => t.ms >= 5000 && t.ms <= 10000));
  for (const t of pending()) t.done = true;
  HIST_FAIL = true; await st.load();
  ck('GET falhou com pendente na tela: o poll RE-ARMA', pending().some((t) => t.ms >= 8000 && t.ms <= 12000), JSON.stringify(pending().map((t) => t.ms)));
  ck('e a tabela velha fica', rows() === 2);
  for (const t of pending()) t.done = true;
  HIST_FAIL = false; HIST = '1790000000:time01:col#pa:C:Accepted:1790000000:old1\n'; await st.load();
  HIST_FAIL = true; await st.load();
  ck('GET falhou SEM pendente: nada a vigiar, sem poll', pending().length === 0, JSON.stringify(pending().map((t) => t.ms)));

  print(''); print('RESULT: ' + pass + ' passed, ' + fail + ' failed');
  imports.system.exit(fail > 0 ? 1 : 0);
})().catch((e) => { print('EXC ' + e + '\n' + e.stack); imports.system.exit(2); });
EOF
} > "$JS"
gjs "$JS"
