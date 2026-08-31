// contest/score/score-icpc.js — renderizador ICPC.
// Header (após remover marcadores desc/asc):
//   flag:username:univ short:team name:univ full:<SHORTS...>:Total:Penalty:LastAC
// Células: ""=untried · tries/tempo=solved (cor do balão) · tries/tempo*=FIRST TO SOLVE
// (★ + contorno) · tries/-=tried-unsolved.
// UNIDADE do tempo (R6, 2026-08-30): a linha 1 do TXT diz — `icpc s` = célula em SEGUNDOS
// (o parse exibe floor(seg/60) e guarda o segundo exato em probSecs p/ a estrela relativa
// do recorte); `icpc` sem flag = minutos (placares ARQUIVADOS), probSecs = min*60.
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

// parse: recebe linhas (já split por \n, sem a 1ª linha do modo), o mapa de balões e a
// flag `secs` (linha 1 era `icpc s` ⇒ célula em segundos; ausente ⇒ minutos, legado).
export function parseICPC(lines, balloons, secs) {
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
      probSecs: {},   // segundos do AC por problema (exatos com a flag `s`; min*60 no legado)
    };
    probIdx.forEach((ci, k) => {
      const raw = v[ci] || '';
      const m = /^(\d+)\/(\d+)(\*?)$/.exec(raw);
      if (m) {
        const sec = secs ? Number(m[2]) : Number(m[2]) * 60;
        // probs guarda a string de EXIBIÇÃO (minutos) — todo consumidor a jusante
        // (render, anônimo, regexes de célula) segue vendo o formato de sempre.
        t.probs[probShorts[k]] = m[1] + '/' + Math.floor(sec / 60) + m[3];
        t.probSecs[probShorts[k]] = sec;
      } else {
        t.probs[probShorts[k]] = raw;
      }
    });
    return t;
  });

  // colocações com empates (placar já vem ORDENADO; só numera). Empate REAL = os três
  // critérios iguais: resolvidos + penalidade + minuto do último AC.
  // RANKING DE COMPETIÇÃO (2026-08-31, achado do Carlos na LATAM): empatado COMPARTILHA a
  // posição e CONSOME — N empatados em 1106 ⇒ o próximo é 1106+N, nunca 1107 (a numeração
  // era DENSA: o grupo inteiro consumia uma posição só).
  // CONVIDADO (coluna `guest`) aparece na linha certa pelo desempenho mas NÃO consome posição:
  // a numeração oficial pula ele, então o pódio combinado bate com o placar oficial.
  let seen = 0, prev = null;
  teams.forEach((t) => {
    if (t.guest) { t.place = null; return; }
    seen++;
    t.place = (prev && prev.total === t.total && prev.penalty === t.penalty && prev.lastac === t.lastac)
      ? prev.place : seen;
    prev = t;
  });

  return { mode: 'icpc', probShorts, teams, balloons, secs: !!secs };
}

// posição RELATIVA AO RECORTE (R1, 2026-08-30): numera os times VISÍVEIS derivando da
// classificação do parse (t.place), com a MESMA regra de empate (total+penalty+lastac);
// convidado segue sem posição. Devolve Map username -> posição no recorte.
export function slicePlaces(teams) {
  const vis = teams.filter((t) => !t.guest && t.place != null)
    .slice().sort((a, b) => a.place - b.place);
  const m = new Map();
  // ranking de competição também no recorte: todo visível consome; empatado herda a
  // posição do primeiro do grupo (mesma regra da numeração geral)
  let sp = 0, cur = 0, prev = null;
  vis.forEach((t) => {
    sp++;
    if (!(prev && prev.total === t.total && prev.penalty === t.penalty && prev.lastac === t.lastac)) cur = sp;
    m.set(t.username, cur);
    prev = t;
  });
  return m;
}

// estrela relativa (R6): menor SEGUNDO de AC por problema entre os times visíveis —
// exata com a flag `s`; no TXT legado a precisão é o minuto (empate ⇒ mais de uma ★,
// deliberado). Convidado participa (no global a estrela do TXT também o considera).
export function sliceFts(teams, probShorts) {
  const best = {};
  teams.forEach((t) => {
    probShorts.forEach((sn) => {
      const s = t.probSecs && t.probSecs[sn];
      if (typeof s === 'number' && (best[sn] === undefined || s < best[sn])) best[sn] = s;
    });
  });
  return best;
}

function cellSolved(v) { return /^\d+\/\d+\/?\*?$/.test(v); }  // tries/minutes[*]
function cellWait(v) { return /^\d+\/-/.test(v); }             // tries/-

