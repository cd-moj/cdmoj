#!/bin/bash
# smoke-submit-ux.gjs.sh — o componente de ENVIO pela web (web/shared/submit-ux.js, 01/10/2026), sem pop-up:
#   • a máquina POR PROBLEMA: idle → sending (JÁ no clique, antes do prepare/leitura do arquivo) → sent (1,5 s,
#     cliques ignorados) → idle; clique durante sending/sent = ignorado (a trava do clique duplo);
#   • mesmo código (hash de linguagem + conteúdo, guardado só depois do envio com SUCESSO) ⇒ o 1º clique ARMA
#     (confirm, 5 s) e o 2º clique NO MESMO botão envia; outra linguagem = código novo; a janela expira;
#   • erro de validação/servidor volta a idle e não grava memória; localStorage que lança = sem memória;
#   • textos: 429 submit_busy legível, sem resposta = "confira antes de reenviar" (nunca "nada foi enviado");
#   • o DOM: roda + aria-busy/aria-disabled no botão clicado, o outro botão do problema inerte, verde
#     "✓ Enviado", âmbar "Mesmo código…", linha de status role=status com a hora, o que e onde acompanhar.
# Sem gjs: pula.
set -u
command -v gjs >/dev/null 2>&1 || { echo "submit-ux.gjs: gjs ausente — pulando"; exit 0; }
W="$(cd "$(dirname "$(readlink -f "$0")")/../../web" && pwd)"
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
JS="$(mktemp --suffix=.js)"; trap 'rm -f "$JS"' EXIT
{ cat <<'EOF'
function FakeNode(tag){ this.tagName=tag; this.nodeType=1; this.children=[]; this.attrs={}; this.style={}; this._text=''; this.dataset={}; this.ev={}; }
FakeNode.prototype.append=function(){ for (const k of arguments) this.children.push(k!==null&&typeof k==='object'?k:{nodeType:3,text:String(k)}); };
FakeNode.prototype.setAttribute=function(k,v){ this.attrs[k]=String(v); };
FakeNode.prototype.getAttribute=function(k){ return k in this.attrs ? this.attrs[k] : null; };
FakeNode.prototype.addEventListener=function(k,f){ this.ev[k]=f; };
FakeNode.prototype._all=function(){ const out=[]; for (const c of this.children) { if (c.nodeType===1) { out.push(c); out.push(...c._all()); } } return out; };
FakeNode.prototype.find=function(pred){ return this._all().filter(pred); };
Object.defineProperty(FakeNode.prototype,'className',{set(v){this.attrs['class']=v},get(){return this.attrs['class']||''}});
Object.defineProperty(FakeNode.prototype,'textContent',{ set(v){this._text=String(v); this.children=[];},
  get(){ let t=this._text; for(const c of this.children) t+= c.nodeType===3?c.text:(c.textContent||''); return t; }});
globalThis.document={ createElement:(t)=>new FakeNode(t), createTextNode:(t)=>({nodeType:3,text:String(t),textContent:String(t)}) };
function T(pt){ return pt; } function uiLocale(){ return 'pt-BR'; }
EOF
  strip "$W/shared/dom.js"; strip "$W/shared/submit-ux.js"
  cat <<'EOF'
let pass=0, fail=0; const ck=(m,ok,d)=>{ if (ok) { print('  ok: '+m); pass++; } else { print('  FAIL: '+m+' :: '+(d||'')); fail++; } };
const flush = async () => { for (let i = 0; i < 12; i++) await null; };
// relógio e timers FALSOS
let NOW = 1790000000000; const TIMERS = [];
const setTimer = (f, ms) => { const t = { f, at: NOW + ms, done: false }; TIMERS.push(t); return t; };
const clearTimer = (t) => { if (t) t.done = true; };
const advance = (ms) => { NOW += ms; for (const t of TIMERS) if (!t.done && t.at <= NOW) { t.done = true; t.f(); } };
function store() { const m = new Map(); return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)), m }; }
const deferred = () => { let res, rej; const p = new Promise((a, b) => { res = a; rej = b; }); return { p, res, rej }; };
const prep = (lang, code) => async () => ({ payload: { filename: 'a.' + lang, code_b64: code }, lang });

