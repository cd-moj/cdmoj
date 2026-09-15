// contest/admin/statement-langs-panel.js — "Idiomas do enunciado": a lista de idiomas que a
// sanfona OFERECE (conf STATEMENT_LANGS), com a disponibilidade por problema (arquivo no contest
// ou tradução no banco). Reusado pelo painel Prova › Problemas (admin) e pela aba 🌐 Idiomas do
// juiz-chefe — a rota /contest/admin/statement-langs aceita os dois papéis.
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { T } from '/shared/i18n.js';
import { STMT_SHORT, stmtName } from '/shared/statement-langs.js';

const enc = encodeURIComponent;

export function makeStatementLangsPanel(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const box = el('div', { class: 'section' });
  const body = el('div', {});
  const msg = el('div', { class: 'small' });
  let DATA = null;

  function render() {
    body.innerHTML = '';
    if (!DATA) return;
    const all = DATA.all || ['pt', 'en', 'es'];
    const on = new Set(DATA.langs || ['pt']);
    const checks = {};
    const row = el('div', { class: 'row', style: 'gap:1rem;flex-wrap:wrap;align-items:center' });
    all.forEach((l) => {
      const cb = el('input', { type: 'checkbox' }); cb.checked = on.has(l); checks[l] = cb;
      row.append(el('label', { class: 'row', style: 'gap:.35rem;align-items:center;cursor:pointer' }, cb,
        el('b', {}, STMT_SHORT[l] || l.toUpperCase()), el('span', { class: 'small muted' }, stmtName(l))));
    });
    const save = el('button', { class: 'btn', onclick: async () => {
      const langs = all.filter((l) => checks[l].checked);
      msg.className = 'small'; msg.textContent = T('Salvando…', 'Saving…');
      try { await apiPost('/contest/admin/statement-langs?contest=' + enc(CONTEST), { langs }, G); msg.textContent = T('✓ salvo', '✓ saved'); await load(); }
      catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
    } }, T('Salvar idiomas', 'Save languages'));
    row.append(save, msg);
    body.append(
      el('p', { class: 'small muted', style: 'margin:.2rem 0 .5rem' },
        T('Marque os idiomas que o competidor pode escolher na sanfona. A sanfona abre no idioma do contest (LOCALE) se ele estiver marcado; senão, no primeiro marcado. Um idioma marcado sem tradução em um problema mostra o português nesse problema.',
          'Check the languages the competitor can pick in the accordion. The accordion opens in the contest language (LOCALE) if it is checked; otherwise, in the first checked one. A checked language without a translation in a problem shows Portuguese for that problem.')),
      row,
      el('div', { class: 'small muted', style: 'margin:.4rem 0 .2rem' },
        T('Idioma padrão agora: ', 'Default language now: '), el('b', {}, (DATA.default || 'pt').toUpperCase()),
        DATA.locale ? ' · LOCALE=' + DATA.locale : ''));
    // disponibilidade por problema: letra × idioma
    const av = DATA.available || {};
    const letters = Object.keys(av);
    if (letters.length) {
      const tbl = el('table', { class: 'moj narrow' },
        el('thead', {}, el('tr', {}, el('th', {}, T('Problema', 'Problem')),
          ...all.map((l) => el('th', { class: 'c' }, STMT_SHORT[l] || l.toUpperCase())))));
      const tb = el('tbody');
      letters.forEach((L) => tb.append(el('tr', {}, el('td', {}, el('b', {}, L)),
        ...all.map((l) => el('td', { class: 'c', title: av[L][l] ? T('tradução disponível', 'translation available') : T('sem tradução — mostra o português', 'no translation — shows Portuguese') },
          av[L][l] ? '✓' : el('span', { class: 'muted' }, '—'))))));
      tbl.append(tb);
      body.append(el('div', { class: 'small muted', style: 'margin:.6rem 0 .2rem' }, T('Traduções disponíveis por problema (do pacote ou enviadas pelo admin):', 'Available translations per problem (from the package or uploaded by the admin):')), tbl);
    }
  }
  async function load() {
    try { DATA = await apiGet('/contest/admin/statement-langs?contest=' + enc(CONTEST), G); }
    catch (e) { body.innerHTML = ''; body.append(el('div', { class: 'error-box' }, e.message || T('Falha.', 'Failed.'))); return; }
    render();
  }
  box.append(el('h3', { style: 'margin:0 0 .3rem' }, T('🌐 Idiomas do enunciado', '🌐 Statement languages')), body);
  return { el: box, panel: box, load };
}