export function renderICPC(parsed, opts) {
  const { searchTerm = '', regionFn = null, genPlace = null, style = 'icon', showPhotos = false, classified = null } = opts || {};
  let teams = filterTeams(parsed.teams, searchTerm);
  if (regionFn) teams = teams.filter(regionFn);

  // FILTRO ATIVO renumera (R1, 2026-08-30 — revoga o "nunca renumera" de antes): o número
  // grande vira a posição NO RECORTE e o .plg a posição geral deste placar; a estrela vira
  // a do recorte (menor segundo entre os visíveis). genPlace (coorte×geral) só SEM filtro —
  // nunca três números na mesma célula.
  const filtered = !!(searchTerm && searchTerm.trim()) || !!regionFn;
  const sliceMap = filtered ? slicePlaces(teams) : null;
  const relFts = filtered ? sliceFts(teams, parsed.probShorts) : null;

  const table = el('table', { class: 'score m-icpc' });
  // quantos times a seleção deixou visíveis (o contador da barra de filtros lê daqui)
  table.dataset.shown = String(teams.length);
  table.dataset.total = String(parsed.teams.length);
  // largura por <colgroup>: com table-layout:fixed é o que garante que TODAS as colunas
  // caibam (o conteúdo quebra dentro da célula em vez de a tabela rolar).
  scoreCols(table, parsed.probShorts.length, { flag: true, penalty: true });
  const headRow = el('tr', {},
    // filtro ativo: nº grande = posição no recorte, .plg = geral; em placar de COORTE sem
    // filtro a coluna leva a posição da coorte e a do placar geral (genPlace)
    el('th', {}, '#', filtered ? el('span', { class: 'plg' }, T('Geral', 'Overall'))
      : (genPlace ? el('span', { class: 'plg' }, T('Geral', 'Overall')) : null)),
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
    if (filtered) {
      const sp = !t.guest ? sliceMap.get(t.username) : null;
      tr.append(el('td', { class: 'cl-place' }, sp != null ? String(sp) : '–',
        !t.guest && t.place != null ? el('span', { class: 'plg',
          title: T('Posição no placar completo (sem o filtro)', 'Position in the full scoreboard (without the filter)') }, String(t.place)) : null));
    } else {
      const gp = genPlace && !t.guest ? genPlace[t.username] : null;
      tr.append(el('td', { class: 'cl-place' }, t.guest ? '–' : String(t.place),
        gp != null ? el('span', { class: 'plg',
          title: T('Posição no placar geral', 'Position in the overall scoreboard') }, String(gp)) : null));
    }
    // bandeira
    const flagTd = el('td', {});
    if (t.flag) { const fi = flagEl(t.flag, { height: 18, title: t.flagTitle || t.flag }); if (fi) flagTd.append(fi); }
    tr.append(flagTd);
    // equipe (logo da escola opcional, via teams-meta; data-URL/local p/ offline)
    const safeLogo = /^(data:image\/|\/|https?:)/.test(t.schoolLogo || '') ? String(t.schoolLogo).replace(/"/g, '') : '';
    // o brasão sai da string de HTML e vira NÓ (o `setMediaSrc` põe o src e o `lazy` nativo).
    // O `safeLogo` valida a URL porque o `rule.logo` do teams-meta é escolha do admin.
    // ⚠ o `lazy` não é enfeite: sem ele o 1º render de uma prova grande pediria uma imagem — um
    // fork de bash sob fcgiwrap — por LINHA do placar.
    const logoImg = safeLogo ? el('img', { alt: '', loading: 'lazy',
      style: 'height:16px;vertical-align:middle;margin-right:4px;border-radius:2px',
      onerror: (e) => e.target.remove() }) : null;
    const label = (t.univShort ? `[${escapeHtml(t.univShort)}] ` : '') + escapeHtml(t.teamName || t.username);
    const teamTd = el('td', { class: 'team',
      title: [t.univFull || t.univShort || '', t.username].filter(Boolean).join(' · '), html: label });
    // chip ↑BR: classificado p/ a PRÓXIMA FASE (só o publicado chega no `classified`)
    const cinfo = classified && classified[t.username];
    if (cinfo) {
      const viaT = { regra1: T('regra 1', 'rule 1'), regra2: T('regra 2', 'rule 2'),
                     regra4: T('regra 4', 'rule 4'), comite: T('comitê', 'committee') }[cinfo.via] || cinfo.via;
      teamTd.append(' ', el('span', { class: 'qual-chip',
        title: T('Classificado — ', 'Qualified — ') + (cinfo.stage || '') +
               ' (' + viaT + (cinfo.sede ? ' · ' + cinfo.sede : '') + ')' }, '↑BR'));
    }
    if (logoImg) { teamTd.prepend(logoImg, ' '); setMediaSrc(logoImg, safeLogo, { lazy: true, onerror: () => logoImg.remove() }); }
    // 📷 = foto do time, SÓ com o placar aberto (opts.showPhotos = !frozen — R4, 2026-08-30;
    // a rota team-photo é pública, o gate aqui é de PRODUTO: freeze não denuncia presença)
    if (showPhotos && t.photoUrl) {
      teamTd.append(' ', mediaLink(t.photoUrl,
        { title: T('Ver a foto do time', 'View team photo'), style: 'text-decoration:none' }, '📷'));
    }
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
        // com filtro ativo a estrela exibida é SEMPRE a do recorte (menor segundo entre os
        // times visíveis); sem filtro, a global que veio do TXT (com a certeza do gerador)
        const fts = filtered
          ? (relFts[sn] !== undefined && t.probSecs && t.probSecs[sn] === relFts[sn])
          : v.endsWith('*');
        const shown = v.endsWith('*') ? v.slice(0, -1) : v;
        const color = balloonColorHex(parsed.balloons, sn);
        // valor dentro de .pv: é o que ganha fonte menor (e no celular sai de cena, dando
        // lugar ao ✓ — os números ficam no title).
        const td = el('td', { class: 'cell ok', title: cellTitle(sn, shown, T) },
          fts ? el('span', { class: 'fts' }, '★') : null,
          style === 'icon' && color ? balloonDot(color) : null,
          el('span', { class: 'pv' }, shown));
        paintSolvedCell(td, color, { style, fts });
        if (fts) {
          td.title = (filtered ? T('Primeiro a resolver no recorte', 'First to solve in the selection')
            : T('Primeiro a resolver', 'First to solve')) + ' · ' + cellTitle(sn, shown, T);
        }
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
