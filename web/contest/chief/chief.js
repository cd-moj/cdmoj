// contest/chief/chief.js — hub do juiz-chefe (.cjudge) e do admin: Situação da avaliação,
// resolução de Conflitos (com alerta vibrante), e a config do veredicto manual (opções + matriz).
import { apiGet, apiPost } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { initContestShell } from '/shared/contest-shell.js';
import { pokeChiefAlert } from '/shared/chief-alert.js';
import { logLink, srcLink } from '/shared/submission-links.js';
import { makeVerdictOptionsEditor, makeAutoVerdictEditor } from '/shared/contest-config/verdict-config.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const enc = encodeURIComponent;
const G = { contest: CONTEST, auth: true };
const fmtS = (s) => { s = Math.max(0, s | 0); const m = Math.floor(s / 60); return m ? m + 'm' + (s % 60) + 's' : s + 's'; };
let confPoll = null, confOptions = [];

// O alerta GLOBAL de conflito (banner flutuante + bip, visível em qualquer página) vive em
// shared/chief-alert.js e é iniciado pelo initContestShell. Aqui só renderizamos a lista de
// conflitos e "cutucamos" o alerta (pokeChiefAlert) após resolver, p/ sumir na hora.

// ===================== abas =====================
function situacaoTab() {
  const panel = el('div', { class: 'section' });
  async function load() {
    panel.innerHTML = ''; panel.append(el('h2', {}, '📊 Situação da avaliação'));
    let d, s;
    try { [d, s] = await Promise.all([apiGet('/contest/admin/dashboard?contest=' + enc(CONTEST), G),
      apiGet('/contest/review/stats?contest=' + enc(CONTEST), G).catch(() => null)]); }
    catch (e) { panel.append(el('div', { class: 'error-box' }, 'Falha: ' + (e.message || 'erro'))); return; }
    const r = d.review || {};
    panel.append(el('div', { class: 'row', style: 'flex-wrap:wrap; margin:.3rem 0' },
      el('span', { class: 'dash-card' }, el('b', {}, r.not_evaluated || 0), ' não avaliadas'),
      el('span', { class: 'dash-card' }, el('b', {}, r.being_evaluated || 0), ' sendo avaliadas'),
      el('span', { class: 'dash-card' }, el('b', {}, r.awaiting_second || 0), ' aguardando 2º voto'),
      el('span', { class: 'dash-card', style: (r.conflicts ? 'border-color:#c00;color:#c00' : '') }, el('b', {}, r.conflicts || 0), ' em conflito'),
      el('span', { class: 'dash-card' }, el('b', {}, (d.judges || {}).online || 0), ' juízes online')));
    // quem está avaliando agora
    const ev = r.evaluators || [];
    panel.append(el('h3', {}, 'Em avaliação / conflito agora'));
    if (!ev.length) { panel.append(el('p', { class: 'muted small' }, 'Ninguém avaliando no momento.')); }
    else {
      const tb = el('tbody');
      ev.forEach(e => tb.append(el('tr', {},
        el('td', {}, el('b', {}, (e.problem_id || '').split('#').pop())),
        el('td', { class: 'small' }, e.computed_verdict || ''),
        el('td', {}, e.conflict ? el('b', { style: 'color:#c00' }, 'conflito') : (e.status || '')),
        el('td', { class: 'small' }, (e.claimants || []).map(c => c.judge + ' (' + fmtS(c.elapsed_s) + ')').join(', ') || (e.votes_n ? '1º voto dado' : '—')))));
      panel.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, 'Problema'), el('th', {}, 'Computado'), el('th', {}, 'Status'), el('th', {}, 'Avaliando (tempo)'))), tb)));
    }
    // desempenho por juiz (do log de auditoria)
    const js = (s && s.judges) || [], tot = (s && s.total) || {};
    panel.append(el('h3', { style: 'margin-top:.8rem' }, '📈 Desempenho por juiz'));
    if (!js.length) { panel.append(el('p', { class: 'muted small' }, 'Sem veredictos manuais ainda.')); }
    else {
      const stb = el('tbody');
      js.forEach(j => stb.append(el('tr', {},
        el('td', {}, el('b', {}, j.judge)),
        el('td', {}, j.votes),
        el('td', { class: 'small' }, fmtS(j.avg_response_s) + (j.timed < j.votes ? ' · ' + j.timed + '/' + j.votes + ' medidos' : '')),
        el('td', {}, j.agreements),
        el('td', { style: (j.conflicts ? 'color:#c00' : '') }, j.conflicts))));
      panel.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, 'Juiz'), el('th', {}, 'Veredictos'), el('th', {}, 'Tempo médio (claim→voto)'), el('th', {}, 'Concordâncias'), el('th', {}, 'Conflitos'))), stb)),
        el('p', { class: 'small muted' }, 'Total: ' + (tot.votes || 0) + ' veredicto(s) · tempo médio geral ' + fmtS(tot.avg_response_s || 0) + '.'));
    }
  }
  return { panel, load, live: true };
}

