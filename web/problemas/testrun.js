// problemas/testrun.js — sub-aba "🧪 testar no juiz" do editor: roda UMA solução avulsa no juiz de
// verdade (POST /problems/test-run — mesma jaula e mesmo TL de uma submissão), contra os testes SALVOS
// no servidor, fora do pacote, do histórico e do placar. É o `moj testrun <id> <arquivo>` da CLI na web
// (pedido do Ribas, 24/09/2026). A API está em server/api/v1/handlers/problems/test-run.sh.
//
// O módulo não conhece o editor: recebe tudo por `ctx` (é o que deixa testar no gjs com API falsa —
// server/test/smoke-testrun-panel.gjs.sh). Regras que ele segue:
//   · a lista de execuções é lembrada POR PROBLEMA no localStorage (até 10; o servidor guarda 7 dias);
//   · os cartões se atualizam EM LUGAR (chave = id do run; nó e <details> preservados — a regra do
//     auto-refresh da casa): um cartão só é refeito quando o conteúdo muda;
//   · o poll é SERIALIZADO (nunca 2 rodadas em voo), pausa com a aba escondida e não desiste por
//     relógio (lição do smoke-calib-poll: o juiz pode levar minutos); erro de rede não apaga nada.
import { el } from '/shared/dom.js';
import { T } from '/shared/i18n.js';

const MAX_RUNS = 10;
const RUN_RE = /^[a-f0-9]{32}$/;
const OK_CODES = new Set(['AC', 'AC,PE']);
const secs = (v) => (v == null || v === '' || !Number.isFinite(+v)) ? '—' : (+(+v).toFixed(4)) + 's';

// tabela de testes {name, code, time, tl} — o MESMO visual da calibração por extenso (solsBlock do
// editar.js usa esta função; uma implementação só). Teste ACEITO com tempo acima do TL passou pela
// tolerância do conf (TLMOD[<lang>|default.drift]): o tempo fica em amarelo, com a explicação no title —
// sem isso lia-se "passou do limite e deu AC?" (relato do Daniel Saad sobre o report.html, 24/09/2026).
const overTol = (t) => OK_CODES.has(t.code) && t.time != null && t.tl != null && +t.time > +t.tl;
export function testsTable(tests) {
  const tb = el('tbody', {});
  (tests || []).forEach(t => tb.append(el('tr', {},
    el('td', {}, t.name || ''),
    el('td', { class: OK_CODES.has(t.code) ? '' : 'bad' }, t.code || '—'),
    el('td', overTol(t)
      ? { class: 'num drift', title: T('Acima do tempo-limite, mas aceito pela tolerância do conf (TLMOD[<linguagem>.drift] ou TLMOD[default.drift]).',
                                         'Above the time limit, but accepted by the conf tolerance (TLMOD[<language>.drift] or TLMOD[default.drift]).',
                                         'Por encima del tiempo límite, pero aceptado por la tolerancia del conf (TLMOD[<language>.drift] o TLMOD[default.drift]).') }
      : { class: 'num' }, t.time == null ? '—' : (+t.time).toFixed(2) + 's'),
    el('td', { class: 'num' }, t.tl == null ? '—' : secs(t.tl)))));
  return el('table', { class: 'soltests' },
    el('thead', {}, el('tr', {},
      el('th', {}, T('teste', 'test', 'prueba')), el('th', {}, T('resultado', 'result', 'resultado')),
      el('th', {}, T('tempo', 'time', 'tiempo')), el('th', {}, 'TL'))),
    tb);
}

// lista de execuções lembradas, por problema: [{run, filename, at}] (mais nova primeiro)
const storeKey = (id) => 'moj_testruns_' + id;
export function loadRuns(id) {
  try {
    const a = JSON.parse(globalThis.localStorage.getItem(storeKey(id)) || '[]');
    return Array.isArray(a) ? a.filter(r => r && RUN_RE.test(r.run)).slice(0, MAX_RUNS) : [];
  } catch { return []; }
}
export function saveRuns(id, list) {
  try { globalThis.localStorage.setItem(storeKey(id), JSON.stringify(list.slice(0, MAX_RUNS))); } catch { /* sem storage: vale a sessão */ }
}

