// contest/score/score.js — placar do contest. Lê ?c=. Busca /contest/score (TXT),
// 1ª linha = modo, despacha para o renderizador certo. Busca, filtro de região,
// refresh 30–60s, animação de mudança de posição.
import { apiGet, apiGetText, apiGetTextMeta } from '/shared/api.js';
import { status, logout } from '/shared/auth.js';
import { el, fmtDate } from '/shared/ui.js';
import { flagManifest } from '/shared/flags.js';
import { parseICPC, renderICPC } from './score-icpc.js';
import { parseOBI, renderOBI } from './score-obi.js';
import { parseGeneric, renderGeneric } from './score-generic.js';
import { T, setLang, getLang } from '/shared/i18n.js';
import { navLabel } from '/shared/nav-i18n.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
let basic = null;
let isAuth = false;
let regions = [];
let teamsMeta = [];      // regras regex -> país/escola
let teamsDir = {};       // /contest/teams: login -> {team,univ_short,univ_full,flag,region,has_logo}
let flagNames = {};      // code(lower) -> nome (p/ título da bandeira e rótulo do filtro)
let activeCountry = '';
let activeSchool = '';
let anonMode = false;       // placar anônimo (agregado, sem desempenho individual)
let forcedAnon = false;     // contest força o modo anônimo (não-admin não desliga)
// região ativa: {name?, regex?} — casa por NOME (== sede do time, /contest/teams) OU regex
// no login. Persistida como JSON; valor legado (string crua) é tratado como regex.
let activeRegion = (() => {
  const v = localStorage.getItem('moj_score_region_' + CONTEST); if (!v) return null;
  try { const o = JSON.parse(v); return (o && (o.name || o.regex)) ? o : null; } catch { return { regex: v }; }
})();
let searchTerm = '';
let noAnim = false;
// COORTES: qual visão de placar pedir ao servidor. '' = a do login (o servidor decide);
// 'oficial' = só as coortes públicas; 'geral' = tudo (só vale p/ quem já pode ver tudo);
// <id de coorte> = placar paralelo dela. `?view=` na URL abre já naquele placar (link direto
// p/ "o placar dos individuais"); o servidor valida o valor, aqui é só a preferência inicial.
let cohortView = (qs.get('view') || '').replace(/[^a-z0-9_-]/gi, '');
let genPlace = null;        // login -> posição no placar GERAL (só em placar de coorte)
let frozenView = false;     // ESTE espectador recebeu o placar congelado (X-MOJ-Frozen) —
                            // gateia o 📷: foto só aparece com o placar aberto (R4, 2026-08-30)
let lastOrder = []; // usernames na ordem anterior (p/ animação)
let refreshTimer = null;

function fmtLeft(sec) {
  if (sec < 0) sec = 0;
  const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
  const p = (x) => String(x).padStart(2, '0');
  return h > 0 ? `${p(h)}:${p(m)}:${p(s)}` : `${p(m)}:${p(s)}`;
}

function navHref(url) {
  const c = encodeURIComponent(CONTEST);
  const map = {
    '/': `/contest/?c=${c}`, '/score': `/contest/score/?c=${c}`,
    '/all_submissions': `/contest/allsubmissions/?c=${c}`, '/stats': `/contest/statistics/?c=${c}`,
    '/pending': `/contest/judge/?c=${c}`, '/logout': '#logout',
  };
  if (map[url]) return map[url];
  return url + (url.includes('?') ? '&' : '?') + 'c=' + c;
}
let NAVBTNS = []; // últimos botões pintados — re-render quando o idioma muda (moj:lang)
function renderNav(buttons) {
  NAVBTNS = buttons;
  const nav = document.getElementById('contestNav'); nav.innerHTML = '';
  const here = location.pathname.replace(/\/+$/, '');
  buttons.forEach(b => {
    const href = navHref(b.url);
    const label = navLabel(b.url, b.label);
    if (href === '#logout') { nav.append(el('a', { href: '#', onclick: async (e) => { e.preventDefault(); await logout(CONTEST); location.href = '/contest/?c=' + encodeURIComponent(CONTEST); } }, label)); return; }
    const active = href.split('?')[0].replace(/\/+$/, '') === here;
    nav.append(el('a', { href, class: active ? 'active' : '' }, label));
  });
}
document.addEventListener('moj:lang', () => { if (NAVBTNS.length) renderNav(NAVBTNS); });