(async () => {
  print('== codeHash ==');
  ck('determinístico', codeHash('c', 'QUJD') === codeHash('c', 'QUJD'));
  ck('linguagem entra no hash', codeHash('c', 'QUJD') !== codeHash('cpp', 'QUJD'));
  ck('conteúdo entra no hash', codeHash('c', 'QUJD') !== codeHash('c', 'QUJE'));
  ck('caixa da linguagem não importa', codeHash('CPP', 'x') === codeHash('cpp', 'x'));

  print('== máquina de estados ==');
  const S = store(); const SENT = [];
  let sendD = null;
  const flow = makeSubmitFlow({ key: 'k1', storage: S, now: () => NOW, setTimer, clearTimer,
    send: (payload) => { SENT.push(payload); sendD = deferred(); return sendD.p; } });
  const A = {}, B = {};
  const pd = deferred();
  const c1 = flow.click(A, () => pd.p);
  ck('sending JÁ no clique (antes do prepare terminar)', flow.state === 'sending' && flow.source === A, flow.state);
  ck('clique de OUTRO botão durante sending = ignorado', (await flow.click(B, prep('c', 'X'))).kind === 'ignored');
  ck('clique do MESMO botão durante sending = ignorado', (await flow.click(A, prep('c', 'X'))).kind === 'ignored');
  pd.res({ payload: { filename: 'a.c', code_b64: 'AAA' }, lang: 'c' }); await flush();
  ck('prepare pronto ⇒ um POST só', SENT.length === 1 && flow.state === 'sending', SENT.length);
  sendD.res({ submission_id: 's1' }); const r1 = await c1;
  ck('resposta ⇒ sent', r1.kind === 'sent' && flow.state === 'sent' && r1.resp.submission_id === 's1');
  ck('memória gravada SÓ agora', S.getItem('k1') && JSON.parse(S.getItem('k1')).lang === 'c');
  ck('durante sent (1,5 s) clique é ignorado', (await flow.click(A, prep('c', 'BBB'))).kind === 'ignored' && SENT.length === 1);
  advance(SENT_MS - 1); ck('ainda sent a 1499 ms', flow.state === 'sent');
  advance(1); ck('volta a idle em SENT_MS = 1500', flow.state === 'idle' && SENT_MS === 1500);

  print('== mesmo código: 2º clique ==');
  const r2 = await flow.click(A, prep('c', 'AAA'));
  ck('mesmo código + linguagem ⇒ confirm (sem POST)', r2.kind === 'confirm' && flow.state === 'confirm' && SENT.length === 1);
  ck('confirm lembra a hora do envio anterior', r2.at === 1790000000000 && flow.armedAt === r2.at, r2.at);
  const c3 = flow.click(A, prep('c', 'AAA')); await flush(); sendD.res({ submission_id: 's2' }); const r3 = await c3;
  ck('2º clique NO MESMO botão envia', r3.kind === 'sent' && SENT.length === 2);
  advance(SENT_MS);
  await flow.click(A, prep('c', 'AAA'));
  ck('armado de novo', flow.state === 'confirm');
  advance(CONFIRM_MS - 1); ck('ainda armado a 4999 ms', flow.state === 'confirm');
  advance(1); ck('a janela expira em CONFIRM_MS = 5000', flow.state === 'idle' && CONFIRM_MS === 5000);
  await flow.click(A, prep('c', 'AAA'));
  const rB = await flow.click(B, prep('c', 'AAA'));
  ck('armado por A, clique em B só re-arma (não envia)', rB.kind === 'confirm' && flow.source === B && SENT.length === 2);
  advance(CONFIRM_MS);
  const c4 = flow.click(A, prep('cpp', 'AAA')); await flush(); sendD.res({ submission_id: 's3' }); const r4 = await c4;
  ck('mesmo texto em OUTRA linguagem = código novo (envia direto)', r4.kind === 'sent' && SENT.length === 3);
  advance(SENT_MS);

  print('== erros ==');
  const r5 = await flow.click(A, async () => { throw new Error('Escreva o seu código no editor.'); });
  ck('validação ⇒ invalid + idle, sem POST', r5.kind === 'invalid' && r5.message.includes('editor') && flow.state === 'idle' && SENT.length === 3);
  const c6 = flow.click(A, prep('c', 'ZZZ')); await flush();
  const e429 = Object.assign(new Error('x'), { status: 429, code: 'submit_busy', data: { inflight: 3, max: 3 } });
  sendD.rej(e429); const r6 = await c6;
  ck('erro do servidor ⇒ error + idle', r6.kind === 'error' && flow.state === 'idle');
  const c7 = flow.click(A, prep('c', 'ZZZ')); await flush();
  ck('envio que FALHOU não arma o "mesmo código" (vai direto ao POST)', SENT.length === 5 && flow.state === 'sending', SENT.length);
  sendD.res({ submission_id: 's4' }); await c7; advance(SENT_MS);
  const bad = { getItem() { throw new Error('bloqueado'); }, setItem() { throw new Error('cheio'); } };
  const f2 = makeSubmitFlow({ key: 'k', storage: bad, now: () => NOW, setTimer, clearTimer, send: async () => ({ submission_id: 'q' }) });
  const ra = await f2.click(A, prep('c', 'AAA')); advance(SENT_MS); const rb = await f2.click(A, prep('c', 'AAA'));
  ck('localStorage que lança: envia sempre, nunca arma', ra.kind === 'sent' && rb.kind === 'sent');

  print('== submitErrorText ==');
  ck('429 submit_busy: legível, com o número', submitErrorText(e429).includes('3 envios esperando o veredicto'));
  ck('sem resposta (rede): manda conferir antes de reenviar', submitErrorText(new TypeError('Failed to fetch')).includes('Confira a lista de envios'));
  ck('502 sem código idem', submitErrorText({ status: 502, message: 'Resposta inválida do servidor' }).includes('Confira'));
  ck('erro com código: a mensagem do servidor', submitErrorText({ status: 400, code: 'lang_not_allowed', message: 'Linguagem .x não aceita' }) === 'Erro: Linguagem .x não aceita');

  print('== DOM: botão + linha de status ==');
  const S2 = store(); let d2 = null; const sentCb = [];
  const fl = makeSubmitFlow({ key: 'kd', storage: S2, now: () => NOW, setTimer, clearTimer, send: () => { d2 = deferred(); return d2.p; } });
  const btn = el('button', { class: 'btn' }, 'Enviar'), st = el('span', { class: 'submit-steps' });
  const btn2 = el('button', { class: 'btn' }, 'Enviar solução'), st2 = el('span', { class: 'submit-steps' });
  const pdom = deferred();
  attachSubmitButton(fl, btn, st, { label: () => 'Enviar', prepare: () => pdom.p, describe: () => 'A · C', hint: () => 'acompanhe em Minhas submissões',
    onSent: (resp) => sentCb.push(resp) });
  attachSubmitButton(fl, btn2, st2, { label: () => 'Enviar solução', prepare: prep('c', 'ED') });
  ck('linha de status é role=status (leitor de tela)', st.getAttribute('role') === 'status' && st.getAttribute('aria-live') === 'polite');
  ck('rótulo de repouso', btn.textContent === 'Enviar' && btn.getAttribute('aria-disabled') === 'false');
  btn.ev.click(); await null;
  ck('clicado: roda + "Enviando…" + aria-busy', btn.className.includes('is-sending') && btn.find((n) => n.className === 'spin').length === 1
     && btn.textContent.includes('Enviando') && btn.getAttribute('aria-busy') === 'true', btn.className + ' | ' + btn.textContent);
  ck('o OUTRO botão do problema fica inerte (aria-disabled), sem roda', btn2.getAttribute('aria-disabled') === 'true' && !btn2.className.includes('is-sending') && btn2.textContent === 'Enviar solução');
  btn2.ev.click(); await flush();
  ck('clique no outro durante o envio não dispara nada', fl.state === 'sending' && fl.source !== null);
  pdom.res({ payload: { filename: 'a.c', code_b64: 'DOM' }, lang: 'c' }); await flush();
  d2.res({ submission_id: 'sd', epoch: 1790000123 }); await flush();
  ck('verde "✓ Enviado"', btn.className.includes('is-sent') && btn.textContent === '✓ Enviado', btn.textContent);
  const ok = st.find((n) => n.className === 'submit-ok')[0];
  ck('status: "✓ Enviado às <hora do servidor> — o que · onde"', ok && ok.textContent.startsWith('✓ Enviado às ') && ok.textContent.includes(' — A · C')
     && ok.textContent.includes('acompanhe em Minhas submissões'), ok && ok.textContent);
  ck('onSent recebeu a resposta (a página põe a linha pendente)', sentCb.length === 1 && sentCb[0].submission_id === 'sd');
  advance(SENT_MS);
  ck('volta ao rótulo', btn.textContent === 'Enviar' && !btn.className.includes('is-sent') && btn.getAttribute('aria-disabled') === 'false');
  ck('a confirmação fica na linha até a próxima ação', st.textContent.includes('Enviado às'));
  // o editor com o MESMO código que acabou de ir pelo arquivo? hash diferente (conteúdo) ⇒ envia
  btn2.ev.click(); await flush(); d2.res({ submission_id: 'se' }); await flush(); advance(SENT_MS);
  ck('a próxima ação limpa a linha do outro botão', st.textContent === '');
  btn2.ev.click(); await flush();
  ck('mesmo código no editor ⇒ âmbar "Mesmo código do envio das HH:MM — enviar de novo?"', btn2.className.includes('is-confirm')
     && /^Mesmo código do envio das \d\d:\d\d — enviar de novo\?$/.test(btn2.textContent), btn2.textContent);
  ck('âmbar não trava o botão', btn2.getAttribute('aria-disabled') === 'false');
  btn2.ev.click(); await flush(); d2.res({ submission_id: 'sf' }); await flush();
  ck('2º clique envia', btn2.className.includes('is-sent'));
  advance(SENT_MS);
  const btn3 = el('button', {}, 'x'), st3 = el('span', {});
  attachSubmitButton(fl, btn3, st3, { label: () => 'x', prepare: async () => { throw new Error('Escreva o seu código no editor.'); } });
  btn3.ev.click(); await flush();
  ck('validação: caixa de erro na linha', st3.find((n) => n.className === 'error-box').length === 1 && st3.textContent.includes('Escreva'));

  print(''); print('RESULT: ' + pass + ' passed, ' + fail + ' failed');
  imports.system.exit(fail > 0 ? 1 : 0);
})().catch((e) => { print('EXC ' + e + '\n' + e.stack); imports.system.exit(2); });
EOF
} > "$JS"
gjs "$JS"
