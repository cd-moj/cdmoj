// contest/submissions-table.js — a tabela "Minhas submissões" do competidor (filtro por problema,
// ordenação por coluna, resumo por modo, poll enquanto há pendente). Fonte ÚNICA (issue #26,
// 2026-09-15): vive na página principal do contest (seção do fim) E na página própria
// /contest/submissions/ — antes era código solto dentro de contest.js.
//
//   const st = makeSubmissionsTable({ contest, basic, problems, userinfo, filterEl, tableEl, onLoaded });
//   await st.load();   // busca o history, pinta e agenda o poll (5–10 s) se houver pendente
//   st.stop();         // cancela o poll (ao sair da página)
// `onLoaded(submissions)` avisa quem precisa da lista (a página principal re-tinge os problemas).
import { apiGet, apiGetText, getToken } from '/shared/api.js';
import { el, verdictClass, isPending, fmtDate, resumoText } from '/shared/ui.js';
import { openHtmlReport } from '/shared/submission-links.js';
import { swapIf, sigOf } from '/shared/admin-ui.js';
import { T } from '/shared/i18n.js';

// tempo:username:problemid:lang:verdict:epoch:subid  (verdict pode conter ':')
// ⚠ o campo 0 ("tempo") NÃO é minuto de prova: a reforma do store grava o EPOCH nele. O minuto
// de prova é calculado na hora de renderizar, a partir do início do contest.
export function parseHistLine(line) {
  const a = line.split(':');
  if (a.length < 7) return null;
  return {
    sinceStart: parseInt(a[0], 10) || 0, user: a[1], problem: a[2], lang: a[3],
    subid: a[a.length - 1], epoch: parseInt(a[a.length - 2], 10) || 0,
    verdict: a.slice(4, a.length - 2).join(':'),
  };
}

