// contest/log/log.js — Log & sessões do contest (admin DO contest): sessões ativas com
// alerta de UA/IP diferentes, e o log de acessos por dia.
import { apiGet } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { initContestShell } from '/shared/contest-shell.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const enc = encodeURIComponent;
const G = { contest: CONTEST, auth: true };
const pad2 = (n) => String(n).padStart(2, '0');
const fmtDate = (e) => new Date((+e || 0) * 1000).toLocaleString('pt-BR');
const todayStr = () => { const d = new Date(); return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()); };

function sessionsSection() {
  const box = el('div', { class: 'section' }, el('h2', {}, '👥 Sessões ativas'),
    el('div', {}, el('button', { class: 'btn ghost', onclick: () => load() }, '↻ Atualizar')));
  const body = el('div', {}, el('p', { class: 'muted small' }, 'carregando…'));
  box.append(body);
  async function load() {
    body.innerHTML = ''; let r;
    try { r = await apiGet('/contest/admin/sessions?contest=' + enc(CONTEST), G); }
    catch (e) { body.append(el('div', { class: 'error-box' }, 'Falha: ' + (e.message || 'erro'))); return; }
    (r.alerts || []).forEach((a) => body.append(el('div', { class: 'alert' },
      '⚠ ' + a.login + ' está logado de ' + [a.multi_ip && 'IPs diferentes', a.multi_ua && 'navegadores/máquinas diferentes'].filter(Boolean).join(' e ') + '.')));
    body.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, (r.count || 0) + ' sessão(ões) ativa(s).'));
    const tb = el('tbody');
    (r.sessions || []).forEach((s) => {
      const anom = s.multi_ip || s.multi_ua;
      tb.append(el('tr', {},
        el('td', {}, el('span', { class: anom ? 'flag-anom' : '' }, (anom ? '⚠ ' : '') + s.login)),
        el('td', {}, s.name || ''),
        el('td', { class: 'ip' + (s.multi_ip ? ' flag-anom' : '') }, s.ip || ''),
        el('td', { class: 'ua' + (s.multi_ua ? ' flag-anom' : '') }, s.user_agent || ''),
        el('td', { class: 'small' }, fmtDate(s.login_at))));
    });
    body.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, 'Login'), el('th', {}, 'Nome'), el('th', {}, 'IP'), el('th', {}, 'Navegador (UA)'), el('th', {}, 'Login em'))), tb)));
  }
  load();
  return box;
}

function accessSection() {
  const box = el('div', { class: 'section' }, el('h2', {}, '📝 Log de acessos'));
  const dateInp = el('input', { type: 'date', value: todayStr() });
  dateInp.addEventListener('change', () => load());
  box.append(el('div', { class: 'row', style: 'margin-bottom:.4rem' },
    el('span', { class: 'small muted' }, 'Dia:'), dateInp, el('button', { class: 'btn ghost', onclick: () => load() }, '↻')));
  const body = el('div', {}, el('p', { class: 'muted small' }, 'carregando…'));
  box.append(body);
  async function load() {
    body.innerHTML = ''; let r;
    try { r = await apiGet('/contest/admin/access-log?contest=' + enc(CONTEST) + '&day=' + enc(dateInp.value), G); }
    catch { body.append(el('div', { class: 'error-box' }, 'Falha ao carregar.')); return; }
    (r.alerts || []).forEach((a) => body.append(el('div', { class: 'alert' },
      '⚠ ' + a.login + ' acessou de ' + [a.multi_ip && 'IPs', a.multi_ua && 'navegadores'].filter(Boolean).join('/') + ' diferentes.')));
    const e2 = r.entries || [];
    body.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, e2.length + ' acesso(s).'));
    if (!e2.length) { body.append(el('div', { class: 'muted' }, 'Sem acessos neste dia.')); return; }
    const tb = el('tbody');
    e2.forEach((x) => tb.append(el('tr', {},
      el('td', { class: 'small' }, fmtDate(x.time)), el('td', {}, x.login || ''),
      el('td', { class: 'ip' }, x.ip || ''), el('td', { class: 'ua' }, x.user_agent || ''))));
    body.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, 'Data/Hora'), el('th', {}, 'Login'), el('th', {}, 'IP'), el('th', {}, 'Navegador (UA)'))), tb)));
  }
  load();
  return box;
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">Contest não informado.</div>'; return; }
  const { st } = await initContestShell(CONTEST);
  if (!st || !st.logged_in || !st.is_admin) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, '🔒 Acesso restrito'),
      el('p', { class: 'muted' }, 'Apenas o admin do contest pode ver o log.'),
      el('a', { class: 'btn', href: '/contest/login/?c=' + enc(CONTEST) }, 'Login do contest')));
    return;
  }
  app.innerHTML = '';
  app.append(sessionsSection(), accessSection());
}
boot();
