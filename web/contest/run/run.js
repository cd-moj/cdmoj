// contest/run/run.js — A PÁGINA DA SUBMISSÃO do juiz: /contest/run/?c=<contest>&id=<id | prefixo de 8+ hex>
// (09/11/2026). Pedidos do Roberto: um link que se compartilha com outro juiz, o clique do meio e o botão direito que
// funcionam, um id que se acha, o report que não some. Pedido do Paulo: o código com cor de sintaxe na tela, sem baixar.
// Dados: /submission/info (só juiz; o chefe e o admin veem quem enviou, o juiz puro julga anônimo — a regra é do
// servidor), o código de /submission/source e o report de /submission/log, com as regras de acesso de sempre.
// O report entra num <iframe> por BLOB URL — nunca pelo atributo srcdoc — porque as âncoras dos testes têm de rolar, não navegar.
import { apiGet, getToken } from '/shared/api.js';
import { status } from '/shared/auth.js';
import { el, verdictClass, fmtDate } from '/shared/ui.js';
import { mountChrome } from '/lib/contest-chrome.js';
import { T } from '/shared/i18n.js';
import { langLabel } from '/shared/languages.js';
import { mountSource, downloadText } from '/shared/code-viewer.js';
import { openReportAuthed, runHref } from '/shared/submission-links.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const ID = (qs.get('id') || '').trim().toLowerCase();
const enc = encodeURIComponent;
const G = { contest: CONTEST, auth: true };
const box = document.getElementById('runContainer');
let reportUrl = null;
window.addEventListener('pagehide', () => { if (reportUrl) URL.revokeObjectURL(reportUrl); });

// código curto do teste -> nome do veredicto (a cor é a mesma do resto do MOJ)
const CODE_NAME = { AC: 'Accepted', 'AC,PE': 'Accepted', WA: 'Wrong Answer', TLE: 'Time Limit Exceeded', MLE: 'Memory Limit Exceeded',
  RE: 'Runtime Error', RE_NZEC: 'Runtime Error', TMT: 'Wrong Answer', UE: 'Judge Error' };
const isFail = (c) => c && c !== 'AC' && c !== 'AC,PE';

function stLabel(st) {
  return ({ open: T('aberta', 'open', 'abierta'), claimed: T('reservada', 'claimed', 'reservada'), voting: T('em votação', 'voting', 'en votación'),
    conflict: T('conflito', 'conflict', 'conflicto'), released: T('liberada', 'released', 'liberada') })[st] || st;
}

function findBox() {
  const inp = el('input', { type: 'search', placeholder: T('id ou começo do id (8+)', 'id or the start of the id (8+)', 'id o el inicio del id (8+)'), value: ID });
  const go = () => { const v = inp.value.trim().toLowerCase(); if (/^[0-9a-f]{8,32}$/.test(v)) location.href = runHref(CONTEST, v); };
  inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') go(); });
  return el('div', { class: 'run-find' },
    el('label', { class: 'small' }, T('Abrir submissão: ', 'Open submission: ', 'Abrir envío: ')), inp,
    el('button', { class: 'btn ghost', onclick: go }, T('Abrir', 'Open', 'Abrir')),
    el('div', { class: 'spacer' }),
    el('a', { class: 'btn ghost', href: '/contest/judge/?c=' + enc(CONTEST) }, T('← Julgamento', '← Judging', '← Evaluación')),
    el('a', { class: 'btn ghost', href: '/contest/allsubmissions/?c=' + enc(CONTEST) }, T('Todas as submissões', 'All submissions', 'Todos los envíos')));
}

function fact(label, ...value) { return [el('dt', {}, label), el('dd', {}, ...value)]; }

function testsTable(tests) {
  if (!tests.length) return el('p', { class: 'small muted' }, T('Sem testes registrados (submissão pendente ou julgamento antigo).', 'No tests recorded (pending submission or old judging).', 'Sin pruebas registradas (envío pendiente o evaluación antigua).'));
  // ordem do NOME (a do pacote): os samples primeiro quando o nome os põe primeiro
  const rows = tests.slice().sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  const first = rows.find((t) => isFail(t.code));
  const tb = el('tbody');
  rows.forEach((t) => tb.append(el('tr', { class: t === first ? 'first-fail' : '' },
    el('td', {}, t.name, t === first ? el('span', { class: 'small muted' }, T(' — 1º a falhar', ' — first to fail', ' — 1.º en fallar')) : null),
    el('td', {}, el('span', { class: 'verdict ' + verdictClass(CODE_NAME[t.code] || t.code) }, t.code || '?')),
    el('td', { class: 'n' }, t.time != null ? String(t.time) + ' s' : '—'),
    el('td', { class: 'n' }, t.tl != null ? String(t.tl) + ' s' : '—'))));
  return el('div', { class: 'chart-wrap' }, el('table', { class: 'moj narrow' },
    el('thead', {}, el('tr', {}, el('th', {}, T('Teste', 'Test', 'Prueba')), el('th', {}, T('Veredicto', 'Verdict', 'Veredicto')),
      el('th', { class: 'n' }, T('Tempo', 'Time', 'Tiempo')), el('th', { class: 'n' }, 'TL'))), tb));
}

