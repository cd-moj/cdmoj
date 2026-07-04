// steps/problemas.js — passo 2: busca+sorteio no banco (painel compartilhado, com coleções),
// add por ID, e a lista selecionada (letra, nome, enunciado personalizado HTML/PDF, ordem).
import { el } from '/shared/ui.js';
import { makeBankPanel } from '/shared/contest-config/index.js';
import { fileToBase64 } from '/shared/auth.js';

const b64toUtf8 = (b) => { try { return decodeURIComponent(escape(atob(b))); } catch { return ''; } };

export function makeStepProblemas(ctx) {
  const d = ctx.draft;
  const listBox = el('div', {});

  function addProblem(p) {
    if (p.bank_id && d.problems.some((x) => x.bank_id === p.bank_id)) return;
    d.problems.push(p); renderList();
  }

  function renderList() {
    listBox.innerHTML = '';
    if (!d.problems.length) { listBox.append(el('p', { class: 'muted small' }, 'Nenhum problema ainda. Sorteie, busque no banco, ou adicione por ID.')); return; }
    d.problems.forEach((p, i) => {
      const letter = el('input', { class: 'letter', value: p._letter || autoLetter(i), maxlength: '3' });
      letter.addEventListener('input', () => { p._letter = letter.value; });
      const name = el('input', { value: p.name || '', placeholder: 'Nome exibido' });
      name.addEventListener('input', () => { p.name = name.value; });
      const idtxt = p.bank_id ? ('banco: ' + p.bank_id) : ((p.source || 'cdmoj') + ' / ' + p.problem_id);
      const genWarn = (p._private && !p._hasStmt)
        ? el('div', { class: 'small', style: 'color:#b8860b;margin-top:.2rem' }, '⏳ enunciado em geração (aguardando juiz)')
        : '';
      const extras = el('div', { class: 'small muted' },
        (p.languages || []).length ? '💻 ' + p.languages.join(' ') + ' · ' : '',
        p._stmt_b64 ? '📄 HTML herdado · ' : '', p._stmt_pdf_b64 ? '📕 PDF herdado · ' : '');
      // enunciado personalizado (HTML digitado + PDF anexado)
      const stmtWrap = el('div', { style: 'margin-top:.35rem' });
      const stmtToggle = el('a', { class: 'small', href: '#', style: 'cursor:pointer' }, '✎ enunciado personalizado');
      stmtToggle.addEventListener('click', (e) => {
        e.preventDefault();
        if (stmtWrap.firstChild) { stmtWrap.innerHTML = ''; return; }
        const ta = el('textarea', { rows: '4', placeholder: 'HTML do enunciado (opcional; sobrescreve o do banco)', style: 'width:100%' });
        ta.value = p._stmt || (p._stmt_b64 ? b64toUtf8(p._stmt_b64) : '');
        ta.addEventListener('input', () => { p._stmt = ta.value; });
        const pdfIn = el('input', { type: 'file', accept: '.pdf,application/pdf', style: 'max-width:220px' });
        pdfIn.addEventListener('change', async () => {
          if (pdfIn.files[0]) { p._stmt_pdf_b64 = await fileToBase64(pdfIn.files[0]); renderList(); }
        });
        const pdfRow = el('div', { class: 'row', style: 'margin-top:.3rem' },
          el('span', { class: 'small muted' }, 'PDF (opcional):'), pdfIn,
          p._stmt_pdf_b64 ? el('button', { class: 'btn ghost', onclick: () => { delete p._stmt_pdf_b64; renderList(); } }, 'remover PDF') : '');
        stmtWrap.append(ta, pdfRow);
      });
      const up = el('button', { class: 'btn ghost', onclick: () => { if (i > 0) { [d.problems[i - 1], d.problems[i]] = [d.problems[i], d.problems[i - 1]]; renderList(); } } }, '↑');
      const dn = el('button', { class: 'btn ghost', onclick: () => { if (i < d.problems.length - 1) { [d.problems[i + 1], d.problems[i]] = [d.problems[i], d.problems[i + 1]]; renderList(); } } }, '↓');
      const rm = el('button', { class: 'btn danger', onclick: () => { d.problems.splice(i, 1); renderList(); } }, '✕');
      listBox.append(el('div', { class: 'prob-row' }, letter,
        el('div', {}, name, el('div', { class: 'pid' }, idtxt), extras, genWarn, stmtToggle, stmtWrap),
        el('div', { class: 'row' }, up, dn, rm)));
    });
  }

  const bank = makeBankPanel({
    api: ctx.bankApi,
    onAdd: (it) => addProblem({ kind: 'bank', bank_id: it.id, name: it.title || it.id, _private: it.private, _hasStmt: it.has_statement }),
    searchLabel: 'Buscar problemas (públicos + seus privados)',
    searchPlaceholder: '🔎 Buscar problemas (públicos + os seus privados) — título ou id…',
    noQueryFilter: (items) => items.filter((it) => it.private),
    emptyHint: 'você não tem problemas privados — digite para buscar no banco público',
  });

  renderList();
  const root = el('div', { class: 'section' },
    el('h2', {}, '2 · Problemas'),
    bank.el,
    el('h3', { style: 'margin:.8rem 0 .2rem' }, 'Problemas do contest'), listBox);
  return { el: root };
}

function autoLetter(i) {
  if (i < 26) return String.fromCharCode(65 + i);
  return String.fromCharCode(65 + Math.floor(i / 26) - 1) + String.fromCharCode(65 + (i % 26));
}