// ctx: { id(): string, get(path), post(path, body), report(run): Promise<html>, openHtmlReport(html),
//        createEditor(mount, {doc, cm}), cmFor(filename), fileToBase64(file), textToBase64(text),
//        hiddenFile(), now?(): ms, schedule?(fn, ms), visible?(): bool }
export function makeTestRun(ctx) {
  const now = ctx.now || (() => Date.now());
  const schedule = ctx.schedule || ((fn, ms) => setTimeout(fn, ms));
  const visible = ctx.visible || (() => typeof document === 'undefined' || document.visibilityState !== 'hidden');
  let runs = [];            // [{run, filename, at}] — do problema atual
  const recs = new Map();   // run -> último registro do servidor (ou {status:'expired'})
  const cards = new Map();  // run -> {root, head, body, sig}
  let polling = false, timer = null, curId = '';
  let ed = null, edCm = null, picked = null, pickedText = null;

  const msg = el('div', { class: 'small', style: 'margin:.3rem 0;min-height:1.1em' });
  const setMsg = (t, bad) => { msg.textContent = t || ''; msg.style.color = bad ? '#ff8a8a' : ''; };
  const fnInput = el('input', { type: 'text', placeholder: 'sol.cpp', style: 'max-width:14rem' });
  const mount = el('div', { class: 'editor-mount sec' });   // o tamanho menor do editor (13rem, redimensionável)
  const fi = ctx.hiddenFile(false);
  const pickBtn = el('button', { class: 'btn ghost', type: 'button', onclick: () => fi.click() }, T('📁 escolher arquivo', '📁 choose file', '📁 elegir archivo'));
  const runBtn = el('button', { class: 'btn', type: 'button', onclick: () => submit() }, T('▶ Rodar no juiz', '▶ Run on the judge', '▶ Ejecutar en el juez'));
  const unsaved = el('div', { class: 'small muted', hidden: true }, T('Salve o problema primeiro: o teste roda contra o pacote do servidor.', 'Save the problem first: the test runs against the package on the server.', 'Guarda el problema primero: la prueba corre contra el paquete del servidor.'));
  const list = el('div', {});
  const panel = el('div', { id: 'trunPanel', class: 'solpanel', 'data-cat': 'trun', hidden: true },
    el('p', { class: 'small muted', style: 'margin:.2rem 0 .5rem' },
      T('Roda UMA solução no juiz de verdade, com a mesma jaula e o mesmo tempo-limite de uma submissão. Ela roda contra os testes SALVOS no servidor. Ela não entra no pacote, no histórico nem no placar. Use para testar a solução de um aluno ou uma ideia sem mexer no pacote. A linguagem vem da extensão do arquivo.',
        'Runs ONE solution on the real judge, with the same sandbox and the same time limit as a submission. It runs against the tests SAVED on the server. It does not enter the package, the history or the scoreboard. Use it to test a student solution or an idea without changing the package. The language comes from the file extension.',
        'Ejecuta UNA solución en el juez real, con la misma jaula y el mismo tiempo límite que un envío. Corre contra las pruebas GUARDADAS en el servidor. No entra en el paquete, en el historial ni en el marcador. Úsalo para probar la solución de un estudiante o una idea sin tocar el paquete. El lenguaje viene de la extensión del archivo.')),
    el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap;margin-bottom:.3rem' },
      pickBtn, fi, el('span', { class: 'small muted' }, T('ou cole o código — arquivo', 'or paste the code — file', 'o pega el código — archivo')), fnInput,
      el('span', { style: 'flex:1' }), runBtn),
    mount, unsaved, msg,
    el('h4', { style: 'margin:.8rem 0 .2rem' }, T('Execuções', 'Runs', 'Ejecuciones')),
    list);

  // SERIALIZADO: abrir a sub-aba (cria vazio) e o 🧪 de uma solução (preenche) chegam juntos — sem a
  // fila, os dois criariam um CodeMirror cada no mesmo mount
  let edChain = Promise.resolve();
  async function _ensureEditor(doc) {
    const cm = ctx.cmFor(fnInput.value) || null;
    if (ed && cm === edCm) { if (doc != null) ed.setValue(doc); return; }
    const keep = doc != null ? doc : (ed ? ed.getValue() : '');
    mount.innerHTML = ''; ed = await ctx.createEditor(mount, { doc: keep, cm }); edCm = cm;
  }
  function ensureEditor(doc) { edChain = edChain.then(() => _ensureEditor(doc), () => _ensureEditor(doc)); return edChain; }
  fnInput.addEventListener('change', () => { ensureEditor(null); });
  fi.addEventListener('change', async () => {
    const f = fi.files && fi.files[0]; if (!f) return;
    picked = f; pickedText = await f.text();
    fnInput.value = f.name; await ensureEditor(pickedText); fi.value = '';
    setMsg(T('Arquivo carregado. Rode como está ou edite antes.', 'File loaded. Run it as it is or edit it first.', 'Archivo cargado. Ejecútalo tal cual o edítalo antes.'));
  });

  // preenche com uma solução do editor (o texto ATUAL, sem salvar) — o 🧪 de cada linha de solução
  async function prefill(filename, code) {
    fnInput.value = filename || ''; picked = null; pickedText = null;
    await ensureEditor(code || ''); setMsg('');
  }

  async function submit() {
    const id = ctx.id(); if (!id) { unsaved.hidden = false; return; }
    const filename = fnInput.value.trim();
    const code = ed ? ed.getValue() : '';
    if (!filename) { setMsg(T('Dê um nome ao arquivo, com a extensão (ex.: sol.cpp).', 'Name the file, with the extension (e.g. sol.cpp).', 'Dale un nombre al archivo, con la extensión (ej.: sol.cpp).'), true); return; }
    if (!code.trim()) { setMsg(T('Cole o código ou escolha um arquivo.', 'Paste the code or choose a file.', 'Pega el código o elige un archivo.'), true); return; }
    runBtn.disabled = true; setMsg(T('Enviando…', 'Sending…', 'Enviando…'));
    try {
      // arquivo escolhido e NÃO editado: vão os BYTES dele (um .cpp em Latin-1 não passa pelo UTF-8)
      const b64 = (picked && code === pickedText && filename === picked.name) ? await ctx.fileToBase64(picked) : ctx.textToBase64(code);
      const j = await ctx.post('/problems/test-run', { id, filename, code_b64: b64 });
      if (!j || !RUN_RE.test(j.run || '')) throw new Error(T('resposta inesperada do servidor', 'unexpected server response', 'respuesta inesperada del servidor'));
      runs = [{ run: j.run, filename, at: now() }, ...runs.filter(r => r.run !== j.run)].slice(0, MAX_RUNS);
      saveRuns(id, runs); recs.set(j.run, { run: j.run, filename, status: 'queued', requested_at: Math.floor(now() / 1000) });
      setMsg(T('Na fila do juiz. O resultado aparece abaixo.', 'Queued on the judge. The result shows up below.', 'En cola en el juez. El resultado aparece abajo.'));
      render(); poll();
    } catch (e) {
      setMsg((e && e.message) || T('Falha ao enviar.', 'Failed to send.', 'Error al enviar.'), true);
    } finally { runBtn.disabled = false; }
  }

  // ---- cartões (em lugar) ----
  const sigOf = (r) => r ? JSON.stringify([r.status, r.lang, r.verdict, r.correct, r.total_tests, r.duration_s, r.tl_used, r.report, (r.tests || []).length]) : 'none';
  const LANG_NAME = { C: 'C', CPP: 'C++', PY: 'Python', JAVA: 'Java', RS: 'Rust', GO: 'Go', JS: 'JavaScript', HS: 'Haskell', PAS: 'Pascal', SH: 'Shell', KT: 'Kotlin', CS: 'C#' };
  function headOf(it, r) {
    const when = new Date(it.at || 0);
    const hh = String(when.getHours()).padStart(2, '0') + ':' + String(when.getMinutes()).padStart(2, '0');
    const lang = r && r.lang ? (LANG_NAME[r.lang] || r.lang) : '';
    return [el('b', {}, it.filename || (r && r.filename) || '?'), el('span', { class: 'muted' }, [lang, hh].filter(Boolean).map(x => ' · ' + x).join(''))];
  }
  function waitingText(r) {
    const since = r && r.requested_at ? Math.max(0, Math.floor((now() / 1000 - r.requested_at) / 60)) : 0;
    return T(`⏳ na fila / julgando (há ${since} min)`, `⏳ queued / judging (${since} min ago)`, `⏳ en cola / juzgando (hace ${since} min)`);
  }
  function bodyOf(it, r) {
    if (!r) return [el('span', { class: 'muted' }, T('consultando…', 'checking…', 'consultando…'))];
    if (r.status === 'expired') return [el('span', { class: 'muted' }, T('expirou (o servidor guarda 7 dias)', 'expired (the server keeps it 7 days)', 'expiró (el servidor lo guarda 7 días)'))];
    if (r.status !== 'done') return [el('span', { class: 'trun-wait' }, waitingText(r))];
    const acc = String(r.verdict_canon || r.verdict || '').startsWith('Accepted');
    const out = [el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap' },
      el('span', { class: 'pill ' + (acc ? 'ok' : 'no') }, r.verdict || r.verdict_canon || '?'),
      el('span', { class: 'small muted' },
        `${r.correct != null ? r.correct : '?'}/${r.total_tests != null ? r.total_tests : '?'} ` + T('testes', 'tests', 'pruebas')
        + (r.duration_s != null ? ` · ${secs(r.duration_s)}` : '') + (r.tl_used != null ? ` · TL ${secs(r.tl_used)}` : '')),
      r.report ? el('a', { href: '#', onclick: (e) => { e.preventDefault(); openReport(it.run); } }, '📄 report') : null)];
    if ((r.tests || []).length) out.push(el('details', {}, el('summary', { class: 'small' }, T('testes', 'tests', 'pruebas') + ` (${r.tests.length})`), testsTable(r.tests)));
    return out;
  }
  function render() {
    const want = runs.map(r => r.run);
    for (const [k, c] of cards) if (!want.includes(k)) { c.root.remove(); cards.delete(k); }
    runs.forEach((it, i) => {
      const r = recs.get(it.run);
      let c = cards.get(it.run);
      if (!c) {
        const head = el('div', { class: 'row', style: 'gap:.4rem;align-items:center;flex-wrap:wrap' });
        const body = el('div', { style: 'margin-top:.2rem' });
        const drop = el('button', { class: 'btn ghost small', type: 'button', title: T('tirar da lista', 'remove from the list', 'quitar de la lista'),
          onclick: () => { runs = runs.filter(x => x.run !== it.run); saveRuns(curId, runs); recs.delete(it.run); render(); } }, '✕');
        const root = el('div', { class: 'solrow trun-card', style: 'display:block' }, el('div', { class: 'row', style: 'gap:.4rem;align-items:center' }, head, el('span', { style: 'flex:1' }), drop), body);
        c = { root, head, body, sig: null }; cards.set(it.run, c);
      }
      const s = sigOf(r);
      if (s !== c.sig) {
        c.head.innerHTML = ''; c.head.append(...headOf(it, r));
        c.body.innerHTML = ''; c.body.append(...bodyOf(it, r).filter(Boolean)); c.sig = s;
      }
      else if (r && r.status !== 'done' && r.status !== 'expired') { const w = c.body.querySelector ? c.body.querySelector('.trun-wait') : null; if (w) w.textContent = waitingText(r); }
      // ordem: a lista manda (mais nova em cima); só move se estiver fora do lugar
      if (list.children[i] !== c.root) list.insertBefore ? list.insertBefore(c.root, list.children[i] || null) : list.append(c.root);
    });
    if (!runs.length && !list.children.length) list.append(el('p', { class: 'small muted trun-empty' }, T('Nenhuma execução ainda.', 'No runs yet.', 'Ninguna ejecución todavía.')));
    if (runs.length) [...list.children].filter(n => n.classList && n.classList.contains('trun-empty')).forEach(n => n.remove());
  }

  async function openReport(run) {
    try { ctx.openHtmlReport(await ctx.report(run)); }
    catch (e) { setMsg(T('Falha ao abrir o report: ', 'Failed to open the report: ', 'Error al abrir el report: ') + ((e && e.message) || ''), true); }
  }

  // ---- poll serializado ----
  const pending = () => runs.filter(it => { const r = recs.get(it.run); return !r || (r.status !== 'done' && r.status !== 'expired'); });
  async function poll() {
    if (polling || !curId) return;
    if (timer) { clearTimeout(timer); timer = null; }
    const todo = pending(); if (!todo.length) return;
    if (!visible()) return;                       // aba escondida: o visibilitychange re-arma
    polling = true;
    const id = curId;
    try {
      for (const it of todo) {
        try {
          const r = await ctx.get('/problems/test-run?run=' + it.run);
          if (id !== curId) return;               // trocou de problema no meio
          recs.set(it.run, r);
        } catch (e) {
          if (e && e.status === 404) recs.set(it.run, { run: it.run, status: 'expired' });
          // outro erro (rede): mantém o cartão como está e tenta de novo
        }
      }
      render();
    } finally { polling = false; }
    const left = pending(); if (!left.length) return;
    const oldest = Math.min(...left.map(it => it.at || now()));
    timer = schedule(poll, now() - oldest > 10 * 60 * 1000 ? 15000 : 3000);
  }

  // troca de problema (ou 1ª carga): lista lembrada + consulta
  function refresh() {
    curId = ctx.id() || '';
    unsaved.hidden = !!curId; runBtn.disabled = !curId;
    if (timer) { clearTimeout(timer); timer = null; }
    for (const [, c] of cards) c.root.remove();
    cards.clear(); recs.clear(); list.innerHTML = '';
    runs = curId ? loadRuns(curId) : [];
    render(); poll();
  }
  // o editor nasce quando a sub-aba ABRE (CodeMirror num painel escondido mede errado — as outras
  // sub-abas também criam os editores na hora de mostrar)
  async function show() { if (!ed) await ensureEditor(null); poll(); }
  return { panel, prefill, refresh, show, onVisible: () => poll(), _state: () => ({ runs, recs, cards, polling }) };
}