function startCountdown() {
  const eln = document.getElementById('contestCountdown');
  const pre = document.getElementById('prestartNotice');
  const preLeft = document.getElementById('prestartLeft');
  let wasBefore = false;
  const tick = () => {
    const now = Math.floor(Date.now() / 1000);
    // PRÉ-INÍCIO: o servidor já serve a vitrine (times SEM colunas de problema); aqui é só
    // o aviso + a contagem regressiva até o start. Ao zerar, busca o placar de verdade.
    const toStart = (basic.start_time || 0) - now;
    if (toStart > 0) {
      eln.textContent = T('Começa em: ', 'Starts in: ') + fmtLeft(toStart);
      preLeft.textContent = fmtLeft(toStart);
      pre.classList.remove('hidden');
      wasBefore = true;
      setTimeout(tick, 1000);
      return;
    }
    if (wasBefore) { wasBefore = false; pre.classList.add('hidden'); pollScore(); }
    const left = (basic.end_time || 0) - now;
    if (left > 0) { eln.textContent = T('Termina em: ', 'Ends in: ') + fmtLeft(left); setTimeout(tick, 1000); }
    else eln.textContent = T('Competição encerrada', 'Contest ended');
  };
  tick();
}

// ---- regiões -----------------------------------------------------------------
// t casa com a região ativa? Por NOME (t._region, vindo do /contest/teams, == sede
// explícita do time) OU pelo regex no login (clássico) — qualquer um serve.
function regionMatch(t) {
  if (!activeRegion) return true;
  if (activeRegion.regex) { const re = safeRe(activeRegion.regex); if (re && re.test(t.username || '')) return true; }
  if (activeRegion.name && (t._region || '') &&
      String(t._region).toLowerCase() === String(activeRegion.name).toLowerCase()) return true;
  return false;
}
function setRegion(r) {
  activeRegion = (r && (r.name || r.regex)) ? { name: r.name || '', regex: r.regex || '' } : null;
  if (activeRegion) localStorage.setItem('moj_score_region_' + CONTEST, JSON.stringify(activeRegion));
  else localStorage.removeItem('moj_score_region_' + CONTEST);
  reRender();
}
// sedes para o <select>: a ÁRVORE do regions.json (achatada, subregião indentada — é a curadoria
// do organizador e pode filtrar por regex) mais as sedes que aparecem no placar e não estão lá.
function regionOptions() {
  const out = [];
  const walk = (list, depth) => (list || []).forEach(r => {
    if (r.regex || r.name) out.push({ name: r.name || '', regex: r.regex || '', depth });
    if (Array.isArray(r.subregions) && r.subregions.length) walk(r.subregions, depth + 1);
  });
  walk(regions, 0);
  const seen = new Set(out.map(o => (o.name || '').toLowerCase()));
  ((parsed && parsed.teams) || []).forEach(t => {
    const n = t._region || ''; if (!n || seen.has(n.toLowerCase())) return;
    seen.add(n.toLowerCase()); out.push({ name: n, regex: '', depth: 0 });
  });
  return out;
}