function conflitosTab() {
  const panel = el('div', { class: 'section' });
  async function render(list) {
    panel.innerHTML = ''; panel.append(el('h2', {}, '⚖️ Conflitos de veredicto'));
    if (!list.length) { panel.append(el('p', { class: 'muted' }, 'Nenhum conflito. 🎉')); return; }
    list.forEach(cf => {
      const sel = el('select', {}, el('option', { value: '' }, '-- veredicto final --'), ...confOptions.map(o => el('option', { value: o.label }, o.label)));
      const btn = el('button', { class: 'btn' }, 'Resolver'); const msg = el('span', { class: 'small' });
      btn.addEventListener('click', async () => { if (!sel.value) return; btn.disabled = true; msg.textContent = 'Enviando…';
        try { await apiPost('/contest/review/resolve?contest=' + enc(CONTEST), { id: cf.id, verdict: sel.value }, G); loadConflicts(); pokeChiefAlert(); }
        catch (e) { btn.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || 'falha'; } });
      const votes = el('ul', { style: 'margin:.2rem 0 .3rem 1rem' }, ...(cf.votes || []).map(v => el('li', { class: 'small' }, el('b', {}, v.by), ' → ', v.label, ' (', v.verdict, ')')));
      panel.append(el('div', { class: 'field', style: 'border:1px solid #c0392b; border-radius:.5rem; padding:.5rem .7rem; margin:.4rem 0' },
        el('div', {}, el('b', {}, (cf.problem_id || '').split('#').pop()), ' · ', el('span', { class: 'small muted' }, cf.login || ''),
          ' · computado: ', el('span', { class: 'small muted' }, cf.computed_verdict || '')),
        el('div', { class: 'row small', style: 'gap:.7rem; margin:.2rem 0' }, logLink(CONTEST, cf), srcLink(CONTEST, cf)),
        votes, el('div', { class: 'row' }, sel, btn, msg)));
    });
  }
  async function loadConflicts() {
    let r; try { r = await apiGet('/contest/review/conflicts?contest=' + enc(CONTEST), G); } catch { return; }
    confOptions = r.options || confOptions;
    render(r.conflicts || []);
  }
  function load() { loadConflicts(); clearTimeout(confPoll); const tick = () => { if (!panel.hidden) loadConflicts(); confPoll = setTimeout(tick, 6000 + Math.random() * 3000); }; confPoll = setTimeout(tick, 6000); }
  return { panel, load };
}

function optionsTab() { const panel = el('div', {}); function load() { panel.innerHTML = ''; panel.append(makeVerdictOptionsEditor(CONTEST)); } return { panel, load }; }
function autoTab() { const panel = el('div', {}); function load() { panel.innerHTML = ''; panel.append(makeAutoVerdictEditor(CONTEST)); } return { panel, load }; }

const TABS = [
  { id: 'sit', label: '📊 Situação', make: situacaoTab },
  { id: 'conf', label: '⚖️ Conflitos', make: conflitosTab },
  { id: 'opts', label: '🏷️ Opções', make: optionsTab },
  { id: 'auto', label: '⚙️ Auto-veredicto', make: autoTab },
];

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">Contest não informado.</div>'; return; }
  const { st } = await initContestShell(CONTEST);
  if (!st || !st.logged_in) { app.innerHTML = ''; app.append(el('div', { class: 'section' }, el('h2', {}, '🔒 Entre no contest'), el('a', { class: 'btn', href: '/contest/?c=' + enc(CONTEST) }, 'Ir para o contest'))); return; }
  if (!st.is_chief && !st.is_admin) { app.innerHTML = ''; app.append(el('div', { class: 'section' }, el('h2', {}, '🔒 Acesso restrito'), el('p', { class: 'muted' }, 'Área do juiz-chefe (.cjudge) e do admin.'))); return; }
  app.innerHTML = '';
  const tabbar = el('div', { class: 'tabbar' }), wrap = el('div', {});
  app.append(tabbar, wrap);
  const built = {}, btn = {};
  async function show(id) {
    TABS.forEach(t => { if (built[t.id]) built[t.id].panel.hidden = (t.id !== id); btn[t.id].classList.toggle('active', t.id === id); });
    if (!built[id]) { const t = TABS.find(x => x.id === id); const inst = t.make(); built[id] = inst; wrap.append(inst.panel); if (inst.load) await inst.load(); if (inst.live) { clearInterval(inst._t); inst._t = setInterval(() => { if (!inst.panel.hidden) inst.load(); }, 12000); } }
    history.replaceState(null, '', location.pathname + '?c=' + enc(CONTEST) + '#' + id);
  }
  TABS.forEach(t => { btn[t.id] = el('button', { onclick: () => show(t.id) }, t.label); tabbar.append(btn[t.id]); });
  // o banner global (shared/chief-alert.js) pede esta aba ao ser clicado, mesmo já estando aqui
  window.addEventListener('moj:show-conflicts', () => show('conf'));
  const want = (location.hash || '').replace('#', '');
  show(TABS.some(t => t.id === want) ? want : 'sit');
}
boot();