export function makeSubmissionsTable({ contest, basic, problems, userinfo, filterEl, tableEl, onLoaded } = {}) {
  const enc = encodeURIComponent;
  let submissions = [], subSumm = {}, subFilter = 'ALL', sortField = 'epoch', sortAsc = false, pollTimer = null;
  const probs = () => (problems || []).filter((p) => p.show !== false);
  const shortNameOf = (pid) => { const p = (problems || []).find((x) => x.problem_id === pid); return p ? (p.short_name || pid) : pid; };
  const fullNameOf = (pid) => { const p = (problems || []).find((x) => x.problem_id === pid); return p ? (p.full_name || '') : ''; };
  // minuto de prova (o que "Tempo" significa no ICPC; negativo antes do início = juiz testando)
  const minuto = (epoch) => { const ini = (basic && basic.start_time) || 0; return (!ini || !epoch) ? '—' : String(Math.floor((epoch - ini) / 60)); };

  async function downloadAuthed(path, filename) {
    try {
      const r = await fetch('/api/v1' + path, { headers: { Authorization: 'Bearer ' + getToken(contest) } });
      if (!r.ok) throw new Error('HTTP ' + r.status);
      const a = el('a', { href: URL.createObjectURL(await r.blob()), download: filename });
      document.body.append(a); a.click(); a.remove();
    } catch { alert(T('Falha ao baixar arquivo/log.', 'Failed to download file/log.')); }
  }
  async function openReportAuthed(path) {
    try {
      const r = await fetch('/api/v1' + path, { headers: { Authorization: 'Bearer ' + getToken(contest) } });
      openHtmlReport(await r.text());
    } catch { alert(T('Falha ao abrir o report.', 'Failed to open the report.')); }
  }

  // EM LUGAR (regra da casa): o poll (5–10 s com pendente) só troca o DOM quando a ASSINATURA
  // do que aparece muda — filtro/ordenação/linhas — senão o clique do time no chip ou no
  // cabeçalho "pisca" e o scroll da tabela volta ao topo a cada tick
  function renderFilter() {
    if (!filterEl) return;
    const sig = sigOf('f', subFilter, probs().map((p) => [p.problem_id, p.short_name]));
    swapIf(filterEl, sig, () => {
      const box = el('span', {});
      const mk = (label, val) => box.append(el('span', { class: 'tag' + (subFilter === val ? ' active' : ''),
        onclick: () => { subFilter = val; renderFilter(); renderTable(); } }, label));
      mk(T('Todos', 'All'), 'ALL');
      probs().forEach((p) => mk(p.short_name || p.problem_id, p.problem_id));
      return box;
    });
  }

  function renderTable() {
    if (!tableEl) return;
    const canLog = !!(userinfo && (userinfo.show_log || userinfo.is_admin || userinfo.is_judge));
    const sig = sigOf('t', subFilter, sortField, sortAsc, canLog, (basic && basic.start_time) || 0,
      submissions.map((s) => [s.subid, s.verdict, s.epoch, s.problem, resumoText(subSumm[s.subid]) || '']));
    swapIf(tableEl, sig, () => buildTable(canLog));
  }
  function buildTable(canLog) {
    let rows = submissions.filter((s) => subFilter === 'ALL' || s.problem === subFilter);
    rows = rows.slice().sort((a, b) => {
      if (sortField === 'epoch') return sortAsc ? a.epoch - b.epoch : b.epoch - a.epoch;
      if (sortField === 'problem') { const sa = shortNameOf(a.problem), sb = shortNameOf(b.problem); return sortAsc ? sa.localeCompare(sb) : sb.localeCompare(sa); }
      if (sortField === 'verdict') return sortAsc ? (a.verdict || '').localeCompare(b.verdict || '') : (b.verdict || '').localeCompare(a.verdict || '');
      return 0;
    });
    if (!rows.length) return el('span', { class: 'muted small' }, T('Nenhuma submissão ainda.', 'No submissions yet.'));
    const arrow = (f) => sortField === f ? (sortAsc ? ' ▲' : ' ▼') : '';
    const th = (label, f) => el('th', { onclick: () => { sortAsc = (sortField === f) ? !sortAsc : false; sortField = f; renderTable(); } }, label + arrow(f));
    const head = el('thead', {}, el('tr', {},
      th(T('Tempo', 'Time'), 'epoch'), th(T('Problema', 'Problem'), 'problem'), el('th', {}, T('Arquivo', 'File')),
      th(T('Resultado', 'Result'), 'verdict'), el('th', {}, T('Data', 'Date')), canLog ? el('th', {}, 'Log') : null));
    const tb = el('tbody');
    rows.forEach((s) => {
      const pending = isPending(s.verdict);
      const fileLink = el('a', { href: '#', onclick: (e) => { e.preventDefault();
        downloadAuthed(`/submission/source?contest=${enc(contest)}&id=${enc(s.subid)}&time=${enc(s.epoch)}`, s.subid + '.' + (s.lang || 'txt').toLowerCase()); } }, T('cód', 'src'));
      // detalhe sob o veredicto (pontos/grupos): o servidor redige por modo — em icpc vem null
      const rtxt = pending ? '' : resumoText(subSumm[s.subid]);
      const vcell = el('td', {}, el('span', { class: 'verdict ' + verdictClass(s.verdict) },
        pending ? el('span', {}, el('span', { class: 'spin' }), ' ' + s.verdict) : s.verdict),
        rtxt ? el('div', { class: 'small muted', style: 'margin-top:.15rem' }, rtxt) : '');
      const logCell = canLog ? el('td', {}, el('a', { href: '#', onclick: (e) => { e.preventDefault();
        openReportAuthed(`/submission/log?contest=${enc(contest)}&id=${enc(s.subid)}&time=${enc(s.epoch)}`); } }, 'log')) : null;
      tb.append(el('tr', {}, el('td', {}, minuto(s.epoch)),
        el('td', {}, el('b', {}, shortNameOf(s.problem)), ' ', el('span', { class: 'small muted' }, fullNameOf(s.problem))),
        el('td', {}, fileLink), vcell, el('td', {}, fmtDate(s.epoch)), logCell));
    });
    return el('table', { class: 'moj' }, head, tb);
  }

  async function load() {
    let txt;
    try { txt = await apiGetText('/contest/history?contest=' + enc(contest), { contest, auth: true }); }
    catch { return; }
    submissions = txt.split('\n').map((s) => s.trim()).filter(Boolean).map(parseHistLine).filter(Boolean);
    // resumo das já julgadas — lotes de 100 (URL curta), best-effort; icpc devolve null e nada aparece
    const done = submissions.filter((s) => !isPending(s.verdict)).map((s) => s.subid).filter((id) => !(id in subSumm));
    for (let i = 0; i < done.length; i += 100) {
      try { Object.assign(subSumm, await apiGet('/submission/summary?contest=' + enc(contest) + '&ids=' + done.slice(i, i + 100).join(','), { contest, auth: true }) || {}); }
      catch { /* best-effort */ }
    }
    renderFilter(); renderTable();
    if (onLoaded) { try { onLoaded(submissions); } catch { /* quem ouve cuida */ } }
    clearTimeout(pollTimer);
    if (submissions.some((s) => isPending(s.verdict))) pollTimer = setTimeout(load, 5000 + Math.random() * 5000);
  }
  function stop() { clearTimeout(pollTimer); pollTimer = null; }
  return { load, stop, render: () => { renderFilter(); renderTable(); }, get submissions() { return submissions; },
    setProblems(p) { problems = p; }, setUserinfo(u) { userinfo = u; } };
}