async function mountReport(host, s) {
  host.replaceChildren(el('div', { class: 'muted small' }, T('carregando o report…', 'loading the report…', 'cargando el informe…')));
  try {
    const r = await fetch(`/api/v1/submission/log?contest=${enc(CONTEST)}&id=${enc(s.id)}&time=${enc(s.sub_epoch || '')}`,
      { headers: { Authorization: 'Bearer ' + getToken(CONTEST) } });
    const body = await r.text();
    if (!r.ok) { let m = ''; try { m = JSON.parse(body).error.message || ''; } catch { /* não é JSON */ } throw new Error(m || 'HTTP ' + r.status); }
    if (reportUrl) URL.revokeObjectURL(reportUrl);
    reportUrl = URL.createObjectURL(new Blob([body], { type: 'text/html' }));
    // sandbox SEM allow-scripts: o blob é da origem desta página (a do token) e o report não tem script (default-src
    // 'none' no <head> dele) — o sandbox garante isso mesmo se um dia tiver. O allow-same-origin é o que deixa o Chrome
    // carregar o blob (com origem opaca o iframe fica em branco) e, sem scripts, não dá poder nenhum ao documento.
    host.replaceChildren(el('iframe', { class: 'run-report', src: reportUrl, title: 'report', sandbox: 'allow-same-origin' }));
  } catch (e) {
    host.replaceChildren(el('div', { class: 'error-box' }, T('Não foi possível abrir o report: ', 'Could not open the report: ', 'No se pudo abrir el informe: ') + (e.message || '')));
  }
}

async function render(info) {
  const s = { id: info.id, sub_epoch: info.sub_epoch, lang: info.lang };
  const msg = el('span', { class: 'small muted' });
  const copy = async (text, ok) => { try { await navigator.clipboard.writeText(text); msg.textContent = ok; } catch { msg.textContent = text; } };
  const link = location.origin + runHref(CONTEST, info.id);
  const verdict = info.verdict_canon || info.verdict || '?';
  const facts = el('dl', { class: 'run-facts' },
    ...fact(T('Problema', 'Problem', 'Problema'), el('b', {}, info.letter || '?'), ' ', info.title || info.problem_id || ''),
    ...fact(T('Linguagem', 'Language', 'Lenguaje'), langLabel(info.lang) || info.lang || ''),
    ...fact(T('Enviada', 'Submitted', 'Enviado'), fmtDate(info.sub_epoch),
      info.minute != null ? el('span', { class: 'small muted' }, T(' · minuto ', ' · minute ', ' · minuto ') + info.minute) : null),
    ...fact(T('Veredicto', 'Verdict', 'Veredicto'), el('span', { class: 'verdict ' + verdictClass(verdict), style: 'font-weight:700' }, verdict),
      info.verdict && info.verdict !== verdict ? el('span', { class: 'small muted' }, ' (' + info.verdict + ')') : null),
    ...(info.score_max ? fact(T('Pontos', 'Points', 'Puntos'), info.score + ' / ' + info.score_max,
      info.total_tests ? el('span', { class: 'small muted' }, ' · ' + info.correct + ' / ' + info.total_tests + T(' testes', ' tests', ' pruebas')) : null) : []),
    ...(info.host ? fact(T('Juiz', 'Judge', 'Juez'), info.host, info.duration_s != null ? el('span', { class: 'small muted' }, ' · ' + info.duration_s + ' s') : null) : []),
    ...(info.round ? fact(T('Rodada', 'Round', 'Ronda'), T('arquivada: ', 'archived: ', 'archivada: ') + info.round) : []),
    ...fact(T('Time', 'Team', 'Equipo'), info.anonymous
      ? el('span', { class: 'muted' }, T('anônimo (julgamento cego)', 'anonymous (blind judging)', 'anónimo (evaluación ciega)'))
      : el('span', {}, el('b', {}, info.login || ''), (info.team ? ' · ' + info.team : ''), (info.univ ? ' · ' + info.univ : ''))),
    ...(info.review ? fact(T('Revisão', 'Review', 'Revisión'), stLabel(info.review.status) + (info.review.conflict ? ' ⚠' : ''),
      el('span', { class: 'small muted' }, ' · ' + info.review.votes_n + T(' voto(s)', ' vote(s)', ' voto(s)')),
      info.review.votes ? el('span', { class: 'small muted' }, ' — ' + info.review.votes.map((v) => v.by + ': ' + v.verdict).join(', ')) : null) : []));

  const codeHost = el('div', { class: 'run-code' });
  const repHost = el('div', {});
  let codeText = '';
  const ext = String(info.lang || 'txt').toLowerCase();
  box.replaceChildren(findBox(),
    el('div', { class: 'row', style: 'align-items:center;gap:.5rem;flex-wrap:wrap' },
      el('h2', { style: 'margin:0' }, T('Submissão ', 'Submission ', 'Envío '), el('span', { class: 'run-id' }, info.id)),
      el('div', { class: 'spacer' }), msg,
      el('button', { class: 'btn ghost', onclick: () => copy(link, T('link copiado', 'link copied', 'enlace copiado')) }, T('🔗 Copiar link', '🔗 Copy link', '🔗 Copiar enlace')),
      el('button', { class: 'btn ghost', onclick: () => copy(info.id, T('id copiado', 'id copied', 'id copiado')) }, T('📋 Copiar id', '📋 Copy id', '📋 Copiar id'))),
    facts,
    el('h3', {}, T('Testes', 'Tests', 'Pruebas')), testsTable(info.tests || []),
    el('div', { class: 'row', id: 'code', style: 'align-items:center;gap:.5rem;margin-top:1rem' },
      el('h3', { style: 'margin:0' }, T('Código', 'Code', 'Código')), el('div', { class: 'spacer' }),
      el('button', { class: 'btn ghost', onclick: () => copy(codeText, T('código copiado', 'code copied', 'código copiado')) }, T('📋 Copiar', '📋 Copy', '📋 Copiar')),
      el('button', { class: 'btn ghost', onclick: () => { if (codeText) downloadText(info.id + '.' + ext, codeText); } }, T('⬇ Baixar', '⬇ Download', '⬇ Descargar'))),
    info.has_source ? codeHost : el('p', { class: 'small muted' }, T('Código-fonte indisponível.', 'Source code unavailable.', 'Código fuente no disponible.')),
    el('div', { class: 'row', id: 'report', style: 'align-items:center;gap:.5rem;margin-top:1rem' },
      el('h3', { style: 'margin:0' }, 'Report'), el('div', { class: 'spacer' }),
      el('button', { class: 'btn ghost', onclick: () => openReportAuthed(CONTEST, `/submission/log?contest=${enc(CONTEST)}&id=${enc(info.id)}&time=${enc(info.sub_epoch || '')}`) },
        T('↗ Abrir em nova aba', '↗ Open in a new tab', '↗ Abrir en una pestaña nueva'))),
    info.has_log ? repHost : el('p', { class: 'small muted' }, T('Report indisponível (pendente ou removido pela retenção).', 'Report unavailable (pending or removed by retention).', 'Informe no disponible (pendiente o eliminado por la retención).')));
  const jobs = [];
  if (info.has_source) jobs.push(mountSource(codeHost, CONTEST, s).then((r) => { if (r) codeText = r.code; }));
  if (info.has_log) jobs.push(mountReport(repHost, s));
  await Promise.all(jobs);
  const h = location.hash.slice(1);
  if (h === 'code' || h === 'report') { const t = document.getElementById(h); if (t) t.scrollIntoView(); }
}

