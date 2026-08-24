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
import { setMediaSrc, mediaLink } from '/shared/media-auth.js';
import { balloonColorHex, balloonSVG, balloonDot, paintSolvedCell } from './score-colors.js';
import { scoreCols, cellTitle } from './score-cols.js';

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
  const { searchTerm = '', regionFn = null, genPlace = null, style = 'icon' } = opts || {};
  let teams = filterTeams(parsed.teams, searchTerm);
  if (regionFn) teams = teams.filter(regionFn);

  const table = el('table', { class: 'score m-icpc' });
  // quantos times a seleção deixou visíveis (o contador da barra de filtros lê daqui — a
  // posição NUNCA é renumerada, então é o contador que revela que há filtro ativo)
  table.dataset.shown = String(teams.length);
  table.dataset.total = String(parsed.teams.length);
  // largura por <colgroup>: com table-layout:fixed é o que garante que TODAS as colunas
  // caibam (o conteúdo quebra dentro da célula em vez de a tabela rolar).
  scoreCols(table, parsed.probShorts.length, { flag: true, penalty: true });
  const headRow = el('tr', {},
    // em placar de COORTE a coluna leva duas posições: a da coorte e a do placar geral
    el('th', {}, '#', genPlace ? el('span', { class: 'plg' }, T('Geral', 'Overall')) : null),
    el('th', { title: T('Bandeira', 'Flag') }, ''),   // rótulo não cabe na coluna estreita: fica no title
    el('th', {}, T('Equipe', 'Team')));
  const sonic = sonicEnabled(parsed.balloons);
  parsed.probShorts.forEach(pb => {
    const cc = balloonColorHex(parsed.balloons, pb);
    const icon = sonic ? sonicImgHTML(pb) + ' ' : (cc ? balloonSVG(cc) + ' ' : '');
    headRow.append(el('th', { class: 'prob', html: icon + escapeHtml(pb) }));
  });
  headRow.append(el('th', {}, 'Total'));
  headRow.append(el('th', { title: T('Soma das penalidades (min)', 'Penalty sum (min)') }, T('Penal.', 'Pen.')));
  table.append(el('thead', {}, headRow));

  const tb = el('tbody');
  teams.forEach(t => {
    const tr = el('tr', { id: 'tr-team-' + t.username.replace(/\W/g, '_'),
      class: t.guest ? 'guest-row' : '' });
    // convidado não tem posição oficial: mostra "–" no lugar do número
    const gp = genPlace && !t.guest ? genPlace[t.username] : null;
    tr.append(el('td', { class: 'cl-place' }, t.guest ? '–' : String(t.place),
      gp != null ? el('span', { class: 'plg',
        title: T('Posição no placar geral', 'Position in the overall scoreboard') }, String(gp)) : null));
    // bandeira
    const flagTd = el('td', {});
    if (t.flag) { const fi = flagEl(t.flag, { height: 18, title: t.flagTitle || t.flag }); if (fi) flagTd.append(fi); }
    tr.append(flagTd);
    // equipe (logo da escola opcional, via teams-meta; data-URL/local p/ offline)
    const safeLogo = /^(data:image\/|\/|https?:)/.test(t.schoolLogo || '') ? String(t.schoolLogo).replace(/"/g, '') : '';
    // o brasão sai da string de HTML e vira NÓ: em contest SECRETO o src é um blob: buscado com
    // Bearer (shared/media-auth.js), que nenhuma string de `<img src=…>` consegue. O `safeLogo`
    // segue validando a URL CRUA (o `rule.logo` do teams-meta é escolha do admin), então `blob:`
    // nunca precisa entrar na regex. ⚠ o `lazy` não é enfeite: sem ele o 1º render de uma prova
    // grande dispararia uma busca — um fork de bash — por LINHA do placar.
    const logoImg = safeLogo ? el('img', { alt: '', loading: 'lazy',
      style: 'height:16px;vertical-align:middle;margin-right:4px;border-radius:2px',
      onerror: (e) => e.target.remove() }) : null;
    const label = (t.univShort ? `[${escapeHtml(t.univShort)}] ` : '') + escapeHtml(t.teamName || t.username);
    const teamTd = el('td', { class: 'team',
      title: [t.univFull || t.univShort || '', t.username].filter(Boolean).join(' · '), html: label });
    if (logoImg) { teamTd.prepend(logoImg, ' '); setMediaSrc(logoImg, safeLogo, { lazy: true, onerror: () => logoImg.remove() }); }
    // foto do time (photo.webp; a rota serve o legado png também): link, abre em nova aba
    if (t.photoUrl) teamTd.append(' ', mediaLink(t.photoUrl, { title: T('Foto do time', 'Team photo'), style: 'text-decoration:none' }, '📷'));
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
        // valor dentro de .pv: é o que ganha fonte menor (e no celular sai de cena, dando
        // lugar ao ✓ — os números ficam no title).
        const td = el('td', { class: 'cell ok', title: cellTitle(sn, shown, T) },
          fts ? el('span', { class: 'fts' }, '★') : null,
          style === 'icon' && color ? balloonDot(color) : null,
          el('span', { class: 'pv' }, shown));
        paintSolvedCell(td, color, { style, fts });
        if (fts) td.title = T('Primeiro a resolver', 'First to solve') + ' · ' + cellTitle(sn, shown, T);
        tr.append(td);
      } else if (cellWait(v)) {
        tr.append(el('td', { class: 'cell c-try prob-wait-cell', title: cellTitle(sn, v, T) },
          el('span', { class: 'pv' }, v)));
      } else {
        tr.append(el('td', { class: 'cell', title: sn }, el('span', { class: 'pv' }, v)));
      }
    });
    tr.append(el('td', { class: 'cell tot' }, t.total));
    tr.append(el('td', { class: 'cell pen' }, el('span', { class: 'pv' }, t.penalty)));
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
