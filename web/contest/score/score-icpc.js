// contest/score/score-icpc.js — renderizador ICPC.
// Header (após remover marcadores desc/asc):
//   flag:username:univ short:team name:univ full:<SHORTS...>:Total:Penalty:LastAC
// Células: ""=untried · tries/minutes=solved (cor do balão) · tries/minutes*=FIRST TO SOLVE
// (★ + contorno) · tries/-=tried-unsolved.
// Total=resolvidos; Penalty=soma das penalidades (coluna visível); LastAC=minuto do último
// AC — coluna de SISTEMA: entra só no EMPATE (total+penalty+lastac iguais), não renderiza.
// TXT antigo sem as colunas novas continua parseando (índices ausentes viram '').
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';
import { flagEl } from '/shared/flags.js';
import { sonicEnabled, sonicImgHTML } from '/shared/sonic.js';
import { balloonColorHex, balloonIsDark, balloonSVG } from './score-colors.js';

const SYS = ['flag', 'username', 'univ short', 'team name', 'univ full', 'total', 'penalty', 'lastac', 'guest'];

// parse: recebe linhas (já split por \n, sem a 1ª linha do modo) e o mapa de balões.
export function parseICPC(lines, balloons) {
  if (lines.length < 1) return null;
  const headerRaw = lines[0].split(':');
  // remove TODAS as colunas-marcador de ordenação iniciais (desc/asc)
  let start = 0;
  while (start < headerRaw.length && /^(desc|asc)$/i.test(headerRaw[start].trim())) start++;
  const header = headerRaw.slice(start); // alinha 1:1 com as colunas de dados

  const idx = (name) => header.findIndex(h => h.trim().toLowerCase() === name);
  const iFlag = idx('flag'), iUser = idx('username'), iUnivS = idx('univ short'),
        iTeam = idx('team name'), iUnivF = idx('univ full'), iTotal = idx('total'),
        iPen = idx('penalty'), iLast = idx('lastac'), iGuest = idx('guest');

  // problemas = colunas que não são do sistema, até "total"
  const probEnd = iTotal >= 0 ? iTotal : header.length;
  const probIdx = [];
  for (let i = 0; i < probEnd; i++) {
    if (!SYS.includes(header[i].trim().toLowerCase())) probIdx.push(i);
  }
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
      penalty: iPen >= 0 ? (v[iPen] || '') : '',
      lastac: iLast >= 0 ? (v[iLast] || '') : '',
      // time CONVIDADO (extra-oficial): aparece intercalado, mas NÃO consome posição oficial
      guest: iGuest >= 0 && String(v[iGuest] || '').trim() === '1',
      probs: {},
    };
    probIdx.forEach((ci, k) => { t.probs[probShorts[k]] = v[ci] || ''; });
    return t;
  });

  // colocações com empates (placar já vem ORDENADO; só numera). Empate REAL = os três
  // critérios iguais: resolvidos + penalidade + minuto do último AC.
  // CONVIDADO (coluna `guest`) aparece na linha certa pelo desempenho mas NÃO consome posição:
  // a numeração oficial pula ele, então o pódio combinado bate com o placar oficial.
  let place = 0, prev = null;
  teams.forEach((t) => {
    if (t.guest) { t.place = null; return; }
    if (prev && prev.total === t.total && prev.penalty === t.penalty && prev.lastac === t.lastac) {
      t.place = prev.place;
    } else { place++; t.place = place; }
    prev = t;
  });

  return { mode: 'icpc', probShorts, teams, balloons };
}

function cellSolved(v) { return /^\d+\/\d+\/?\*?$/.test(v); }  // tries/minutes[*]
function cellWait(v) { return /^\d+\/-/.test(v); }             // tries/-

