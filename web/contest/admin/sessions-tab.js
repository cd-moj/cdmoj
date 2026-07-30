// contest/admin/sessions-tab.js — "Pessoas › Sessões": quem está logado agora (com alerta de
// multi-IP/multi-UA = possível conta emprestada), o botão que desloga quem está fora da imagem
// da sede (gate de UA) e o log de acessos por dia. Tudo com CSV para auditoria externa.
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { fmtDate, todayStr, stamp, toCsv, downloadText } from '/shared/admin-ui.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;

export function makeSessionsTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div', {});

  async function load() {
    panel.innerHTML = '';
    // ---- sessões ativas ----
    const sBox = el('div', { class: 'section' }, el('h2', {}, T('🖥 Sessões ativas', '🖥 Active sessions')));
    const uaFilter = el('input', { type: 'search', placeholder: T('filtrar por UA / login / IP…', 'filter by UA / login / IP…'), style: 'min-width:220px' });
    const sBody = el('div', {});
    let SESS = [];
    function renderSessions() {
      sBody.innerHTML = '';
      const f = uaFilter.value.trim().toLowerCase();
      const items = SESS.filter((s) => !f || (s.user_agent || '').toLowerCase().includes(f) || (s.login || '').toLowerCase().includes(f) || (s.ip || '').toLowerCase().includes(f));
      const tb = el('tbody');
      items.forEach((s) => {
        const anom = s.multi_ip || s.multi_ua;
        tb.append(el('tr', {},
          el('td', {}, el('span', { class: anom ? 'flag-anom' : '' }, (anom ? '⚠ ' : '') + s.login)),
          el('td', { class: 'ip' + (s.multi_ip ? ' flag-anom' : '') }, s.ip || ''),
          el('td', { class: 'ua' + (s.multi_ua ? ' flag-anom' : '') }, s.user_agent || ''),
          el('td', { class: 'small' }, fmtDate(s.login_at)),
          el('td', {}, el('button', { class: 'btn ghost', onclick: async () => { try { await apiPost('/contest/admin/logout-user?contest=' + enc(CONTEST), { login: s.login }, G); loadSessions(); } catch (e) { alert(e.message); } } }, T('deslogar', 'log out')))));
      });
      sBody.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, items.length + T(' de ', ' of ') + SESS.length + T(' sessão(ões).', ' session(s).')),
        el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' }, el('thead', {}, el('tr', {}, el('th', {}, 'Login'), el('th', {}, 'IP'), el('th', {}, T('Navegador (UA)', 'Browser (UA)')), el('th', {}, T('Login em', 'Logged in at')), el('th', {}, ''))), tb)));
    }
    async function loadSessions() {
      let r; try { r = await apiGet('/contest/admin/sessions?contest=' + enc(CONTEST), G); }
      catch { sBody.innerHTML = ''; sBody.append(el('div', { class: 'error-box' }, T('Falha.', 'Failed.'))); return; }
      sBox.querySelectorAll('.alert').forEach((n) => n.remove());
      (r.alerts || []).forEach((a) => sBox.insertBefore(el('div', { class: 'alert' }, '⚠ ' + a.login + T(' está logado de ', ' is logged in from ') + [a.multi_ip && T('IPs diferentes', 'different IPs'), a.multi_ua && T('navegadores/máquinas diferentes', 'different browsers/machines')].filter(Boolean).join(T(' e ', ' and ')) + '.'), sBody));
      SESS = r.sessions || []; renderSessions();
    }
    uaFilter.addEventListener('input', renderSessions);
    const mismatchBtn = el('button', { class: 'btn danger', title: T('compara cada sessão com o UA esperado da sede daquele time', 'compares each session with the expected UA of that team\'s site'),
      onclick: async () => {
        if (!confirm(T('Deslogar todas as sessões cujo UA não bate o esperado?', 'Log out all sessions whose UA does not match the expected one?'))) return;
        try { const r = await apiPost('/contest/admin/logout-mismatch?contest=' + enc(CONTEST), {}, G); alert(r.sessions_removed + T(' sessão(ões) encerradas.', ' session(s) ended.')); loadSessions(); }
        catch (e) { alert(e.message || T('falha', 'failed')); }
      } }, T('Deslogar UA divergente', 'Log out mismatched UA'));
    const dlSess = el('button', { class: 'btn ghost', title: T('Baixar sessões (CSV)', 'Download sessions (CSV)'), onclick: () => {
      const rows = [['login', 'ip', 'user_agent', 'login_at', 'login_iso', 'multi_ip', 'multi_ua'],
        ...SESS.map((s) => [s.login || '', s.ip || '', s.user_agent || '', s.login_at || '', new Date((s.login_at || 0) * 1000).toISOString(), !!s.multi_ip, !!s.multi_ua])];
      downloadText('sessoes-' + CONTEST + '-' + stamp() + '.csv', toCsv(rows), 'text/csv');
    } }, '⬇ CSV');
    sBox.append(el('div', { class: 'row', style: 'margin:.3rem 0' }, uaFilter, el('button', { class: 'btn ghost', onclick: () => loadSessions() }, '↻'), mismatchBtn, dlSess), sBody);

    // ---- log de acessos ----
    const aBox = el('div', { class: 'section' }, el('h2', {}, T('📝 Log de acessos', '📝 Access log')));
    const dateInp = el('input', { type: 'date', value: todayStr() });
    const aBody = el('div', {});
    let ACC = [];
    const dlAcc = el('button', { class: 'btn ghost', title: T('Baixar acessos do dia (CSV)', 'Download the day\'s accesses (CSV)'), onclick: () => {
      const rows = [['epoch', 'datahora', 'login', 'ip', 'user_agent'],
        ...ACC.map((x) => [x.time, new Date((x.time || 0) * 1000).toISOString(), x.login || '', x.ip || '', x.user_agent || ''])];
      downloadText('acessos-' + CONTEST + '-' + (dateInp.value || stamp()) + '.csv', toCsv(rows), 'text/csv');
    } }, '⬇ CSV');
    async function loadAccess() {
      aBody.innerHTML = ''; let r;
      try { r = await apiGet('/contest/admin/access-log?contest=' + enc(CONTEST) + '&day=' + enc(dateInp.value), G); }
      catch { aBody.append(el('div', { class: 'error-box' }, T('Falha.', 'Failed.'))); return; }
      const e2 = r.entries || []; ACC = e2;
      aBody.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, e2.length + T(' acesso(s).', ' access(es).')));
      if (!e2.length) { aBody.append(el('div', { class: 'muted' }, T('Sem acessos.', 'No accesses.'))); return; }
      const tb = el('tbody');
      e2.forEach((x) => tb.append(el('tr', {}, el('td', { class: 'small' }, fmtDate(x.time)), el('td', {}, x.login || ''), el('td', { class: 'ip' }, x.ip || ''), el('td', { class: 'ua' }, x.user_agent || ''))));
      aBody.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' }, el('thead', {}, el('tr', {}, el('th', {}, T('Data/Hora', 'Date/Time')), el('th', {}, 'Login'), el('th', {}, 'IP'), el('th', {}, T('Navegador (UA)', 'Browser (UA)')))), tb)));
    }
    dateInp.addEventListener('change', loadAccess);
    aBox.append(el('div', { class: 'row', style: 'margin-bottom:.4rem' }, el('span', { class: 'small muted' }, T('Dia:', 'Day:')), dateInp, el('button', { class: 'btn ghost', onclick: () => loadAccess() }, '↻'), dlAcc), aBody);

    panel.append(sBox, aBox);
    await loadSessions(); await loadAccess();
  }
  return { panel, load };
}
