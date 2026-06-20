// contest/admin/admin.js — admin DO contest: reedita aparência/placar e usuários.
// Reusa os mesmos editores da criação (web/shared/contest-config). Requer login .admin no contest.
import { apiGet, apiPost } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { makeColorsEditor, makeTeamsEditor, makeRegionsEditor, makeBasicEditor } from '/shared/contest-config/index.js';

const qs = new URLSearchParams(location.search);
const CONTEST = qs.get('c') || '';
const app = document.getElementById('app');
const G = { contest: CONTEST, auth: true };
const enc = encodeURIComponent;

document.getElementById('backLink').href = '/contest/?c=' + enc(CONTEST);
document.getElementById('scoreLink').href = '/contest/score/?c=' + enc(CONTEST);

async function buildConfig(cfg) {
  const colorsEd = makeColorsEditor({ letters: cfg.letters || [], initial: cfg.colors || {} });
  const regionsEd = makeRegionsEditor({ initial: cfg.regions || [] });
  const basicEd = makeBasicEditor({ initial: cfg.basic || {} });
  const teamsEd = await makeTeamsEditor({ initial: cfg.teams_meta || [] });
  const msg = el('div', { class: 'small', style: 'margin:.5rem 0' });
  const save = el('button', { class: 'btn' }, 'Salvar aparência');
  save.addEventListener('click', async () => {
    save.disabled = true; msg.className = 'small'; msg.textContent = 'Salvando…';
    const payload = { colors: colorsEd.getValue(), regions: regionsEd.getValue(), teams_meta: teamsEd.getValue(), basic: basicEd.getValue() };
    try { await apiPost('/contest/admin/config?contest=' + enc(CONTEST), payload, G); msg.className = 'small'; msg.textContent = '✓ salvo'; save.disabled = false; }
    catch (e) { save.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || 'falha'; }
  });
  const hh = (t) => el('h3', { style: 'margin:1rem 0 .3rem' }, t);
  return el('div', { class: 'section' },
    el('h2', {}, '🎨 Aparência e placar'),
    el('p', { class: 'muted small' }, 'Contest "' + (cfg.name || CONTEST) + '" · modo ' + (cfg.mode || '?') + '. Bandeiras locais (offline).'),
    hh('🎈 Cores dos balões'), colorsEd.el,
    hh('🏳️ Países e escolas (bandeira/sigla por regex no login)'), teamsEd.el,
    hh('🔎 Filtros de região'), regionsEd.el,
    hh('⚙️ Configurações básicas'), basicEd.el,
    el('div', { class: 'row', style: 'margin-top:.7rem' }, save, msg));
}

function buildUsers() {
  const box = el('div', { class: 'section' }, el('h2', {}, '👥 Usuários do contest'));
  const list = el('div', {}, el('p', { class: 'muted small' }, 'carregando…'));
  async function load() {
    list.innerHTML = ''; let r;
    try { r = await apiGet('/contest/admin/users?contest=' + enc(CONTEST), G); }
    catch { list.append(el('div', { class: 'error-box' }, 'Falha ao carregar usuários.')); return; }
    if (r.shared) list.append(el('div', { class: 'small muted', style: 'margin-bottom:.4rem' },
      'Usuários compartilhados de "' + r.shared + '" — apenas o admin é próprio deste contest.'));
    const tb = el('tbody');
    (r.users || []).forEach((u) => {
      const rm = el('button', { class: 'btn danger', onclick: async () => {
        if (!confirm('Remover ' + u.login + '?')) return;
        try { await apiPost('/contest/admin/user-remove?contest=' + enc(CONTEST), { login: u.login }, G); load(); }
        catch (e) { alert(e.message || 'falha'); }
      } }, 'remover');
      tb.append(el('tr', {},
        el('td', {}, u.login, u.admin ? el('span', { class: 'small muted' }, ' (admin)') : ''),
        el('td', {}, u.fullname || ''), el('td', { class: 'small' }, u.email || ''), el('td', {}, rm)));
    });
    list.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, 'Login'), el('th', {}, 'Nome'), el('th', {}, 'Email'), el('th', {}, ''))), tb)));
  }
  load();
  const li = el('input', { placeholder: 'login' }), pw = el('input', { placeholder: 'senha (gerada se vazio)' });
  const fn = el('input', { placeholder: 'nome' }), em = el('input', { placeholder: 'email (opcional)' });
  const amsg = el('div', { class: 'small' });
  const add = el('button', { class: 'btn' }, 'Adicionar / resetar senha');
  add.addEventListener('click', async () => {
    if (!li.value.trim()) { li.focus(); return; }
    add.disabled = true; amsg.className = 'small'; amsg.textContent = 'Salvando…';
    try {
      const r = await apiPost('/contest/admin/user-add?contest=' + enc(CONTEST),
        { login: li.value.trim(), password: pw.value.trim() || undefined, fullname: fn.value.trim() || undefined, email: em.value.trim() || undefined }, G);
      amsg.className = 'small'; amsg.innerHTML = ''; amsg.append('✓ ' + r.user.login + ' · senha: ', el('span', { class: 'cred' }, r.user.password));
      add.disabled = false; li.value = pw.value = fn.value = em.value = ''; load();
    } catch (e) { add.disabled = false; amsg.className = 'small error-box'; amsg.textContent = e.message || 'falha'; }
  });
  box.append(list, el('h3', { style: 'margin:1rem 0 .3rem' }, 'Adicionar usuário ou resetar senha'),
    el('div', { class: 'row' }, li, pw, fn, em, add), amsg);
  return box;
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">Contest não informado (use ?c=&lt;id&gt;).</div>'; return; }
  let st;
  try { st = await apiGet('/auth/status?contest=' + enc(CONTEST), G); } catch { st = null; }
  if (!st || !st.logged_in || !st.is_admin) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' },
      el('h2', {}, '🔒 Acesso restrito'),
      el('p', { class: 'muted' }, 'Entre como administrador deste contest para configurá-lo.'),
      el('a', { class: 'btn', href: '/contest/login/?c=' + enc(CONTEST) }, 'Login do contest')));
    return;
  }
  document.getElementById('ctitle').textContent = 'Admin · ' + (st.contest || CONTEST);
  let cfg;
  try { cfg = await apiGet('/contest/admin/config?contest=' + enc(CONTEST), G); }
  catch (e) { app.innerHTML = ''; app.append(el('div', { class: 'error-box' }, 'Falha ao carregar config: ' + (e.message || 'erro'))); return; }
  app.innerHTML = '';
  app.append(await buildConfig(cfg), buildUsers());
}

boot();