export function renderICPC(parsed, opts) {
  const { searchTerm = '', regionFn = null } = opts || {};
  let teams = filterTeams(parsed.teams, searchTerm);
  if (regionFn) teams = teams.filter(regionFn);

  const table = el('table', { class: 'score' });
  const headRow = el('tr', {},
    el('th', {}, '#'),
    el('th', {}, T('Bandeira', 'Flag')),
    el('th', {}, T('Equipe', 'Team')));
  const sonic = sonicEnabled(parsed.balloons);
  parsed.probShorts.forEach(pb => {
    const cc = balloonColorHex(parsed.balloons, pb);
    const icon = sonic ? sonicImgHTML(pb) + ' ' : (cc ? balloonSVG(cc) + ' ' : '');
    headRow.append(el('th', { html: icon + escapeHtml(pb) }));
  });
  headRow.append(el('th', {}, 'Total'));
  headRow.append(el('th', { title: T('Soma das penalidades (min)', 'Penalty sum (min)') }, T('Penal.', 'Penalty')));
  table.append(el('thead', {}, headRow));

  const tb = el('tbody');
  teams.forEach(t => {
    const tr = el('tr', { id: 'tr-team-' + t.username.replace(/\W/g, '_'),
      class: t.guest ? 'guest-row' : '' });
    // convidado não tem posição oficial: mostra "–" no lugar do número
    tr.append(el('td', { class: 'cl-place' }, t.guest ? '–' : String(t.place)));
    // bandeira
    const flagTd = el('td', {});
    if (t.flag) { const fi = flagEl(t.flag, { height: 18, title: t.flagTitle || t.flag }); if (fi) flagTd.append(fi); }
    tr.append(flagTd);
    // equipe (logo da escola opcional, via teams-meta; data-URL/local p/ offline)
    const safeLogo = /^(data:image\/|\/|https?:)/.test(t.schoolLogo || '') ? String(t.schoolLogo).replace(/"/g, '') : '';
    const logo = safeLogo ? `<img src="${safeLogo}" alt="" style="height:16px;vertical-align:middle;margin-right:4px;border-radius:2px" onerror="this.remove()"> ` : '';
    const label = (t.univShort ? `[${escapeHtml(t.univShort)}] ` : '') + escapeHtml(t.teamName || t.username);
    const teamTd = el('td', { class: 'team', title: t.univFull || t.univShort || '', html: logo + label });
    // foto do time (photo.png subida pelo admin): link clicável, abre em nova aba
    if (t.photoUrl) teamTd.append(' ', el('a', { href: t.photoUrl, target: '_blank', title: T('Foto do time', 'Team photo'), style: 'text-decoration:none' }, '📷'));
    // 🤖 = o time DECLAROU na inscrição que usa IA (transparência, não julgamento)
    if (t.aiDeclared) teamTd.append(' ', el('span', { title: T('Este time declarou que usa IA', 'This team declared AI use'), style: 'cursor:default' }, '🤖'));
    if (t.guest) teamTd.append(' ', el('span', { class: 'pill',
      title: T('Time convidado (extra-oficial): não entra na classificação oficial.',
               'Guest team (unofficial): does not enter the official ranking.') },
      T('convidado', 'guest')));
    tr.append(teamTd);
    // problemas
    parsed.probShorts.forEach(sn => {
      const v = t.probs[sn] || '';
      if (cellSolved(v)) {
        const fts = v.endsWith('*');                       // first to solve
        const shown = fts ? v.slice(0, -1) : v;
        const color = balloonColorHex(parsed.balloons, sn);
        const td = el('td', {}, (fts ? '★ ' : '') + shown);
        if (color) { td.style.background = color; td.style.color = balloonIsDark(color) ? '#fff' : '#222'; td.style.fontWeight = '700'; }
        else { td.style.background = '#e2ffe9'; td.style.color = '#222'; td.style.fontWeight = '700'; }
        if (fts) { td.title = 'First to solve'; td.style.boxShadow = 'inset 0 0 0 2px currentColor'; }
        tr.append(td);
      } else if (cellWait(v)) {
        tr.append(el('td', { class: 'prob-wait-cell' }, v));
      } else {
        tr.append(el('td', {}, v));
      }
    });
    tr.append(el('td', {}, t.total));
    tr.append(el('td', {}, t.penalty));
    tb.append(tr);
  });
  table.append(tb);
  return table;
}

// ---- compartilhado ----
export function filterTeams(list, term) {
  if (!term) return list;
  const q = term.trim().toLowerCase();
  return list.filter(t =>
    (t.username || '').toLowerCase().includes(q) ||
    (t.teamName || '').toLowerCase().includes(q) ||
    (t.univShort || '').toLowerCase().includes(q) ||
    (t.univFull || '').toLowerCase().includes(q));
}
function escapeHtml(s) {
  return String(s).replace(/[<>&"']/g, c => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;', "'": '&#39;' })[c]);
}
