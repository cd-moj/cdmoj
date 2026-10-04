// steps/problemas.js — passo 2: busca+sorteio no banco (painel compartilhado, com coleções),
// add por ID, e a lista selecionada (letra, nome — automático no idioma da prova ou um dos títulos
// PT·EN·ES —, enunciado personalizado HTML/PDF, ordem).
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';
import { makeBankPanel } from '/shared/contest-config/index.js';
import { fileToBase64 } from '/shared/auth.js';
import { autoTitle, makeTitleChips } from '/shared/problem-titles.js';

const b64toUtf8 = (b) => { try { return decodeURIComponent(escape(atob(b))); } catch { return ''; } };

export function makeStepProblemas(ctx) {
  const d = ctx.draft;
  const listBox = el('div', {});
  const locale = () => ctx.contestLocale();

  function addProblem(p) {
    if (p.bank_id && d.problems.some((x) => x.bank_id === p.bank_id)) return;
    d.problems.push(p); renderList();
  }

  function renderList() {
    listBox.innerHTML = '';
    if (!d.problems.length) { listBox.append(el('p', { class: 'muted small' }, T('Nenhum problema ainda. Sorteie, busque no banco, ou adicione por ID.', 'No problems yet. Draw, search the bank, or add by ID.', 'Todavía no hay problemas. Sortea, busca en el banco o agrega por ID.'))); return; }
    d.problems.forEach((p, i) => {
      const letter = el('input', { class: 'letter', value: p._letter || autoLetter(i), maxlength: '3' });
      letter.addEventListener('input', () => { p._letter = letter.value; });
      // NOME: vazio = automático, o título no idioma da prova (o servidor decide na criação, com o idioma do
      // passo 5); os chips PT·EN·ES preenchem com o título de um idioma; digitar vale como nome próprio.
      const auto = autoTitle(p._titles, locale(), p._title || p.bank_id || p.problem_id);
      const name = el('input', { value: p.name || '', placeholder: T('automático: ', 'automatic: ', 'automático: ') + auto,
        title: T('Vazio = o título no idioma da prova (passo 5). Os botões PT/EN/ES usam o título de um idioma.',
          'Empty = the title in the contest language (step 5). The PT/EN/ES buttons use the title in one language.',
          'Vacío = el título en el idioma de la competencia (paso 5). Los botones PT/EN/ES usan el título de un idioma.') });
      const chips = makeTitleChips(p._titles, () => name.value, (v) => { name.value = v; p.name = v; });
      name.addEventListener('input', () => { p.name = name.value; chips.repaint && chips.repaint(); });
      const idtxt = p.bank_id ? (T('banco: ', 'bank: ', 'banco: ') + p.bank_id) : ((p.source || 'cdmoj') + ' / ' + p.problem_id);
      const genWarn = (p._private && !p._hasStmt)
        ? el('div', { class: 'small', style: 'color:#b8860b;margin-top:.2rem' }, T('⏳ enunciado em geração (aguardando juiz)', '⏳ statement being generated (waiting for judge)', '⏳ enunciado en generación (esperando al juez)'))
        : '';
      const extras = el('div', { class: 'small muted' },
        (p.languages || []).length ? '💻 ' + p.languages.join(' ') + ' · ' : '',
        p._stmt_b64 ? T('📄 HTML herdado · ', '📄 inherited HTML · ', '📄 HTML heredado · ') : '', p._stmt_pdf_b64 ? T('📕 PDF herdado · ', '📕 inherited PDF · ', '📕 PDF heredado · ') : '');
      // enunciado personalizado (HTML digitado + PDF anexado)
      const stmtWrap = el('div', { style: 'margin-top:.35rem' });
      const stmtToggle = el('a', { class: 'small', href: '#', style: 'cursor:pointer' }, T('✎ enunciado personalizado', '✎ custom statement', '✎ enunciado personalizado'));
      stmtToggle.addEventListener('click', (e) => {
        e.preventDefault();
        if (stmtWrap.firstChild) { stmtWrap.innerHTML = ''; return; }
        const ta = el('textarea', { rows: '4', placeholder: T('HTML do enunciado (opcional; sobrescreve o do banco)', 'Statement HTML (optional; overrides the bank one)', 'HTML del enunciado (opcional; sobrescribe el del banco)'), style: 'width:100%' });
        ta.value = p._stmt || (p._stmt_b64 ? b64toUtf8(p._stmt_b64) : '');
        ta.addEventListener('input', () => { p._stmt = ta.value; });
        const pdfIn = el('input', { type: 'file', accept: '.pdf,application/pdf', style: 'max-width:220px' });
        pdfIn.addEventListener('change', async () => {
          if (pdfIn.files[0]) { p._stmt_pdf_b64 = await fileToBase64(pdfIn.files[0]); renderList(); }
        });
        const pdfRow = el('div', { class: 'row', style: 'margin-top:.3rem' },
          el('span', { class: 'small muted' }, T('PDF (opcional):', 'PDF (optional):', 'PDF (opcional):')), pdfIn,
          p._stmt_pdf_b64 ? el('button', { class: 'btn ghost', onclick: () => { delete p._stmt_pdf_b64; renderList(); } }, T('remover PDF', 'remove PDF', 'quitar PDF')) : '');
        stmtWrap.append(ta, pdfRow);
      });
      const up = el('button', { class: 'btn ghost', onclick: () => { if (i > 0) { [d.problems[i - 1], d.problems[i]] = [d.problems[i], d.problems[i - 1]]; renderList(); } } }, '↑');
      const dn = el('button', { class: 'btn ghost', onclick: () => { if (i < d.problems.length - 1) { [d.problems[i + 1], d.problems[i]] = [d.problems[i], d.problems[i + 1]]; renderList(); } } }, '↓');
      const rm = el('button', { class: 'btn danger', onclick: () => { d.problems.splice(i, 1); renderList(); } }, '✕');
      listBox.append(el('div', { class: 'prob-row' }, letter,
        el('div', {}, el('div', { class: 'row', style: 'gap:.35rem;flex-wrap:wrap;align-items:center' }, name, chips),
          el('div', { class: 'pid' }, idtxt), extras, genWarn, stmtToggle, stmtWrap),
        el('div', { class: 'row' }, up, dn, rm)));
    });
  }

  const bank = makeBankPanel({
    api: ctx.bankApi,
    // sem `name`: o servidor dá o título no idioma da prova (o passo 5 ainda pode trocar o idioma)
    onAdd: (it) => addProblem({ kind: 'bank', bank_id: it.id, name: '', _title: it.title || it.id, ...(it.titles ? { _titles: it.titles } : {}), _private: it.private, _hasStmt: it.has_statement }),
    searchLabel: T('Buscar problemas (públicos + seus privados)', 'Search problems (public + your private)', 'Buscar problemas (públicos + tus privados)'),
    searchPlaceholder: T('🔎 Buscar problemas (públicos + os seus privados) — título ou id…', '🔎 Search problems (public + your private) — title or id…', '🔎 Buscar problemas (públicos + tus privados) — título o id…'),
    noQueryFilter: (items) => items.filter((it) => it.private),
    emptyHint: T('você não tem problemas privados — digite para buscar no banco público', 'you have no private problems — type to search the public bank', 'no tienes problemas privados — escribe para buscar en el banco público'),
  });

  renderList();
  const root = el('div', { class: 'section' },
    el('h2', {}, T('2 · Problemas', '2 · Problems', '2 · Problemas')),
    bank.el,
    el('h3', { style: 'margin:.8rem 0 .2rem' }, T('Problemas do contest', 'Contest problems', 'Problemas de la competencia')), listBox);
  return { el: root };
}

function autoLetter(i) {
  if (i < 26) return String.fromCharCode(65 + i);
  return String.fromCharCode(65 + Math.floor(i / 26) - 1) + String.fromCharCode(65 + (i % 26));
}
