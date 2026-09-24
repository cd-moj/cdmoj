#!/bin/bash
# smoke-testrun-panel.gjs.sh — a sub-aba "🧪 testar no juiz" do editor (web/problemas/testrun.js) num
# DOM falso, com a API FALSA (o POST/GET de /problems/test-run respondem o que o teste mandar). Prende:
#   · sem id (problema não salvo): botão desabilitado + aviso;
#   · colar código: POST {id, filename, code_b64} com o texto; arquivo escolhido e NÃO editado: os BYTES
#     dele (fileToBase64), editado: o texto;
#   · cartão queued -> done atualiza EM LUGAR (mesmo nó; <details> aberto não é refeito se nada mudou);
#     poll para quando tudo termina; 404 vira "expirou"; erro de rede não apaga o cartão;
#   · 429 mostra a mensagem do servidor e não cria run;
#   · a lista é lembrada no localStorage por problema, e localStorage quebrado não derruba nada;
#   · 📄 report chama openHtmlReport com o html do servidor.
# Sem gjs: pula (rc 0).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
W="$ROOT/web"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "testrun-panel: gjs ausente — pulando"; exit 0; }
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
{ cat <<'JS'
function FakeNode(tag){ this.tagName=String(tag).toUpperCase(); this.nodeType=1; this.children=[]; this.attrs={}; this.dataset={}; this._ev={}; this._cls=new Set(); this.style={}; this.parent=null; this.value=''; this.disabled=false; this.open=false; }
FakeNode.prototype.append=function(){ for (const k of arguments){ const n = typeof k==='object'?k:{nodeType:3,text:String(k)}; if (n.parent) n.parent._drop(n); n.parent=this; this.children.push(n);} };
FakeNode.prototype._drop=function(n){ const i=this.children.indexOf(n); if(i>=0) this.children.splice(i,1); n.parent=null; };
FakeNode.prototype.insertBefore=function(n, ref){ if (n.parent) n.parent._drop(n); const i = ref ? this.children.indexOf(ref) : -1; n.parent=this; if (i<0) this.children.push(n); else this.children.splice(i,0,n); return n; };
FakeNode.prototype.remove=function(){ if (this.parent) this.parent._drop(this); };
FakeNode.prototype.setAttribute=function(k,v){ if(k==='class'){ this._cls=new Set(String(v).split(/\s+/).filter(Boolean)); } else if (k==='hidden') this.hidden=true; else if (k==='disabled') this.disabled=true; this.attrs[k]=v; };
FakeNode.prototype.addEventListener=function(t,f){ (this._ev[t]=this._ev[t]||[]).push(f); };
FakeNode.prototype.fire=async function(t){ for (const f of (this._ev[t]||[])) await f({ preventDefault(){}, currentTarget:this }); };
FakeNode.prototype.click=function(){ return this.fire('click'); };
FakeNode.prototype._all=function(){ const o=[]; for (const c of this.children) if (c.nodeType===1){ o.push(c); o.push(...c._all()); } return o; };
FakeNode.prototype.querySelector=function(sel){ const cls=sel.replace(/^\./,''); return this._all().find(n=>n._cls.has(cls)) || null; };
Object.defineProperty(FakeNode.prototype,'className',{set(v){this.setAttribute('class',v)},get(){return [...this._cls].join(' ')}});
Object.defineProperty(FakeNode.prototype,'classList',{get(){ const s=this._cls; return { contains:(c)=>s.has(c), toggle:(c,on)=>{ if(on===undefined) on=!s.has(c); on?s.add(c):s.delete(c); return on; }, add:(c)=>s.add(c), remove:(c)=>s.delete(c) }; }});
Object.defineProperty(FakeNode.prototype,'innerHTML',{set(v){ for (const c of this.children) if (c.nodeType===1) c.parent=null; this.children=[]; }, get(){ return ''; }});
Object.defineProperty(FakeNode.prototype,'textContent',{set(v){ this.children=[{nodeType:3,text:String(v)}]; }, get(){ return this.children.map(c=>c.nodeType===3?c.text:c.textContent).join(''); }});
globalThis.document={ createElement:(t)=>new FakeNode(t), createTextNode:(t)=>({nodeType:3,text:String(t)}), visibilityState:'visible' };
let STORE = {}; let STORE_BROKEN = false;
globalThis.localStorage={ getItem(k){ if (STORE_BROKEN) throw new Error('quota'); return k in STORE ? STORE[k] : null; }, setItem(k,v){ if (STORE_BROKEN) throw new Error('quota'); STORE[k]=String(v); } };
function T(pt,en){ return pt; }
JS
  strip "$W/shared/dom.js"; strip "$W/problemas/testrun.js"
  cat <<'JS'
let PASS=0, FAIL=0; const ck=(n,c)=>{ if (c) PASS++; else { FAIL++; print('FALHOU: '+n); } };
const RUN1='a'.repeat(32), RUN2='b'.repeat(32);
let ID='', POSTS=[], GETS={}, SCHED=[], OPENED=null, NOW=1790000000000;
const b64 = (s) => 'T:'+s;             // textToBase64 falso (o teste só confere QUAL caminho foi usado)
function mk(){ return makeTestRun({
  id: () => ID,
  post: async (p, b) => { POSTS.push([p, b]); if (POST_ERR) throw POST_ERR; return { run: NEXT_RUN }; },
  get: async (p) => { const run = p.split('run=')[1]; const r = GETS[run]; if (r instanceof Error) throw r; if (!r) { const e = new Error('nf'); e.status = 404; throw e; } return r; },
  report: async (run) => '<html>'+run+'</html>', openHtmlReport: (h) => { OPENED = h; },
  createEditor: async (m, o) => { let d = o.doc; return { getValue: () => d, setValue: (v) => { d = v; } }; },
  cmFor: () => 'cpp', fileToBase64: async (f) => 'F:'+f.name, textToBase64: b64,
  hiddenFile: () => { const i = new FakeNode('input'); i.files = []; return i; },
  now: () => NOW, schedule: (fn, ms) => { SCHED.push([fn, ms]); return SCHED.length; }, visible: () => true,
}); }
let POST_ERR = null, NEXT_RUN = RUN1;
const all = (n) => n._all ? n._all() : [];
const txt = (n) => n.textContent;
const byText = (root, s) => all(root).find(n => n.tagName==='BUTTON' && txt(n).includes(s));
const cardsOf = (tr) => all(tr.panel).filter(n => n._cls.has('trun-card'));
const flush = async () => { for (let i = 0; i < 30; i++) await Promise.resolve(); };
(async () => {
  // 1. sem id
  let tr = mk(); tr.refresh();
  const runBtn = byText(tr.panel, 'Rodar no juiz');
  const unsaved = all(tr.panel).find(n => txt(n).startsWith('Salve o problema'));
  ck('sem id: botão desabilitado e aviso visível', runBtn.disabled === true && unsaved.hidden === false);
  // 2. com id: lista vazia
  ID = 'o#p'; tr.refresh();
  ck('com id: botão ligado, aviso escondido', runBtn.disabled === false && unsaved.hidden === true);
  ck('lista vazia avisa', all(tr.panel).some(n => n._cls.has('trun-empty')));
  // 3. colar (via prefill) e enviar
  GETS[RUN1] = { run: RUN1, status: 'queued', lang: 'CPP', requested_at: NOW/1000 - 120 };
  await tr.prefill('sol.cpp', 'int main(){}');
  await runBtn.click(); await flush();
  ck('POST /problems/test-run com id, filename e o TEXTO', POSTS.length === 1 && POSTS[0][0] === '/problems/test-run' && JSON.stringify(POSTS[0][1]) === JSON.stringify({ id: 'o#p', filename: 'sol.cpp', code_b64: 'T:int main(){}' }));
  ck('run lembrado no localStorage do problema', JSON.parse(STORE['moj_testruns_o#p'] || '[]')[0].run === RUN1);
  let cards = cardsOf(tr); const card1 = cards[0];
  ck('cartão criado, na fila (há 2 min)', cards.length === 1 && txt(card1).includes('na fila') && txt(card1).includes('há 2 min'));
  ck('poll re-armado em 3 s', SCHED.length > 0 && SCHED[SCHED.length-1][1] === 3000);
  ck('sem o aviso de lista vazia', !all(tr.panel).some(n => n._cls.has('trun-empty')));
  // 4. termina
  GETS[RUN1] = { run: RUN1, status: 'done', lang: 'CPP', verdict: 'Accepted,100p', verdict_canon: 'Accepted', correct: 3, total_tests: 3, duration_s: 1.25, tl_used: 1, report: true,
    tests: [{ name: 't1', code: 'AC', time: 0.01, tl: 1 }, { name: 't2', code: 'AC', time: 0.02, tl: 1 }, { name: 't3', code: 'AC', time: 0.03, tl: 1 }] };
  const nsch = SCHED.length; await SCHED[SCHED.length-1][0](); await flush();
  cards = cardsOf(tr);
  ck('done: MESMO nó do cartão (em lugar)', cards.length === 1 && cards[0] === card1);
  ck('done: veredicto, 3/3 testes, duração e TL', txt(card1).includes('Accepted,100p') && txt(card1).includes('3/3 testes') && txt(card1).includes('1.25s') && txt(card1).includes('TL 1s'));
  ck('done: tabela de testes (soltests) com 3 linhas', all(card1).filter(n => n.tagName==='TABLE' && n._cls.has('soltests')).length === 1 && all(card1).filter(n => n.tagName==='TR').length === 4);
  ck('tudo terminou: poll NÃO re-arma', SCHED.length === nsch);
  const det = all(card1).find(n => n.tagName==='DETAILS'); det.open = true;
  await tr.onVisible(); await flush();
  ck('nada mudou: <details> é o MESMO nó e segue aberto', all(card1).find(n => n.tagName==='DETAILS') === det && det.open === true);
  // 5. report
  const rep = all(card1).find(n => n.tagName==='A' && txt(n).includes('report')); await rep.click(); await flush();
  ck('📄 report abre o html do servidor', OPENED === '<html>'+RUN1+'</html>');
  // 6. 429
  POST_ERR = Object.assign(new Error('Você já tem 3 teste(s) na fila — aguarde terminarem'), { status: 429 });
  await runBtn.click(); await flush();
  ck('429: mensagem do servidor na tela e nenhum run novo', all(tr.panel).some(n => txt(n) === 'Você já tem 3 teste(s) na fila — aguarde terminarem') && cardsOf(tr).length === 1);
  POST_ERR = null;
  // 7. arquivo escolhido: bytes se não editado
  const fi = all(tr.panel).find(n => n.tagName==='INPUT' && n.files);
  fi.files = [{ name: 'a.c', text: async () => 'int x;' }]; await fi.fire('change'); await flush();
  NEXT_RUN = RUN2; GETS[RUN2] = { run: RUN2, status: 'queued', requested_at: NOW/1000 };
  await runBtn.click(); await flush();
  ck('arquivo NÃO editado: vão os BYTES (fileToBase64)', POSTS[POSTS.length-1][1].code_b64 === 'F:a.c' && POSTS[POSTS.length-1][1].filename === 'a.c');
  ck('mais nova em cima', cardsOf(tr).length === 2 && cardsOf(tr)[1] === card1);
  // 8. erro de rede não apaga; 404 = expirou
  GETS[RUN2] = new Error('rede'); await tr.onVisible(); await flush();
  ck('erro de rede: cartão continua na fila', cardsOf(tr).length === 2 && txt(cardsOf(tr)[0]).includes('na fila'));
  delete GETS[RUN2]; await tr.onVisible(); await flush();
  ck('404: expirou', txt(cardsOf(tr)[0]).includes('expirou'));
  // 9. outra instância (recarga da página) lembra a lista
  const tr2 = mk(); tr2.refresh(); await flush();
  ck('recarga: a lista volta do localStorage', cardsOf(tr2).length === 2);
  // 10. localStorage quebrado não derruba
  STORE_BROKEN = true; const tr3 = mk(); tr3.refresh(); await flush();
  ck('localStorage quebrado: lista vazia, sem exceção', cardsOf(tr3).length === 0);
  print(`RESULT: ${PASS} passed, ${FAIL} failed`);
})().catch(e => { print('EXCEÇÃO: ' + e + '\n' + (e.stack || '')); print('RESULT: 0 passed, 1 failed'); });
JS
} > "$T/t.js"
# gjs roda o laço de eventos p/ as promessas? — sim, com o mainloop do GLib: usa o script direto
out="$(gjs -m "$T/t.js" 2>&1 || gjs "$T/t.js" 2>&1)"
printf '%s\n' "$out" | grep -v '^$'
grep -q 'RESULT: [0-9]* passed, 0 failed' <<<"$out"
