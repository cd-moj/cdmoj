// contest/judge/judge.js — JUDGE: avaliação de veredicto.
// Dois modos: (1) MANUAL (contest com manual_verdict): fila de revisão /contest/review/* — pega
// (máx 2, 1 ativa, 5 min + prorroga), vê log+fonte+veredicto computado, escolhe o veredicto;
// 2 juízes no mesmo → vai ao aluno; diferentes → conflito (juiz-chefe resolve). (2) LEGADO:
// /contest/allsubmissions + /contest/set-verdict (admin/chief).
import { apiGet, apiGetText, apiPost } from '/shared/api.js';
import { status } from '/shared/auth.js';
import { el, verdictClass, isPending, fmtDate } from '/shared/ui.js';
import { mountChrome } from '/lib/contest-chrome.js';
import { logLink as _logLink, srcLink as _srcLink } from '/shared/submission-links.js';
import { T } from '/shared/i18n.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const enc = encodeURIComponent;
const G = { contest: CONTEST, auth: true };
let problems = [], subs = [], finalVerdicts = [];
let REVIEW = false, rv = null, ME = '', OPTIONS = [], IS_CHIEF = false, pollT = null, tickT = null;

const shortOf = (pid) => { const p = problems.find(x => x.problem_id === pid); return p ? (p.short_name || pid) : pid; };

// log/código autenticados (com a extensão certa) — helpers compartilhados em submission-links.js
const logLink = (s) => _logLink(CONTEST, s);
const srcLink = (s) => _srcLink(CONTEST, s);

// ===================== MODO MANUAL (fila de revisão) =====================
async function rvAct(path, body) { return apiPost('/contest/review/' + path + '?contest=' + enc(CONTEST), body, G); }

function countsBar(c) {
  return el('div', { class: 'row', style: 'gap:.6rem; flex-wrap:wrap; margin-bottom:.5rem' },
    el('span', { class: 'dash-card' }, el('b', {}, c.not_evaluated || 0), T(' não avaliadas', ' not evaluated')),
    el('span', { class: 'dash-card' }, el('b', {}, c.being_evaluated || 0), T(' sendo avaliadas', ' being evaluated')),
    el('span', { class: 'dash-card' }, el('b', {}, c.awaiting_second || 0), T(' aguardando 2º voto', ' awaiting 2nd vote')),
    el('span', { class: 'dash-card', style: (c.conflicts ? 'border-color:#c00' : '') }, el('b', {}, c.conflicts || 0), T(' em conflito', ' in conflict')));
}