async function boot() {
  if (!CONTEST) { box.replaceChildren(el('div', { class: 'error-box' }, T('Contest não informado (?c=).', 'Contest not specified (?c=).', 'Competencia no especificada (?c=).'))); return; }
  let basic;
  try { basic = await apiGet('/contest/basic?contest=' + enc(CONTEST), {}); }
  catch { box.replaceChildren(el('div', { class: 'error-box' }, T('Contest não encontrado.', 'Contest not found.', 'Competencia no encontrada.'))); return; }
  const st = await status(CONTEST);
  if (!st.logged_in) { location.href = '/contest/?c=' + enc(CONTEST); return; }
  await mountChrome(CONTEST, basic, { auth: true });
  if (!st.is_judge && !st.is_admin) { box.replaceChildren(el('div', { class: 'notice' }, T('Acesso restrito a juízes.', 'Access restricted to judges.', 'Acceso restringido a jueces.'))); return; }
  if (!ID) { box.replaceChildren(findBox(), el('p', { class: 'muted' }, T('Digite o id da submissão (ou os 8 primeiros caracteres, como na lista).', 'Type the submission id (or its first 8 characters, as in the list).', 'Escribe el id del envío (o sus primeros 8 caracteres, como en la lista).'))); return; }
  let info;
  try { info = await apiGet('/submission/info?contest=' + enc(CONTEST) + '&id=' + enc(ID), G); }
  catch (e) {
    const extra = (e && e.data && Array.isArray(e.data.ids)) ? el('ul', {}, ...e.data.ids.map((i) => el('li', {}, el('a', { href: runHref(CONTEST, i), class: 'run-id' }, i)))) : null;
    box.replaceChildren(findBox(), el('div', { class: 'error-box' }, (e && e.message) || T('erro', 'error', 'error')), extra);
    return;
  }
  // o id completo na barra: o link copiado de lá também serve
  if (info.id !== ID) history.replaceState(null, '', runHref(CONTEST, info.id) + location.hash);
  document.title = T('Submissão ', 'Submission ', 'Envío ') + info.id.slice(0, 8) + ' — MOJ';
  await render(info);
}
boot();
