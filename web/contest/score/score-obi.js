// contest/score/score-obi.js — renderizador OBI (células = pontos).
// Header (após remover marcadores): [flag:]username[:univ short]:team name:<SHORTS...>:Total
import { el } from '/shared/ui.js';
import { flagEl } from '/shared/flags.js';
import { sonicEnabled, sonicImgHTML } from '/shared/sonic.js';
import { filterTeams } from './score-icpc.js';

function escHtml(s) { return String(s).replace(/[<>&"']/g, c => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;', "'": '&#39;' })[c]); }

const SYS = ['flag', 'username', 'univ short', 'team name', 'univ full', 'total'];

export function parseOBI(lines) {
  if (lines.length < 1) return null;
  const headerRaw = lines[0].split(':');
  let start = 0;
  while (start < headerRaw.length && /^(desc|asc)$/i.test(headerRaw[start].trim())) start++;
  const header = headerRaw.slice(start);

  const idx = (name) => header.findIndex(h => h.trim().toLowerCase() === name);
  const iFlag = idx('flag'), iUser = idx('username'), iUnivS = idx('univ short'),
        iTeam = idx('team name'), iUnivF = idx('univ full'), iTotal = idx('total');
  const probEnd = iTotal >= 0 ? iTotal : header.length;
  const probIdx = [];
  for (let i = 0; i < probEnd; i++) if (!SYS.includes(header[i].trim().toLowerCase())) probIdx.push(i);
  const probShorts = probIdx.map(i => header[i]);

  const teams = lines.slice(1).filter(Boolean).map(line => {
    const v = line.split(':');
    const t = {
      flag: iFlag >= 0 ? (v[iFlag] || '') : '',
      username: iUser >= 0 ? (v[iUser] || '') : '',
      univShort: iUnivS >= 0 ? (v[iUnivS] || '') : '',
      teamName: iTeam >= 0 ? (v[iTeam] || '') : '',
      univFull: iUnivF >= 0 ? (v[iUnivF] || '') : '',
      total: iTotal >= 0 ? (v[iTotal] || '') : '',
      probs: {},
    };
    probIdx.forEach((ci, k) => { t.probs[probShorts[k]] = v[ci] || ''; });
    return t;
  });
  teams.forEach((t, i) => { t.place = i + 1; });
  return { mode: 'obi', probShorts, teams, hasFlag: iFlag >= 0, hasUnivShort: iUnivS >= 0, hasUnivFull: iUnivF >= 0 };
}

export function renderOBI(parsed, opts) {
  const { searchTerm = '', regionFn = null } = opts || {};
  let teams = filterTeams(parsed.teams, searchTerm);
  if (regionFn) teams = teams.filter(regionFn);

  const table = el('table', { class: 'score' });
  const headRow = el('tr', {}, el('th', {}, '#'));
  if (parsed.hasFlag) headRow.append(el('th', {}, 'Bandeira'));
  headRow.append(el('th', {}, 'Equipe'));
  const sonic = sonicEnabled(parsed.balloons);
  parsed.probShorts.forEach(pb => headRow.append(sonic ? el('th', { html: sonicImgHTML(pb) + ' ' + escHtml(pb) }) : el('th', {}, pb)));
  headRow.append(el('th', {}, 'Total'));
  table.append(el('thead', {}, headRow));

  const tb = el('tbody');
  teams.forEach(t => {
    const tr = el('tr', { id: 'tr-team-' + t.username.replace(/\W/g, '_') });
    tr.append(el('td', { class: 'cl-place' }, String(t.place)));
    if (parsed.hasFlag) {
      const flagTd = el('td', {});
      if (t.flag) { const fi = flagEl(t.flag, { height: 18, title: t.flagTitle || t.flag }); if (fi) flagTd.append(fi); }
      tr.append(flagTd);
    }
    const safeLogo = /^(data:image\/|\/|https?:)/.test(t.schoolLogo || '') ? String(t.schoolLogo).replace(/"/g, '') : '';
    const logo = safeLogo ? `<img src="${safeLogo}" alt="" style="height:16px;vertical-align:middle;margin-right:4px;border-radius:2px" onerror="this.remove()"> ` : '';
    const label = (parsed.hasUnivShort && t.univShort ? `[${escHtml(t.univShort)}] ` : '') + escHtml(t.teamName || t.username);
    const teamTd = el('td', { class: 'team', title: (parsed.hasUnivFull && t.univFull) || '', html: logo + label });
    // foto do time (photo.png subida pelo admin): link clicável, abre em nova aba
    if (t.photoUrl) teamTd.append(' ', el('a', { href: t.photoUrl, target: '_blank', title: 'Foto do time', style: 'text-decoration:none' }, '📷'));
    tr.append(teamTd);
    parsed.probShorts.forEach(sn => {
      const v = t.probs[sn] || '';
      const n = parseInt(v, 10);
      if (v !== '' && n > 0) { const td = el('td', {}, v); td.style.cssText = 'background:#dde9ff;color:#1346aa;font-weight:700'; tr.append(td); }
      else if (v === '0') { const td = el('td', {}, v); td.style.cssText = 'background:#fbe7e9;color:#c4314b;font-weight:700'; tr.append(td); }
      else tr.append(el('td', {}, ''));
    });
    tr.append(el('td', {}, t.total));
    tb.append(tr);
  });
  table.append(tb);
  return table;
}