// ---- país / escola (teams-meta) ---------------------------------------------
function safeRe(rx) { try { return new RegExp(rx, 'i'); } catch { return null; } }
// EXPLÍCITO primeiro (/contest/teams — o `.team` por-usuário + assets): preenche o que o
// TXT não trouxe, marca a sede (t._region, filtro por nome) e aponta o BRASÃO p/ a rota
// team-logo. O teams-meta (regex) roda depois, só nos vazios.
// O 📷 VOLTOU (R4, 2026-08-30 — revoga a decisão de 2026-08-24 de tirá-lo): photoUrl é
// preenchido de has_photo e o render só o mostra com o placar ABERTO (opts.showPhotos =
// !frozenView) — durante o freeze a foto denunciaria quem está presente/ativo.
function applyTeamsDir(p) {
  if (!p || !(p.mode === 'icpc' || p.mode === 'obi')) return;
  let anyFlag = false;
  p.teams.forEach(t => {
    // o TXT do placar já traz bandeira e sigla: quem não está no diretório (time removido do
    // store, vindo de USERS_FROM…) precisa entrar nos filtros do mesmo jeito.
    if (!t._country && t.flag) { t._country = t.flag; t.flagTitle = t.flagTitle || flagNames[String(t.flag).toLowerCase()] || t.flag; }
    if (!t._school && t.univShort) t._school = t.univShort;
    const d = teamsDir[t.username || ''];
    if (!d) return;
    if (d.flag) {
      if (!t.flag) { t.flag = d.flag; anyFlag = true; }
      t._country = d.flag;
      t.flagTitle = flagNames[String(d.flag).toLowerCase()] || d.flag;
    }
    if (d.univ_short && !t.univShort) t.univShort = d.univ_short;
    if (d.univ_full && !t.univFull) t.univFull = d.univ_full;
    if (d.region) t._region = d.region;
    t._school = t._school || t.univShort || '';
    if (d.has_logo && !t.schoolLogo) {
      t.schoolLogo = '/api/v1/contest/team-logo?contest=' + encodeURIComponent(CONTEST) + '&user=' + encodeURIComponent(t.username || '');
    }
    if (d.has_photo) {
      t.photoUrl = '/api/v1/contest/team-photo?contest=' + encodeURIComponent(CONTEST) + '&user=' + encodeURIComponent(t.username || '');
    }
    if (d.ai) t.aiDeclared = true;
  });
  if (anyFlag && p.mode === 'obi') p.hasFlag = true;
}
function applyTeamsMeta(p) {
  if (!p || !(p.mode === 'icpc' || p.mode === 'obi') || !teamsMeta.length) return;
  let anyFlag = false;
  const compiled = teamsMeta.map(r => ({ ...r, _re: safeRe(r.regex || '') }));
  p.teams.forEach(t => {
    const u = t.username || '';
    t._country = t._country || ''; t._school = t._school || t.univShort || '';
    const rule = compiled.find(r => r._re && r._re.test(u));
    if (!rule) return;
    if (rule.country) {
      if (!t.flag) { t.flag = rule.country; anyFlag = true; }
      t._country = rule.country;
      t.flagTitle = flagNames[String(rule.country).toLowerCase()] || rule.country;
    }
    if (rule.school && !t.univShort) t.univShort = rule.school;
    if (rule.school_full && !t.univFull) t.univFull = rule.school_full;
    if (rule.logo && !t.schoolLogo) t.schoolLogo = rule.logo;   // brasão por-time (teamsDir) vence
    t._school = rule.school || t.univShort || '';
  });
  if (anyFlag && p.mode === 'obi') p.hasFlag = true;
}
// casamento ESTRITO (igual ao do relatório): quem não tem o dado NÃO casa. Era
// `t._country !== undefined && …`, então time sem bandeira aparecia em QUALQUER filtro de
// bandeira — pedir "Santa Catarina" trazia de volta todo mundo sem bandeira.
const eqi = (a, b) => String(a || '').toLowerCase() === String(b || '').toLowerCase();
function combinedFilterFn() {
  if (!activeRegion && !activeCountry && !activeSchool) return null;
  return (t) => {
    if (!regionMatch(t)) return false;
    if (activeCountry && !eqi(t._country, activeCountry)) return false;
    if (activeSchool && !eqi(t._school, activeSchool)) return false;
    return true;
  };
}
// UMA barra de filtros, com os MESMOS controles do relatório offline (coorte, bandeira,
// universidade, sede, busca) + contador de times visíveis e "limpar". As opções vêm dos times
// PRESENTES no placar exibido: trocar de coorte reconstrói as listas.
function fLabel(txt, ctl) { return el('label', {}, txt, ctl); }
function renderFilters() {
  const bar = document.getElementById('scoreFilters');
  if (!bar) return;
  const isBoard = parsed && (parsed.mode === 'icpc' || parsed.mode === 'obi');
  bar.innerHTML = '';
  bar.classList.toggle('hidden', !!anonMode);   // no anônimo não há linha p/ filtrar

  // COORTE (troca o placar no servidor: cada visão tem posição e ⭐ próprias — filtrar linha
  // daria estrela errada, ver lib/cohorts.sh). Duas fontes: convidados × placares paralelos.
  const coh = basic && basic.cohort;
  const svs = (basic && basic.score_views) || [];
  let viewSel = null;
  // os ids são os MESMOS do relatório offline (fView/fFlag/fUniv/fRegion/fQ/fCount): a barra é a
  // mesma coisa nos dois lugares, e é por eles que a bancada de teste mexe nos controles.
  if (coh && (coh.views || []).length > 1) {
    viewSel = el('select', { id: 'fView' },
      el('option', { value: 'geral' }, T('Geral (com convidados)', 'Overall (with guests)')),
      el('option', { value: 'oficial' }, T('Oficial', 'Official')));
    viewSel.value = cohortView || 'geral';
  } else if (svs.length > 1) {
    viewSel = el('select', { id: 'fView' }, el('option', { value: '' }, T('Geral (todos)', 'Overall (everyone)')),
      ...svs.map((v) => el('option', { value: v.id }, v.name || v.id)));
    viewSel.value = cohortView || '';
  }
  if (viewSel) {
    viewSel.addEventListener('change', () => { cohortView = viewSel.value; pollScore(); });
    bar.append(fLabel(T('Placar:', 'Board:'), viewSel));
  }

  if (isBoard) {
    const countries = [...new Set(parsed.teams.map(t => t._country).filter(Boolean))]
      .sort((a, b) => flagLabel(a).localeCompare(flagLabel(b)));
    const schools = [...new Set(parsed.teams.map(t => t._school).filter(Boolean))].sort();
    if (countries.length) {
      const sel = el('select', { id: 'fFlag' }, el('option', { value: '' }, T('todas', 'all')),
        ...countries.map(c => el('option', { value: c }, flagLabel(c))));
      sel.value = activeCountry;
      sel.addEventListener('change', () => { activeCountry = sel.value; reRender(); });
      bar.append(fLabel(T('Bandeira:', 'Flag:'), sel));
    }
    if (schools.length) {
      const sel = el('select', { id: 'fUniv' }, el('option', { value: '' }, T('todas', 'all')),
        ...schools.map(s => el('option', { value: s }, s)));
      sel.value = activeSchool;
      sel.addEventListener('change', () => { activeSchool = sel.value; reRender(); });
      bar.append(fLabel(T('Universidade:', 'University:'), sel));
    }
    const rops = regionOptions();
    if (rops.length) {
      const sel = el('select', { id: 'fRegion' }, el('option', { value: '' }, T('todas', 'all')),
        ...rops.map((r, i) => el('option', { value: String(i) },
          ' '.repeat(r.depth * 2) + (r.name || r.regex))));
      const cur = rops.findIndex(r => (r.name || '') === ((activeRegion && activeRegion.name) || '') &&
                                      (r.regex || '') === ((activeRegion && activeRegion.regex) || ''));
      sel.value = activeRegion && cur >= 0 ? String(cur) : '';
      sel.addEventListener('change', () => setRegion(sel.value === '' ? null : rops[Number(sel.value)]));
      bar.append(fLabel(T('Sede:', 'Site:'), sel));
    }
  }

  const q = el('input', { id: 'fQ', class: 'filter', type: 'search',
    placeholder: T('buscar time, universidade, login…', 'search team, university, login…') });
  q.value = searchTerm;
  q.addEventListener('input', () => { searchTerm = q.value; reRender(); });
  bar.append(q);
  bar.append(el('button', { id: 'fClear', type: 'button', onclick: () => {
    activeCountry = ''; activeSchool = ''; searchTerm = ''; setRegion(null); renderFilters();
  } }, T('limpar filtros', 'clear filters')));
  bar.append(el('span', { class: 'fcount', id: 'fCount' }, ''));
}
function flagLabel(c) { return flagNames[String(c).toLowerCase()] || String(c).toUpperCase(); }
// contador: quantos times a seleção deixou visíveis. Com filtro ativo o placar RENUMERA
// (R1, 2026-08-30 — revoga o "nunca renumera"): nº grande = posição no recorte, .plg = a
// geral; no ICPC a ★ passa a ser a do recorte, e o contador avisa.
function updateCount(shown, total, filtered) {
  const c = document.getElementById('fCount');
  if (!c) return;
  c.textContent = (shown === total && !filtered)
    ? T(`${total} times`, `${total} teams`)
    : T(`Mostrando ${shown} de ${total} times`, `Showing ${shown} of ${total} teams`)
      + (filtered && parsed && parsed.mode === 'icpc' ? T(' · ★ = 1º do recorte', ' · ★ = 1st in selection') : '');
}