// PAINEL DE AVALIAÇÃO (estável): enquanto o juiz avalia, a página NÃO recarrega — só o contador
// local roda. Mostra o veredicto computado em destaque + log/fonte + o select de voto.
function evalPanel(it) {
  const mine = (it.claimants || []).find(x => x.by === ME);
  const left = mine ? Math.max(0, mine.expires_in_s | 0) : 0;
  const cdEl = el('b', { id: 'rvCountdown' }, fmtLeft(left));
  const sel = el('select', {}, el('option', { value: '' }, T('-- escolha o veredicto --', '-- choose the verdict --')),
    ...OPTIONS.map(o => el('option', { value: o.label }, o.label)));
  const vb = el('button', { class: 'btn', type: 'button' }, T('✓ Votar e liberar', '✓ Vote and release'));
  const msg = el('span', { class: 'small' });
  vb.addEventListener('click', async () => {
    if (!sel.value) { msg.className = 'small error-box'; msg.textContent = T('Escolha um veredicto.', 'Choose a verdict.'); return; }
    vb.disabled = true; msg.className = 'small'; msg.textContent = T('Enviando…', 'Sending…');
    try { await rvAct('vote', { id: it.id, label: sel.value }); loadReview(); }   // reload → sai do painel
    catch (e) { vb.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
  });
  startTick(left);
  return el('div', { class: 'section', style: 'border:2px solid #0a7; background:#f4fff9' },
    el('h2', {}, T('⏳ Avaliando — Problema ', '⏳ Evaluating — Problem '), el('b', {}, shortOf(it.problem_id))),
    el('div', { class: 'row', style: 'gap:1rem; flex-wrap:wrap; align-items:center; margin:.3rem 0' },
      el('div', {}, el('span', { class: 'small muted' }, T('Veredicto computado (referência): ', 'Computed verdict (reference): ')),
        el('span', { class: 'verdict ' + verdictClass(it.computed_verdict), style: 'font-weight:700' }, it.computed_verdict || '?')),
      logLink(it), srcLink(it)),
    el('div', { class: 'row', style: 'gap:.5rem; align-items:center; margin:.5rem 0' },
      el('label', { class: 'small' }, T('Seu veredicto: ', 'Your verdict: ')), sel, vb, msg),
    el('div', { class: 'row', style: 'margin-top:.4rem; align-items:center; gap:.5rem' },
      el('span', { class: 'small muted' }, T('Tempo restante: ', 'Time left: ')), cdEl,
      el('button', { class: 'btn ghost', onclick: () => act('claim', it.id, 'extend') }, '+5 min'),
      el('button', { class: 'btn ghost', onclick: () => act('claim', it.id, 'giveup') }, T('Desistir', 'Give up'))),
    el('p', { class: 'small muted', style: 'margin-top:.4rem' }, T('A página não recarrega enquanto você avalia. Ao votar, sua tarefa encerra e libera você para a próxima.', 'The page does not reload while you evaluate. When you vote, your task ends and releases you for the next one.')));
}

function renderReview() {
  const box = document.getElementById('judgeContainer'); box.innerHTML = '';
  const items = rv.items || [], c = rv.counts || {};
  box.append(countsBar(c));

  // se tenho uma avaliação ATIVA: mostra só o painel estável (sem fila, sem poll)
  if (rv.my_active) {
    const it = items.find(x => x.id === rv.my_active);
    if (!it) { box.append(el('div', { class: 'muted' }, T('Sua avaliação ativa terminou — recarregando…', 'Your active evaluation ended — reloading…'))); return; }
    box.append(evalPanel(it));
    return;
  }

  // sem avaliação ativa: a FILA (com botão pegar). Aqui não há select, então o poll não atrapalha.
  if (!items.length) { box.append(el('div', { class: 'muted' }, T('Nenhuma submissão aguardando avaliação. 🎉', 'No submissions awaiting evaluation. 🎉'))); return; }
  const head = el('thead', {}, el('tr', {},
    el('th', {}, T('Problema', 'Problem')), el('th', {}, T('Veredicto computado', 'Computed verdict')), el('th', {}, T('Status', 'Status')),
    el('th', {}, T('Avaliando', 'Evaluating')), el('th', {}, T('Ver', 'View')), el('th', {}, T('Ação', 'Action'))));
  const tb = el('tbody');
  items.forEach((s) => {
    const full = (s.claimants || []).length >= 2;
    const voted = !!s.my_vote;
    const canClaim = !full && !voted && (s.votes_n || 0) < 2 && s.status !== 'released';
    const whoCell = (s.claimants || []).length
      ? el('div', { class: 'small' }, (s.claimants).map(x => x.by + ' (' + (x.elapsed_s | 0) + 's)').join(', '))
      : el('span', { class: 'small muted' }, (s.votes_n ? T('1º voto dado', '1st vote cast') : '—'));
    const actionCell = canClaim
      ? el('button', { class: 'btn', onclick: () => act('claim', s.id, 'claim') }, T('Pegar p/ avaliar', 'Claim to evaluate'))
      : el('span', { class: 'small muted' }, voted ? T('você já votou', 'you already voted') : (full ? T('lotada (2)', 'full (2)') : (s.conflict ? T('conflito', 'conflict') : '—')));
    tb.append(el('tr', {},
      el('td', {}, el('b', {}, shortOf(s.problem_id))),
      el('td', {}, el('span', { class: 'verdict ' + verdictClass(s.computed_verdict) }, s.computed_verdict || '?')),
      el('td', {}, el('span', { class: 'verdict ' + (s.conflict ? 'flag-anom' : '') }, s.status + (s.conflict ? ' ⚠' : ''))),
      el('td', {}, whoCell),
      el('td', {}, el('div', { class: 'row', style: 'gap:.4rem' }, logLink(s), srcLink(s))),
      el('td', {}, actionCell)));
  });
  box.append(el('table', { class: 'moj' }, head, tb));
  if (IS_CHIEF && (c.conflicts || 0) > 0) box.append(el('p', { class: 'small' },
    T('⚠ Há conflitos — resolva no ', '⚠ There are conflicts — resolve in the '), el('a', { href: '/contest/chief/?c=' + enc(CONTEST) }, T('painel do juiz-chefe', 'chief judge panel')), '.'));
}

function fmtLeft(s) { s = Math.max(0, s | 0); const m = Math.floor(s / 60), x = s % 60; return m + ':' + String(x).padStart(2, '0'); }
function startTick(left) { clearInterval(tickT); let n = left; const e = () => document.getElementById('rvCountdown'); tickT = setInterval(() => { n--; const el2 = e(); if (!el2) { clearInterval(tickT); return; } el2.textContent = fmtLeft(n); if (n <= 0) { clearInterval(tickT); loadReview(); } }, 1000); }
async function act(path, id, action) { try { await rvAct(path, { id, action }); loadReview(); } catch (e) { alert(e.message || T('falha', 'failed')); } }

async function loadReview() {
  try { rv = await apiGet('/contest/review/list?contest=' + enc(CONTEST), G); }
  catch (e) { document.getElementById('judgeContainer').innerHTML = '<div class="error-box">' + T('Falha ao carregar a fila.', 'Failed to load the queue.') + '</div>'; return; }
  OPTIONS = rv.options || []; IS_CHIEF = !!rv.is_chief;
  renderReview();
  // enquanto o juiz tem uma avaliação ativa, NÃO recarrega (o contador local roda; ações
  // como votar/desistir/+5min chamam loadReview; ao expirar, startTick chama loadReview).
  clearTimeout(pollT);
  if (!rv.my_active) pollT = setTimeout(loadReview, 6000 + Math.random() * 3000);
}

// ===================== MODO LEGADO (allsubmissions + set-verdict) =====================
function parseLine(line) { const v = line.split(':'); if (v.length < 7) return null;
  return { username: v[1], problem_id: v[2], lang: v[3], verdict: v[4], epoch: v[5], id: v[6], fullname: v[7] || '' }; }
function renderLegacy() {
  const box = document.getElementById('judgeContainer'); box.innerHTML = '';
  const fu = (document.getElementById('fUser') || {}).value || '', fp = (document.getElementById('fProblem') || {}).value || '';
  const onlyP = (document.getElementById('onlyPending') || {}).checked;
  const list = subs.filter(s => (!onlyP || isPending(s.verdict)) && (!fu || (s.username || '').toLowerCase().includes(fu.toLowerCase())) && (!fp || shortOf(s.problem_id).toLowerCase().includes(fp.toLowerCase())));
  if (!list.length) { box.innerHTML = '<span class="muted">' + T('Nenhuma submissão.', 'No submissions.') + '</span>'; return; }
  const head = el('thead', {}, el('tr', {}, el('th', {}, T('Quando', 'When')), el('th', {}, T('Usuário', 'User')), el('th', {}, T('Problema', 'Problem')), el('th', {}, T('Veredicto', 'Verdict')), el('th', {}, T('Veredicto final', 'Final verdict')), el('th', {}, T('Ver', 'View'))));
  const tb = el('tbody');
  list.forEach(s => {
    const sel = el('select', {}, el('option', { value: '' }, T('-- escolha --', '-- choose --')), ...finalVerdicts.map(v => el('option', { value: v }, v)));
    const btn = el('button', { class: 'btn', type: 'button', disabled: 'disabled' }, T('Enviar', 'Submit')); const msg = el('span', { class: 'submit-steps' });
    sel.addEventListener('change', () => { btn.disabled = !sel.value; });
    btn.addEventListener('click', async () => { btn.disabled = true; msg.textContent = T('Enviando…', 'Sending…');
      try { await apiPost('/contest/set-verdict?contest=' + enc(CONTEST), { problem_id: s.problem_id, verdict: sel.value, username: s.username }, G); msg.textContent = T('✓ Enviado!', '✓ Sent!'); }
      catch (e) { msg.innerHTML = '<span class="error-box">' + T('Erro: ', 'Error: ') + (e && e.message ? e.message : T('falha', 'failed')) + '</span>'; btn.disabled = false; } });
    tb.append(el('tr', {}, el('td', {}, el('span', { class: 'small' }, fmtDate(s.epoch))), el('td', {}, s.username || ''),
      el('td', {}, el('b', {}, shortOf(s.problem_id))),
      el('td', {}, el('span', { class: 'verdict ' + verdictClass(s.verdict) }, isPending(s.verdict) ? el('span', {}, el('span', { class: 'spin' }), ' ' + s.verdict) : s.verdict)),
      el('td', {}, sel, ' ', btn, ' ', msg),
      el('td', {}, el('div', { class: 'row', style: 'gap:.4rem' }, logLink({ id: s.id, sub_epoch: s.epoch }), srcLink({ id: s.id, sub_epoch: s.epoch, lang: s.lang })))));
  });
  box.append(el('table', { class: 'moj' }, head, tb));
}
async function loadLegacy() {
  let txt; try { txt = await apiGetText('/contest/allsubmissions?contest=' + enc(CONTEST), G); }
  catch { document.getElementById('judgeContainer').innerHTML = '<div class="notice">' + T('Feed completo requer perfil admin/juiz-chefe. (Contest sem veredicto manual.)', 'Full feed requires admin/chief-judge role. (Contest without manual verdict.)') + '</div>'; return; }
  subs = txt.split('\n').map(s => s.trim()).filter(Boolean).map(parseLine).filter(Boolean).sort((a, b) => Number(b.epoch) - Number(a.epoch));
  renderLegacy();
}

async function boot() {
  if (!CONTEST) { document.body.innerHTML = '<div class="container"><div class="error-box">' + T('Contest não informado (?c=).', 'Contest not specified (?c=).') + '</div></div>'; return; }
  let basic;
  try { basic = await apiGet('/contest/basic?contest=' + enc(CONTEST), {}); }
  catch { document.body.innerHTML = '<div class="container"><div class="error-box">' + T('Contest não encontrado.', 'Contest not found.') + '</div></div>'; return; }
  const st = await status(CONTEST);
  if (!st.logged_in) { location.href = '/contest/?c=' + enc(CONTEST); return; }
  if (!st.is_judge && !st.is_admin) { document.body.innerHTML = '<div class="container"><div class="notice">' + T('Acesso restrito a juízes.', 'Access restricted to judges.') + '</div></div>'; return; }
  ME = st.login || '';
  await mountChrome(CONTEST, basic, { auth: true });
  problems = (await apiGet('/contest/problems?contest=' + enc(CONTEST), G).catch(() => null)) || [];
  problems = Array.isArray(problems) ? problems : (problems.problems || []);

  // decide o modo pela fila de revisão (manual?) — funciona p/ juiz PURO (review/list é judge)
  let probe = null;
  try { probe = await apiGet('/contest/review/list?contest=' + enc(CONTEST), G); } catch { /* ignore */ }
  if (probe && probe.manual) {
    REVIEW = true; rv = probe; OPTIONS = rv.options || []; IS_CHIEF = !!rv.is_chief;
    const fb = document.getElementById('judgeFilters'); if (fb) fb.style.display = 'none';
    const rb = document.getElementById('refreshBtn'); if (rb) rb.addEventListener('click', loadReview);
    renderReview();
    clearTimeout(pollT); pollT = setTimeout(loadReview, 6000 + Math.random() * 3000);
  } else if (!st.is_admin && !st.is_chief) {
    // contest SEM veredicto manual: o juiz puro não tem fila de avaliação (veredictos automáticos)
    document.getElementById('judgeContainer').innerHTML =
      '<div class="notice">' + T('Este contest não usa <b>veredicto manual</b> — as correções são automáticas, não há fila para avaliar. (O administrador pode ligar o modo manual em Configurações; a lista completa de submissões é do admin/juiz-chefe.)',
        'This contest does not use <b>manual verdict</b> — corrections are automatic, there is no queue to evaluate. (The administrator can turn on manual mode in Settings; the full submission list is for admin/chief-judge.)') + '</div>';
  } else {
    const fv = await apiGet('/contest/final-verdicts?contest=' + enc(CONTEST), G).catch(() => null);
    finalVerdicts = fv ? (fv.verdicts || []) : [];
    ['fUser', 'fProblem'].forEach(id => { const e = document.getElementById(id); if (e) e.addEventListener('input', renderLegacy); });
    const op = document.getElementById('onlyPending'); if (op) op.addEventListener('change', renderLegacy);
    const rb = document.getElementById('refreshBtn'); if (rb) rb.addEventListener('click', loadLegacy);
    await loadLegacy();
  }
}
boot();
