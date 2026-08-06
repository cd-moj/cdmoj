// contest/admin/problems-tab.js — "Prova › Problemas": a prova em si.
// Sanfona por problema (renomear, linguagens, pool de juízes, enunciado) + o painel
// compartilhado de busca/sorteio do banco (makeBankPanel, o mesmo do wizard).
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { fileToBase64 } from '/shared/auth.js';
import { makeLangPicker, makeJudgePicker, makeBankPanel } from '/shared/contest-config/index.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;

export function makeProblemsTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div', { class: 'section' }, el('h2', {}, T('📚 Problemas', '📚 Problems')));
  const list = el('div', {});

  async function act(p) {
    try { await apiPost('/contest/admin/problems?contest=' + enc(CONTEST), p, G); loadList(); }
    catch (e) { alert(e.message || T('falha', 'failed')); }
  }
  async function postProb(payload, msgEl, reload) {
    if (msgEl) { msgEl.className = 'small'; msgEl.textContent = T('Salvando…', 'Saving…'); }
    try {
      await apiPost('/contest/admin/problems?contest=' + enc(CONTEST), payload, G);
      if (msgEl) msgEl.textContent = T('✓ salvo', '✓ saved');
      if (reload) loadList();
    } catch (e) {
      if (msgEl) { msgEl.className = 'small error-box'; msgEl.textContent = e.message || T('falha', 'failed'); }
      else alert(e.message || T('falha', 'failed'));
    }
  }

  function problemAccordion(p, i, ps, letters) {
    const body = el('div', { class: 'acc-body hidden' });
    const tog = el('span', { class: 'acc-tog' }, '▶');
    const stop = (e) => e.stopPropagation();
    const head = el('div', { class: 'acc-head' },
      tog, el('b', {}, p.letter), ' ', el('span', {}, p.name || ''),
      el('span', { class: 'small muted', style: 'font-family:var(--mono); margin-left:.4rem' }, (p.source || 'cdmoj') + '/' + p.problem_id),
      el('span', { style: 'flex:1' }),
      el('button', { class: 'btn ghost', title: T('subir', 'move up'), onclick: (e) => { stop(e); if (i > 0) { const o = letters.slice(); [o[i - 1], o[i]] = [o[i], o[i - 1]]; act({ action: 'reorder', order: o }); } } }, '↑'),
      el('button', { class: 'btn ghost', title: T('descer', 'move down'), onclick: (e) => { stop(e); if (i < ps.length - 1) { const o = letters.slice(); [o[i + 1], o[i]] = [o[i], o[i + 1]]; act({ action: 'reorder', order: o }); } } }, '↓'),
      el('button', { class: 'btn danger', title: T('remover', 'remove'), onclick: (e) => { stop(e); if (confirm(T('Remover ', 'Remove ') + p.letter + '?')) act({ action: 'remove', letter: p.letter }); } }, '✕'));
    head.addEventListener('click', () => { const hid = body.classList.toggle('hidden'); tog.textContent = hid ? '▶' : '▼'; });

    // --- renomear (nome E identificador: a letra pode ser custom — W1, Q… — e o reorder a preserva) ---
    const nameInp = el('input', { value: p.name || '', style: 'max-width:280px' });
    const letInp = el('input', { value: p.letter || '', maxlength: '3', style: 'width:4.5rem; font-family:var(--mono)' });
    const rnMsg = el('div', { class: 'small' });
    const saveRename = () => {
      const payload = { action: 'rename', letter: p.letter, name: nameInp.value };
      const nl = letInp.value.trim();
      if (nl && nl !== p.letter) payload.new_letter = nl;
      postProb(payload, rnMsg, true);
    };
    // --- linguagens (inline) ---
    const picker = makeLangPicker(p.languages || []);
    const lMsg = el('div', { class: 'small' });
    // --- pool de juízes (inline) ---
    const jPicker = makeJudgePicker(p.judges || [], G);
    const jMsg = el('div', { class: 'small' });
    // --- enunciado: atualizar do banco / enviar HTML / enviar PDF ---
    const sMsg = el('div', { class: 'small' });
    const htmlIn = el('input', { type: 'file', accept: '.html,.htm,text/html', style: 'max-width:200px' });
    const pdfIn = el('input', { type: 'file', accept: '.pdf,application/pdf', style: 'max-width:200px' });
    const sendStmt = async (payload) => postProb({ action: 'statement', letter: p.letter, ...payload }, sMsg, false);

    body.append(
      el('div', { class: 'row', style: 'margin:.3rem 0; flex-wrap:wrap' },
        el('span', { class: 'small muted' }, T('Identificador:', 'Identifier:')), letInp,
        el('span', { class: 'small muted' }, T('Nome:', 'Name:')), nameInp,
        el('button', { class: 'btn ghost', onclick: saveRename }, T('Renomear', 'Rename')), rnMsg),
      el('div', { style: 'margin:.5rem 0' }, el('div', { class: 'small muted' }, T('💻 Linguagens (nenhuma marcada = herda do contest):', '💻 Languages (none checked = inherits from contest):')),
        picker.el, el('div', { class: 'row' }, el('button', { class: 'btn', onclick: () => postProb({ action: 'langs', letter: p.letter, languages: picker.get() }, lMsg, false) }, T('Salvar linguagens', 'Save languages')), lMsg)),
      el('div', { style: 'margin:.5rem 0' }, el('div', { class: 'small muted' }, T('🖥️ Máquinas de juiz deste problema (nenhuma marcada = herda o pool do contest):', '🖥️ Judge machines for this problem (none checked = inherits the contest pool):')),
        jPicker.el, el('div', { class: 'row' }, el('button', { class: 'btn', onclick: () => postProb({ action: 'judges', letter: p.letter, judges: jPicker.get() }, jMsg, false) }, T('Salvar máquinas', 'Save machines')), jMsg)),
      el('div', { style: 'margin:.5rem 0' }, el('div', { class: 'small muted' }, T('📄 Enunciado:', '📄 Statement:')),
        el('div', { class: 'row', style: 'flex-wrap:wrap; gap:.4rem' },
          el('button', { class: 'btn ghost', title: T('Re-buscar do banco de problemas (regenera o enunciado)', 'Re-fetch from the problem bank (regenerates the statement)'), onclick: () => sendStmt({ refresh: true }).then(loadList) }, T('↻ Atualizar do banco', '↻ Refresh from bank')),
          el('span', { class: 'small muted' }, 'HTML:'), htmlIn,
          el('button', { class: 'btn ghost', onclick: async () => { if (!htmlIn.files[0]) { sMsg.className = 'small error-box'; sMsg.textContent = T('Escolha um .html', 'Choose a .html'); return; } sendStmt({ html_b64: await fileToBase64(htmlIn.files[0]) }); } }, T('Enviar HTML', 'Send HTML')),
          el('span', { class: 'small muted' }, 'PDF:'), pdfIn,
          el('button', { class: 'btn ghost', onclick: async () => { if (!pdfIn.files[0]) { sMsg.className = 'small error-box'; sMsg.textContent = T('Escolha um .pdf', 'Choose a .pdf'); return; } sendStmt({ pdf_b64: await fileToBase64(pdfIn.files[0]) }); } }, T('Enviar PDF', 'Send PDF'))), sMsg));
    return el('div', { class: 'acc-item' }, head, body);
  }

  async function loadList() {
    list.innerHTML = ''; let r;
    try { r = await apiGet('/contest/admin/problems?contest=' + enc(CONTEST), G); }
    catch { list.append(el('div', { class: 'error-box' }, T('Falha.', 'Failed.'))); return; }
    const ps = r.problems || [];
    if (!ps.length) { list.append(el('div', { class: 'muted' }, T('Sem problemas.', 'No problems.'))); return; }
    const letters = ps.map((p) => p.letter);
    ps.forEach((p, i) => list.append(problemAccordion(p, i, ps, letters)));
  }

  // painel compartilhado de busca+sorteio: busca = públicos + PRIVADOS do dono do contest
  // (mesmo sujeito do gate de add — a busca lista exatamente o que pode entrar)
  const bankApi = {
    meta: () => apiGet('/contest/admin/bank?contest=' + enc(CONTEST) + '&meta=1', G),
    draw: (p) => apiGet('/contest/admin/draw?contest=' + enc(CONTEST) + '&' + new URLSearchParams(p).toString(), G),
    search: (q) => apiGet('/contest/admin/bank?contest=' + enc(CONTEST) + '&limit=30&q=' + enc(q), G),
  };
  let bank = null;

  async function load() {
    if (!bank) {
      bank = makeBankPanel({
        api: bankApi,
        onAdd: (it) => act({ action: 'add', problem: { bank_id: it.id, name: it.title || it.id } }),
        searchLabel: T('Buscar problemas (públicos + os privados do dono do contest)', 'Search problems (public + the contest owner\'s private ones)'),
        searchPlaceholder: T('🔎 Buscar problemas (públicos + privados do dono) — título ou id…', '🔎 Search problems (public + owner\'s private) — title or id…'),
        noQueryFilter: (items) => items.filter((it) => it.private),
        emptyHint: T('o dono do contest não tem problemas privados — digite para buscar no banco público', 'the contest owner has no private problems — type to search the public bank'),
      });
      panel.append(list, el('h3', { style: 'margin:1rem 0 .3rem' }, T('Adicionar do banco', 'Add from bank')), bank.el);
    }
    await loadList();
  }
  return { panel, load };
}