// ---- placar anônimo (agregado: distribuição + quartis, sem nomes) ------------
function renderAnon(p) {
  const box = document.getElementById('scoreContainer'); box.innerHTML = '';
  if (!(p.mode === 'icpc' || p.mode === 'obi')) { box.innerHTML = `<span class="muted">${T('Modo anônimo é só p/ ICPC/OBI.', 'Anonymous mode is ICPC/OBI only.')}</span>`; return; }
  const isSolved = p.mode === 'icpc' ? (v) => /^\d+\/\d+\/?\*?$/.test(v || '') : (v) => { const n = parseInt(v, 10); return v !== '' && n > 0; };
  const teams = p.teams || [];
  const solves = teams.map((t) => p.probShorts.filter((sn) => isSolved(t.probs[sn])).length);
  const n = solves.length, sorted = solves.slice().sort((a, b) => b - a);
  const at = (q) => (n ? sorted[Math.min(n - 1, Math.floor(q * n))] : 0);
  const dist = {}; solves.forEach((k) => { dist[k] = (dist[k] || 0) + 1; });
  const probCounts = p.probShorts.map((sn) => ({ sn, c: teams.filter((t) => isSolved(t.probs[sn])).length }));
  const card = (big, sub) => el('div', { style: 'flex:1;min-width:110px;background:#fff;border:1px solid #e3e9f2;border-radius:10px;padding:.7rem .9rem' },
    el('div', { style: 'font-size:1.7rem;font-weight:800;line-height:1' }, String(big)), el('div', { style: 'color:#64748b;font-size:.82rem' }, sub));
  const bar = (pc) => el('span', { style: 'display:inline-block;height:.7em;background:#1e57c4;border-radius:3px;min-width:2px;vertical-align:middle;width:' + pc + '%' });
  box.append(el('div', { style: 'background:#eef3fb;border-radius:8px;padding:.5rem .7rem;margin-bottom:.6rem;color:#334155' },
    '🔒 ' + T('Placar anônimo — desempenho individual oculto.', 'Anonymous scoreboard — individual performance hidden.')));
  box.append(el('div', { style: 'display:flex;gap:.8rem;flex-wrap:wrap;margin-bottom:.4rem' },
    card(n, T('participantes', 'participants')), card('≥' + at(0.25), T('top 25% resolveu', 'top 25% solved')),
    card(at(0.5), T('mediana', 'median')), card('≥' + at(0.75), T('75% resolveu ≥', '75% solved ≥')), card(sorted[0] || 0, T('máximo', 'max'))));
  const dtb = el('tbody');
  Object.keys(dist).map(Number).sort((a, b) => a - b).forEach((k) => {
    const pc = n ? Math.round(dist[k] / n * 100) : 0;
    dtb.append(el('tr', {}, el('td', {}, k + ' ' + T('problema(s)', 'problem(s)')), el('td', {}, String(dist[k])), el('td', {}, bar(pc), ' ' + pc + '%')));
  });
  box.append(el('h3', { style: 'margin:1rem 0 .3rem' }, T('Distribuição (quantos resolveram quantos)', 'Distribution')),
    el('table', { class: 'score' }, el('thead', {}, el('tr', {}, el('th', {}, T('Resolvidos', 'Solved')), el('th', {}, T('Participantes', 'Participants')), el('th', {}, '%'))), dtb));
  const ptb = el('tbody');
  probCounts.forEach((x) => { const pc = n ? Math.round(x.c / n * 100) : 0; ptb.append(el('tr', {}, el('td', {}, el('b', {}, x.sn)), el('td', {}, String(x.c)), el('td', {}, bar(pc), ' ' + pc + '%'))); });
  box.append(el('h3', { style: 'margin:1rem 0 .3rem' }, T('Resolvedores por problema', 'Solvers per problem')),
    el('table', { class: 'score' }, el('thead', {}, el('tr', {}, el('th', {}, T('Problema', 'Problem')), el('th', {}, T('Resolveram', 'Solved')), el('th', {}, '%'))), ptb));
}

