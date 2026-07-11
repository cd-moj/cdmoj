// contest/score/score-generic.js — renderizador genérico (treino/heuristic/outro).
// Colunas livres: usa os nomes REAIS do cabeçalho (após remover marcadores desc/asc).
// Se houver coluna "flag", mostra bandeira. Adiciona uma coluna "#" de posição.
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';
import { flagEl } from '/shared/flags.js';

export function parseGeneric(lines, mode) {
  if (lines.length < 1) return null;
  const headerRaw = lines[0].split(':');
  let start = 0;
  while (start < headerRaw.length && /^(desc|asc)$/i.test(headerRaw[start].trim())) start++;
  const header = headerRaw.slice(start);
  const iFlag = header.findIndex(h => h.trim().toLowerCase() === 'flag');
  const iUser = header.findIndex(h => h.trim().toLowerCase() === 'username');
  const iTeam = header.findIndex(h => h.trim().toLowerCase() === 'team name');

  const rows = lines.slice(1).filter(Boolean).map(line => {
    const v = line.split(':');
    return header.map((_, i) => v[i] != null ? v[i] : '');
  });
  rows.forEach((r, i) => { r._place = i + 1; });
  return { mode, header, rows, iFlag, iUser, iTeam };
}

export function renderGeneric(parsed, opts) {
  const { searchTerm = '', regionFn = null } = opts || {};
  const q = (searchTerm || '').trim().toLowerCase();
  let rows = parsed.rows;
  if (q) {
    rows = rows.filter(r => r.some(cell => String(cell).toLowerCase().includes(q)));
  }
  if (regionFn && parsed.iUser >= 0) {
    rows = rows.filter(r => regionFn({ username: r[parsed.iUser] || '' }));
  }

  const table = el('table', { class: 'score' });
  const headRow = el('tr', {}, el('th', {}, '#'));
  parsed.header.forEach((h, i) => {
    if (i === parsed.iFlag) { headRow.append(el('th', {}, T('Bandeira', 'Flag'))); return; }
    headRow.append(el('th', {}, h));
  });
  table.append(el('thead', {}, headRow));

  const tb = el('tbody');
  rows.forEach(r => {
    const tr = el('tr', {});
    tr.append(el('td', { class: 'cl-place' }, String(r._place)));
    parsed.header.forEach((_, i) => {
      const val = r[i] != null ? r[i] : '';
      if (i === parsed.iFlag) {
        const td = el('td', {});
        if (val) { const fi = flagEl(val, { height: 18, title: String(val) }); if (fi) td.append(fi); }
        tr.append(td);
      } else if (i === parsed.iUser || i === parsed.iTeam) {
        tr.append(el('td', { class: 'team' }, val));
      } else {
        tr.append(el('td', {}, val));
      }
    });
    tb.append(tr);
  });
  table.append(tb);
  return table;
}