// ---- render principal --------------------------------------------------------
let parsed = null;
function reRender() {
  const box = document.getElementById('scoreContainer');
  if (!parsed) { box.innerHTML = `<span class="muted">${T('Placar indisponível.', 'Scoreboard unavailable.')}</span>`; return; }
  // modo anônimo é agregado: filtro de linha não se aplica, então a barra sai de cena (senão
  // ficaria um contador mentindo sobre um placar que não mostra times)
  const fb = document.getElementById('scoreFilters');
  if (fb) fb.classList.toggle('hidden', !!anonMode);
  if (anonMode) { renderAnon(parsed); return; }
  const opts = { searchTerm, regionFn: combinedFilterFn(), genPlace,
    showPhotos: !frozenView,   // 📷 só com o placar ABERTO (R4)
    style: (basic && basic.balloon_style) === 'fill' ? 'fill' : 'icon' };
  let table;
  if (parsed.mode === 'icpc') table = renderICPC(parsed, opts);
  else if (parsed.mode === 'obi') table = renderOBI(parsed, opts);
  else table = renderGeneric(parsed, opts);
  box.innerHTML = '';
  // .board-wrap (e NÃO .chart-wrap): o placar não rola para o lado — as larguras do
  // <colgroup> já garantem que tudo cabe, quebrando linha quando precisa.
  box.append(el('div', { class: 'board-wrap' }, table));
  updateCount(Number(table.dataset.shown || 0), Number(table.dataset.total || 0),
    !!((searchTerm && searchTerm.trim()) || opts.regionFn));
  animateMoves();
}

function currentOrder() {
  if (!parsed) return [];
  if (parsed.mode === 'icpc' || parsed.mode === 'obi') return parsed.teams.map(t => t.username);
  if (parsed.iUser >= 0) return parsed.rows.map(r => r[parsed.iUser] || '');
  return [];
}
function animateMoves() {
  if (noAnim) { lastOrder = currentOrder(); return; }
  const order = currentOrder();
  const oldPos = {}; lastOrder.forEach((u, i) => { oldPos[u] = i; });
  order.forEach((u, i) => {
    if (oldPos[u] == null) return;
    const row = document.getElementById('tr-team-' + String(u).replace(/\W/g, '_'));
    if (!row) return;
    if (oldPos[u] > i) { row.classList.add('placing-up'); setTimeout(() => row.classList.remove('placing-up'), 1100); }
    else if (oldPos[u] < i) { row.classList.add('placing-down'); setTimeout(() => row.classList.remove('placing-down'), 1100); }
  });
  lastOrder = order;
}

// posição de cada login no placar GERAL (a visão que ESTE espectador recebe sem `?view=`).
// Serve p/ o placar de coorte mostrar as duas classificações, como o relatório offline.
async function fetchGenPlace() {
  genPlace = null;
  // só faz sentido num placar paralelo/de coorte; 'geral' e 'oficial' diferem só por convidado,
  // que não consome posição — a classificação é a mesma e o 2º número seria ruído.
  if (!cohortView || cohortView === 'geral' || cohortView === 'oficial') return;
  let txt = '';
  try { txt = await apiGetText('/contest/score?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: isAuth }); }
  catch { return; }
  const lines = txt.replace(/\r/g, '').split('\n');
  const mode = (lines[0] || '').trim().toLowerCase();
  const data = lines.slice(1).filter(Boolean);
  if (!data.length) return;
  let p = null;
  if (/^icpc/.test(mode)) p = parseICPC(data, BALLOONS, mode.split(/\s+/).includes('s'));
  else if (/^obi/.test(mode)) p = parseOBI(data);
  if (!p) return;
  const m = {};
  p.teams.forEach(t => { if (t.username && t.place != null) m[t.username] = t.place; });
  genPlace = Object.keys(m).length ? m : null;
}
// AVISO DE FREEZE. Quem decide é o servidor (cabeçalho `X-MOJ-Frozen` do /contest/score): a
// página não tem como saber se ESTE espectador recebeu o placar congelado ou o completo. Sem o
// aviso, o competidor lê um placar parado nos últimos 60 minutos achando que é o placar de
// verdade — e é justamente o momento mais tenso da prova.
function setFrozenNotice(on) {
  const box = document.getElementById('freezeNotice');
  if (!box) return;
  box.classList.toggle('hidden', !on);
  if (!on) return;
  const t = (basic && basic.freeze_time) || 0;
  const el2 = document.getElementById('freezeSince');
  if (el2) el2.textContent = t ? new Date(t * 1000).toLocaleTimeString() : '';
}

async function pollScore() {
  clearTimeout(refreshTimer);
  let txt = '';
  try {
    const r = await apiGetTextMeta('/contest/score?contest=' + encodeURIComponent(CONTEST)
      + (cohortView ? '&view=' + encodeURIComponent(cohortView) : ''),
      { contest: CONTEST, auth: isAuth });
    txt = r.text;
    frozenView = r.headers.get('X-MOJ-Frozen') === '1';
    setFrozenNotice(frozenView);
  }
  catch {
    const box = document.getElementById('scoreContainer');
    if (basic && basic.secret && !isAuth) {
      // contest SUPER SECRETO: o placar exige sessão do contest — convite ao login, sem erro cru
      box.innerHTML = `<div class="section" style="text-align:center"><h2>🔒 ${T('Contest privado', 'Private contest')}</h2>
        <p class="muted">${T('Entre no contest para ver o placar.', 'Log in to the contest to view the scoreboard.')}</p>
        <p><a class="btn" href="/contest/?c=${encodeURIComponent(CONTEST)}">${T('Entrar →', 'Log in →')}</a></p></div>`;
      return;
    }
    box.innerHTML = `<span class="error-box">${T('Falha ao carregar o placar.', 'Failed to load scoreboard.')}</span>`; return;
  }

  const lines = txt.replace(/\r/g, '').split('\n');
  const mode = (lines[0] || '').trim().toLowerCase();
  const dataLines = lines.slice(1).filter(Boolean);

  if (!dataLines.length) {
    // só o modo (placar ainda não gerado)
    parsed = null;
    document.getElementById('scoreContainer').innerHTML = `<span class="muted">${T('Placar ainda não gerado.', 'Scoreboard not generated yet.')}</span>`;
  } else if (/^icpc/.test(mode)) {
    // flag `s` na linha do modo = células em SEGUNDOS (R6) — o parse exibe minutos
    parsed = parseICPC(dataLines, BALLOONS, mode.split(/\s+/).includes('s'));
  } else if (/^obi/.test(mode)) {
    parsed = parseOBI(dataLines);
  } else {
    // treino / heuristic / outro / qualquer outro -> genérico
    parsed = parseGeneric(dataLines, mode || 'outro');
  }
  if (parsed) {
    if (!parsed.balloons) parsed.balloons = BALLOONS;
    applyTeamsDir(parsed); applyTeamsMeta(parsed);
    await fetchGenPlace();
    // a mesma classificação nos dois placares (nada a informar) ⇒ não mostra a 2ª posição
    if (genPlace && parsed.teams.every(t => t.place == null || genPlace[t.username] === t.place)) genPlace = null;
    renderFilters(); reRender();
  }

  refreshTimer = setTimeout(pollScore, 30000 + Math.random() * 30000); // 30–60s
}

// ---- boot --------------------------------------------------------------------
let BALLOONS = {};
async function boot() {
  if (!CONTEST) { document.body.innerHTML = '<div class="container"><div class="error-box">' + T('Contest não informado (use ?c=&lt;id&gt;).', 'No contest specified (use ?c=&lt;id&gt;).') + '</div></div>'; return; }
  try { basic = await apiGet('/contest/basic?contest=' + encodeURIComponent(CONTEST), {}); }
  catch { document.body.innerHTML = '<div class="container"><div class="error-box">' + T('Contest não encontrado.', 'Contest not found.') + '</div></div>'; return; }
  if (basic.locale) setLang(basic.locale, { persist: false });
  document.title = T('Placar — ', 'Scoreboard — ') + (basic.contest_name || 'Contest') + ' — MOJ';
  document.getElementById('contestTitle').textContent = basic.contest_name || 'Contest';
  document.getElementById('backBtn').href = '/contest/?c=' + encodeURIComponent(CONTEST);
  startCountdown();

  const st = await status(CONTEST);
  isAuth = !!st.logged_in;
  document.getElementById('publicNotice').classList.toggle('hidden', isAuth);

  // nav + balões + regiões + times (auth quando possível; tolerante a falha)
  const [nav, bc, rg, tm, td, mani] = await Promise.all([
    apiGet('/contest/navbuttons?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: isAuth }).catch(() => null),
    apiGet('/contest/balloons?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: isAuth }).catch(() => null),
    apiGet('/contest/regions?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: isAuth }).catch(() => null),
    apiGet('/contest/teams-meta?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: isAuth }).catch(() => null),
    apiGet('/contest/teams?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: isAuth }).catch(() => null),
    flagManifest().catch(() => ({ countries: [], br_states: [] })),
  ]);
  if (nav) { const buttons = Array.isArray(nav) ? nav : (nav.buttons || []); if (buttons.length) renderNav(buttons); }
  BALLOONS = bc ? (bc.balloons || bc) : {};
  regions = rg ? (Array.isArray(rg) ? rg : (rg.regions || [])) : [];
  teamsMeta = tm ? (tm.rules || (Array.isArray(tm) ? tm : [])) : [];
  teamsDir = (td && td.teams) || {};
  (mani.countries || []).forEach(c => { flagNames[c.code] = c.name; });
  (mani.br_states || []).forEach(s => { flagNames['br-' + s.code] = s.name; });

  // controles (busca, bandeira, universidade, sede e coorte vivem na barra: renderFilters)
  document.getElementById('noAnim').addEventListener('change', (e) => { noAnim = e.target.checked; });

  // modo anônimo: forçado pelo contest (não-admin não desliga) ou alternável localmente
  forcedAnon = !!(basic && basic.score_anon);
  anonMode = forcedAnon || localStorage.getItem('moj_score_anon_' + CONTEST) === '1';
  if (!(forcedAnon && !st.is_admin)) {
    const cb = el('input', { type: 'checkbox' }); cb.checked = anonMode;
    cb.addEventListener('change', () => { anonMode = cb.checked; localStorage.setItem('moj_score_anon_' + CONTEST, cb.checked ? '1' : '0'); reRender(); });
    document.getElementById('noAnim').parentNode.parentNode.append(
      el('label', { class: 'small', style: 'margin-left:.6rem' }, cb, ' ' + T('Anônimo', 'Anonymous')));
  }

  // COORTES: o AVISO p/ quem é convidado (o seletor de placar mora na barra de filtros, junto
  // dos outros — quem escolhe a visão está filtrando o placar como quem escolhe uma bandeira).
  const coh = basic && basic.cohort;
  if (coh && (coh.unranked || !coh.public)) {
    const main = document.querySelector('main.container') || document.body;
    main.prepend(el('div', { class: 'alert', style: 'font-weight:600' },
      T(`🏅 Você está na categoria “${coh.name}” (convidado): aparece neste placar, mas fora da classificação oficial.`,
        `🏅 You are in the “${coh.name}” category (guest): you show up on this scoreboard, but outside the official ranking.`)));
  }

  // ordenação por clique no cabeçalho (delegação)
  document.getElementById('scoreContainer').addEventListener('click', (e) => {
    const th = e.target.closest('table.score th');
    if (!th || !parsed) return;
    sortByHeader(th);
  });

  await pollScore();
}

// ordenação simples por coluna clicada (placar já vem ordenado; isto é um extra do usuário)
let sortState = { key: null, asc: false };
function sortByHeader(th) {
  const ths = Array.from(th.parentNode.children);
  const colIndex = ths.indexOf(th); // 0 = '#'
  if (colIndex <= 0) { // voltar à ordem original do servidor
    sortState = { key: null, asc: false };
    reRender();
    return;
  }
  const key = th.textContent.trim();
  sortState.asc = (sortState.key === key) ? !sortState.asc : false;
  sortState.key = key;
  const dir = sortState.asc ? 1 : -1;
  const numCmp = (a, b) => {
    const na = parseFloat(a), nb = parseFloat(b);
    if (!Number.isNaN(na) && !Number.isNaN(nb)) return (na - nb) * dir;
    return String(a).localeCompare(String(b)) * dir;
  };
  if (parsed.mode === 'icpc' || parsed.mode === 'obi') {
    // colunas: 0=#,1=Bandeira(se houver)... usamos os campos conhecidos
    if (/^total$/i.test(key)) parsed.teams.sort((a, b) => numCmp(a.total, b.total));
    else if (parsed.probShorts.includes(key)) parsed.teams.sort((a, b) => numCmp(a.probs[key] || '', b.probs[key] || ''));
    else parsed.teams.sort((a, b) => numCmp((a.teamName || a.username), (b.teamName || b.username)));
  } else {
    const hi = parsed.header.findIndex(h => h.trim() === key);
    if (hi >= 0) parsed.rows.sort((a, b) => numCmp(a[hi] || '', b[hi] || ''));
  }
  reRender();
}

boot();
