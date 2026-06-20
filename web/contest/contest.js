// contest/contest.js — entrada do contest: login full-screen (não logado) OU página
// principal (logado). Lê ?c=<contestId> da URL. Reusa shared/* e a API v1 real.
import { apiGet, apiGetText, apiPost, getToken } from '/shared/api.js';
import { login, logout, status, fileToBase64, textToBase64 } from '/shared/auth.js';
import { el, verdictClass, isPending, fmtDate } from '/shared/ui.js';
import { createEditor } from '/shared/editor.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const LANGS = [ // [editorLang, label, ext]
  ['c', 'C', 'c'], ['cpp', 'C++', 'cpp'], ['python', 'Python', 'py'],
  ['java', 'Java', 'java'], ['rust', 'Rust', 'rs'], ['javascript', 'JavaScript', 'js'],
];

let LOCALE = 'pt';
let basic = null;
let problems = [];
let balloons = {};
let userinfo = null;
let submissions = [];
let subFilter = 'ALL';
let sortField = 'epoch', sortAsc = false;
let pollTimer = null;
let loginCountdownTimer = null, loginPollTimer = null;

const T = (pt, en) => (LOCALE === 'en' ? en : pt);

// ---- helpers ---------------------------------------------------------------
function b64utf8(b64) {
  try {
    const bin = atob(b64 || '');
    return new TextDecoder('utf-8').decode(Uint8Array.from(bin, c => c.charCodeAt(0)));
  } catch { return ''; }
}
function fmtLeft(sec) {
  if (sec < 0) sec = 0;
  const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
  const p = (x) => String(x).padStart(2, '0');
  return h > 0 ? `${p(h)}:${p(m)}:${p(s)}` : `${p(m)}:${p(s)}`;
}
function show(id) { document.getElementById(id).classList.remove('hidden'); }
function hide(id) { document.getElementById(id).classList.add('hidden'); }

// normaliza verdict (para classe de cor e ordenação)
function vClass(v) { return verdictClass(v); }

// cor do balão para um short_name (mapa hex SEM '#')
function balloonColor(shortName) {
  const c = balloons && balloons[shortName];
  if (!c) return '';
  const hex = typeof c === 'string' ? c : c.hex;
  return hex ? (hex.startsWith('#') ? hex : '#' + hex) : '';
}
function balloonIsDark(hex) {
  hex = hex.replace('#', '');
  if (hex.length === 3) hex = hex.split('').map(x => x + x).join('');
  const r = parseInt(hex.substr(0, 2), 16), g = parseInt(hex.substr(2, 2), 16), b = parseInt(hex.substr(4, 2), 16);
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255 < 0.5;
}
function balloonSVG(color) {
  return `<svg class="balloon-svg" viewBox="0 0 42 47" aria-hidden="true">
    <ellipse cx="21" cy="21" rx="18" ry="18" fill="${color}" stroke="#b2b2b2" stroke-width="2"/>
    <ellipse cx="16" cy="14" rx="5" ry="5.1" fill="#fff" fill-opacity=".48"/>
    <polygon points="18,36 24,36 21,46" fill="${color}" stroke="#b2b2b2" stroke-width="1.4" stroke-linejoin="round"/>
    <ellipse cx="14" cy="15" rx="1.4" ry="2.8" fill="#fff" fill-opacity=".30"/>
    <ellipse cx="12" cy="22" rx="1.1" ry="1.5" fill="#fff" fill-opacity=".22"/>
  </svg>`;
}

async function downloadAuthed(path, filename) {
  try {
    const r = await fetch('/api/v1' + path, { headers: { 'Authorization': 'Bearer ' + getToken(CONTEST) } });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const blob = await r.blob();
    const a = el('a', { href: URL.createObjectURL(blob), download: filename });
    document.body.append(a); a.click(); a.remove();
  } catch { alert(T('Falha ao baixar arquivo/log.', 'Failed to download file/log.')); }
}
async function openLogAuthed(path) {
  try {
    const r = await fetch('/api/v1' + path, { headers: { 'Authorization': 'Bearer ' + getToken(CONTEST) } });
    const txt = await r.text();
    const w = window.open();
    const pre = w.document.createElement('pre');
    pre.style.cssText = 'font-family:monospace;white-space:pre-wrap;padding:1rem';
    pre.textContent = txt;
    w.document.body.append(pre);
    w.document.close();
  } catch { alert(T('Falha ao abrir o log.', 'Failed to open log.')); }
}

// ============================================================================
// LOGIN FULL-SCREEN
// ============================================================================
function renderLoginStatic() {
  document.title = (basic.contest_name || 'Contest') + ' — MOJ';
  document.getElementById('loginContestName').textContent = basic.contest_name || 'Contest';
  document.getElementById('loginTimes').innerHTML =
    T(`Início: ${fmtDate(basic.start_time)}<br>Término: ${fmtDate(basic.end_time)}`,
      `Start: ${fmtDate(basic.start_time)}<br>End: ${fmtDate(basic.end_time)}`);
  document.getElementById('loginUserLbl').textContent = T('Usuário', 'Username');
  document.getElementById('loginPassLbl').textContent = T('Senha', 'Password');
  document.getElementById('loginBtn').textContent = T('Entrar', 'Log in');
  document.getElementById('loginCountdownLbl').textContent = T('Abertura em', 'Opens in');
}

function updateLoginCountdown() {
  clearTimeout(loginCountdownTimer);
  const now = Math.floor(Date.now() / 1000);
  const loginStart = basic.login_start_time != null ? basic.login_start_time : basic.start_time;
  const left = loginStart - now;
  const box = document.getElementById('loginCountdown');
  const form = document.getElementById('loginForm');
  if (left > 0) {
    box.classList.remove('hidden');
    form.classList.add('hidden');
    document.getElementById('loginCountdownTime').textContent = fmtLeft(left);
    loginCountdownTimer = setTimeout(updateLoginCountdown, 1000);
  } else {
    box.classList.add('hidden');
    form.classList.remove('hidden');
  }
}

// repolla basic para detectar mudança de login_start_time (admin pode adiar/antecipar)
function scheduleLoginPoll() {
  clearTimeout(loginPollTimer);
  loginPollTimer = setTimeout(async () => {
    try {
      const fresh = await apiGet('/contest/basic?contest=' + encodeURIComponent(CONTEST), {});
      basic = fresh; LOCALE = basic.locale || 'pt';
      renderLoginStatic();
      updateLoginCountdown();
    } catch {}
    scheduleLoginPoll();
  }, 15000);
}

function bootLogin() {
  show('loginView');
  hide('mainView');
  renderLoginStatic();
  updateLoginCountdown();
  scheduleLoginPoll();
  const form = document.getElementById('loginForm');
  form.onsubmit = async (e) => {
    e.preventDefault();
    const btn = document.getElementById('loginBtn');
    const err = document.getElementById('loginError');
    err.classList.add('hidden'); err.textContent = '';
    btn.disabled = true;
    try {
      await login(CONTEST, form.username.value.trim(), form.password.value);
      // recarrega a página: agora logado, cai no fluxo principal
      location.reload();
    } catch (ex) {
      err.textContent = ex && ex.message ? ex.message : T('Erro de login, tente novamente', 'Login error, try again');
      err.classList.remove('hidden');
      btn.disabled = false;
    }
  };
}

// ============================================================================
// PÁGINA PRINCIPAL DO CONTEST
// ============================================================================
function startContestCountdown() {
  const eln = document.getElementById('contestCountdown');
  const tick = () => {
    const now = Math.floor(Date.now() / 1000);
    const left = (basic.end_time || 0) - now;
    if (left > 0) {
      eln.textContent = T('Termina em: ', 'Ends in: ') + fmtLeft(left);
      setTimeout(tick, 1000);
    } else {
      eln.textContent = T('Competição encerrada', 'Contest ended');
    }
  };
  tick();
}

// mapeia uma url de navbutton (ex.: "/score", "/all_submissions") para a página real
function navHref(url) {
  const c = encodeURIComponent(CONTEST);
  const map = {
    '/': `/contest/?c=${c}`,
    '/score': `/contest/score/?c=${c}`,
    '/all_submissions': `/contest/allsubmissions/?c=${c}`,
    '/stats': `/contest/statistics/?c=${c}`,
    '/pending': `/contest/judge/?c=${c}`,
    '/logout': '#logout',
  };
  if (map[url]) return map[url];
  // urls sem página dedicada (clarification, jplag, reports, admin_tasks, log) -> mantém querystring
  return url + (url.includes('?') ? '&' : '?') + 'c=' + c;
}

function renderNav(buttons) {
  const nav = document.getElementById('contestNav');
  nav.innerHTML = '';
  const here = location.pathname.replace(/\/+$/, '');
  buttons.forEach(b => {
    const href = navHref(b.url);
    if (href === '#logout') {
      nav.append(el('a', {
        href: '#', onclick: async (e) => { e.preventDefault(); await doLogout(); },
      }, b.label));
      return;
    }
    const active = href.split('?')[0].replace(/\/+$/, '') === here;
    nav.append(el('a', { href, class: active ? 'active' : '' }, b.label));
  });
}

async function doLogout() {
  await logout(CONTEST);
  location.reload();
}

function renderUser() {
  const box = document.getElementById('userSection');
  box.innerHTML = '';
  if (!userinfo) return;
  box.append(
    el('div', { style: 'font-size:1.2rem; font-weight:800; color:var(--blue-dark)' },
      userinfo.name || userinfo.login),
    el('div', { class: 'small muted' }, 'Login: ', el('b', {}, userinfo.login),
      userinfo.is_admin ? '  · admin' : (userinfo.is_judge ? '  · judge' : (userinfo.is_staff ? '  · staff' : ''))),
  );
}

function renderNews(items) {
  if (!Array.isArray(items) || !items.length) { hide('newsSection'); return; }
  show('newsSection');
  document.getElementById('newsTitle').textContent = T('Informações & Notícias', 'Info & News');
  const ul = document.getElementById('newsList'); ul.innerHTML = '';
  items.forEach(n => {
    const li = el('li', { style: 'margin:.4rem 0' },
      el('b', { style: 'color:var(--blue-dark)' }, n.title || ''),
      n.date ? el('span', { class: 'small muted' }, '  (' + fmtDate(n.date) + ')') : null,
      el('div', { class: 'small' }, n.text || n.summary || ''));
    ul.append(li);
  });
}

function renderResources(items) {
  if (!Array.isArray(items) || !items.length) { hide('resourcesSection'); return; }
  show('resourcesSection');
  const ul = document.getElementById('resourcesList'); ul.innerHTML = '';
  items.forEach(r => ul.append(el('li', { style: 'margin:.3rem 0' },
    el('a', { href: r.url || '#', target: '_blank' }, r.label || r.url || ''))));
}

// problema accordion (porta de contest/contest/problems.js para shared/ui)
function problemAccepted(p) {
  return submissions.some(s => s.problem === p.problem_id && /^accepted/i.test(s.verdict || ''));
}

function openStatementNewTab(p) {
  const html = b64utf8(p.statement_html_b64 || '');
  let body = html;
  try {
    const doc = new DOMParser().parseFromString(html, 'text/html');
    if (doc.body && doc.body.innerHTML.trim()) body = doc.body.innerHTML;
  } catch {}
  // reusa o CSS compartilhado para o enunciado
  const full = `<!DOCTYPE html><html lang="${LOCALE === 'en' ? 'en' : 'pt-br'}"><head>
    <meta charset="utf-8"><title>${(p.short_name || '') + ' — ' + (p.full_name || '')}</title>
    <link rel="stylesheet" href="/shared/ui.css">
    <style>body{padding:1.4rem;max-width:900px;margin:auto}</style></head>
    <body><div class="statement-content">${body}</div></body></html>`;
  const url = URL.createObjectURL(new Blob([full], { type: 'text/html' }));
  window.open(url, '_blank');
  setTimeout(() => URL.revokeObjectURL(url), 60000);
}

function renderProblems() {
  const list = document.getElementById('problemList');
  list.innerHTML = '';
  const visible = problems.filter(p => p.show !== false);
  if (!visible.length) { list.innerHTML = `<span class="muted">${T('Nenhum problema disponível.', 'No problems available.')}</span>`; return; }

  visible.forEach(p => {
    const accepted = problemAccepted(p);
    const color = accepted ? balloonColor(p.short_name) : '';
    const item = el('div', { class: 'prob-item' + (accepted ? ' accepted' : ''), id: 'prob-' + p.problem_id });
    if (accepted) {
      if (color) {
        item.style.background = color;
        item.style.color = balloonIsDark(color) ? '#fff' : '#222';
      } else {
        item.style.background = '#e2ffe9';
      }
    }

    const toggle = el('span', { class: 'prob-toggle' }, '▶');
    const balloonSlot = el('span', { class: 'prob-balloon', html: accepted && color ? balloonSVG(color) : '' });
    const left = el('span', { class: 'prob-left' },
      toggle,
      balloonSlot,
      el('span', { class: 'prob-sn' }, p.short_name || ''),
      ' ',
      el('span', { class: 'prob-full' }, p.full_name || ''));

    // links de enunciado (HTML/PDF em nova aba)
    const linksWrap = el('span', { class: 'row' });
    if (p.url) linksWrap.append(el('a', { href: p.url, target: '_blank' }, T('Enunciado', 'Statement')));
    if (p.statement_html_b64) linksWrap.append(el('a', { href: '#', onclick: (e) => { e.preventDefault(); openStatementNewTab(p); } }, 'HTML'));
    if (p.statement_pdf_b64) linksWrap.append(el('a', { href: 'data:application/pdf;base64,' + p.statement_pdf_b64, target: '_blank' }, 'PDF'));

    // form de submit ao lado (editor abre no detalhe; aqui só upload rápido + botão)
    const submitWrap = renderSubmitInline(p);

    const right = el('span', { class: 'prob-right' }, linksWrap, submitWrap.row);

    const row = el('div', { class: 'prob-row' },
      left, right);
    // toggle só ao clicar na parte esquerda (não atrapalha o form)
    left.addEventListener('click', () => toggleDetail(p, item, toggle, submitWrap));

    const detail = el('div', { class: 'prob-detail hidden', id: 'prob-detail-' + p.problem_id });
    item.append(row, detail);
    list.append(item);
  });
}

// Atualiza só a aparência (cor do balão) dos problemas aceitos SEM reconstruir a
// lista — preserva editor aberto e código digitado durante o polling.
function retintProblems() {
  problems.filter(p => p.show !== false).forEach(p => {
    const item = document.getElementById('prob-' + p.problem_id);
    if (!item) return;
    const accepted = problemAccepted(p);
    const color = accepted ? balloonColor(p.short_name) : '';
    item.classList.toggle('accepted', accepted);
    if (accepted) {
      item.style.background = color || '#e2ffe9';
      item.style.color = color && balloonIsDark(color) ? '#fff' : '#222';
    } else {
      item.style.background = '';
      item.style.color = '';
    }
    const slot = item.querySelector('.prob-balloon');
    if (slot) slot.innerHTML = accepted && color ? balloonSVG(color) : '';
  });
}

function toggleDetail(p, item, toggle, submitWrap) {
  const detail = item.querySelector('.prob-detail');
  const opened = !detail.classList.contains('hidden');
  if (opened) { detail.classList.add('hidden'); toggle.textContent = '▶'; return; }
  toggle.textContent = '▼';
  if (!detail.dataset.rendered) {
    // time limits
    const tl = p.time_limits || {};
    if (Object.keys(tl).length) {
      const keys = Object.keys(tl);
      detail.append(el('div', {},
        el('b', {}, 'Time Limits'),
        el('table', { class: 'tl-table' },
          el('thead', {}, el('tr', {}, ...keys.map(k => el('th', {}, k)))),
          el('tbody', {}, el('tr', {}, ...keys.map(k => el('td', {}, tl[k] + ' s')))))));
    }
    // editor de código embutido (CodeMirror via shared/editor.js)
    detail.append(submitWrap.editorBlock);
    // enunciado inline (toggle)
    if (p.statement_html_b64) {
      const stmtToggle = el('span', { class: 'stmt-toggle' }, T('Mostrar enunciado', 'Show statement'));
      const stmtDiv = el('div', { class: 'statement-content hidden' });
      stmtToggle.addEventListener('click', () => {
        const hidden = stmtDiv.classList.contains('hidden');
        if (hidden && !stmtDiv.dataset.rendered) {
          stmtDiv.innerHTML = (() => {
            const html = b64utf8(p.statement_html_b64);
            try { const d = new DOMParser().parseFromString(html, 'text/html'); return d.body ? d.body.innerHTML : html; }
            catch { return html; }
          })();
          stmtDiv.dataset.rendered = '1';
        }
        stmtDiv.classList.toggle('hidden', !hidden);
        stmtToggle.textContent = hidden ? T('Esconder enunciado', 'Hide statement') : T('Mostrar enunciado', 'Show statement');
      });
      detail.append(stmtToggle, stmtDiv);
    }
    detail.dataset.rendered = '1';
    submitWrap.mountEditor();
  }
  detail.classList.remove('hidden');
}

// form de submit por problema: upload + editor (no detalhe) + steps + disable enquanto envia
function renderSubmitInline(p) {
  const sel = el('select', {}, ...LANGS.map(([l, label]) => el('option', { value: l }, label)));
  const fileInput = el('input', { type: 'file', style: 'max-width:170px' });
  const steps = el('span', { class: 'submit-steps' });
  const btn = el('button', { class: 'btn', type: 'button' }, T('Enviar', 'Submit'));
  const row = el('span', { class: 'prob-submit' }, fileInput, btn, steps);

  // bloco do editor (vai pro detalhe); criado sob demanda
  const editorMount = el('div');
  const editorBlock = el('div', {},
    el('div', { class: 'row', style: 'margin:.5rem 0' },
      el('label', { class: 'small' }, T('Linguagem: ', 'Language: ')), sel,
      el('span', { class: 'small muted' }, T('  ou envie um arquivo acima.', '  or upload a file above.'))),
    editorMount);
  let editor = null;
  async function mountEditor() {
    if (editor) return;
    editor = await createEditor(editorMount, { doc: '', language: sel.value });
    sel.addEventListener('change', async () => {
      const cur = editor.getValue(); editorMount.innerHTML = '';
      editor = await createEditor(editorMount, { doc: cur, language: sel.value });
    });
  }

  btn.addEventListener('click', async () => {
    btn.disabled = true;
    steps.textContent = T('Preparando…', 'Preparing…');
    try {
      let filename, code_b64;
      if (fileInput.files && fileInput.files[0]) {
        filename = fileInput.files[0].name;
        code_b64 = await fileToBase64(fileInput.files[0]);
      } else {
        const langDef = LANGS.find(x => x[0] === sel.value) || LANGS[0];
        const txt = editor ? editor.getValue() : '';
        if (!txt.trim()) { steps.innerHTML = `<span class="error-box">${T('Escreva código ou escolha um arquivo.', 'Write code or choose a file.')}</span>`; btn.disabled = false; return; }
        filename = 'solution.' + langDef[2];
        code_b64 = textToBase64(txt);
      }
      steps.textContent = T('Enviando…', 'Sending…');
      await apiPost('/submit?contest=' + encodeURIComponent(CONTEST),
        { problem_id: p.problem_id, filename, code_b64 }, { contest: CONTEST, auth: true });
      steps.textContent = T('✓ Enviado!', '✓ Sent!');
      setTimeout(loadSubmissions, 1200);
    } catch (ex) {
      steps.innerHTML = `<span class="error-box">${T('Erro: ', 'Error: ') + (ex && ex.message ? ex.message : T('falha ao enviar', 'failed to send'))}</span>`;
    } finally { btn.disabled = false; }
  });

  return { row, editorBlock, mountEditor };
}

// ---- submissões (tabela + filtro + ordenação + polling) --------------------
function parseHistLine(line) {
  const a = line.split(':');
  if (a.length < 7) return null;
  // tempo:username:problemid:lang:verdict:epoch:subid  (verdict pode conter ':')
  return {
    sinceStart: parseInt(a[0], 10) || 0,
    user: a[1],
    problem: a[2],
    lang: a[3],
    subid: a[a.length - 1],
    epoch: parseInt(a[a.length - 2], 10) || 0,
    verdict: a.slice(4, a.length - 2).join(':'),
  };
}

function renderSubFilter() {
  const bar = document.getElementById('subFilter');
  bar.innerHTML = '';
  const mk = (label, val) => {
    const t = el('span', { class: 'tag' + (subFilter === val ? ' active' : ''), onclick: () => { subFilter = val; renderSubFilter(); renderSubmissions(); } }, label);
    bar.append(t);
  };
  mk(T('Todos', 'All'), 'ALL');
  problems.filter(p => p.show !== false).forEach(p => mk(p.short_name || p.problem_id, p.problem_id));
}

function shortNameOf(pid) {
  const p = problems.find(x => x.problem_id === pid);
  return p ? (p.short_name || pid) : pid;
}
function fullNameOf(pid) {
  const p = problems.find(x => x.problem_id === pid);
  return p ? (p.full_name || '') : '';
}

function renderSubmissions() {
  const box = document.getElementById('submissionsTable');
  let rows = submissions.filter(s => subFilter === 'ALL' ? true : s.problem === subFilter);
  rows = rows.slice().sort((a, b) => {
    if (sortField === 'epoch') return sortAsc ? a.epoch - b.epoch : b.epoch - a.epoch;
    if (sortField === 'problem') {
      const sa = shortNameOf(a.problem), sb = shortNameOf(b.problem);
      return sortAsc ? sa.localeCompare(sb) : sb.localeCompare(sa);
    }
    if (sortField === 'verdict') return sortAsc ? (a.verdict || '').localeCompare(b.verdict || '') : (b.verdict || '').localeCompare(a.verdict || '');
    return 0;
  });

  box.innerHTML = '';
  if (!rows.length) { box.innerHTML = `<span class="muted small">${T('Nenhuma submissão ainda.', 'No submissions yet.')}</span>`; return; }

  const arrow = (f) => sortField === f ? (sortAsc ? ' ▲' : ' ▼') : '';
  const th = (label, f) => el('th', { onclick: () => { sortAsc = (sortField === f) ? !sortAsc : false; sortField = f; renderSubmissions(); } }, label + arrow(f));
  const canLog = !!(userinfo && (userinfo.show_log || userinfo.is_admin || userinfo.is_judge));

  const head = el('thead', {}, el('tr', {},
    th(T('Tempo', 'Time'), 'epoch'),
    th(T('Problema', 'Problem'), 'problem'),
    el('th', {}, T('Arquivo', 'File')),
    th(T('Resultado', 'Result'), 'verdict'),
    el('th', {}, T('Data', 'Date')),
    canLog ? el('th', {}, 'Log') : null));

  const tb = el('tbody');
  rows.forEach(s => {
    const pending = isPending(s.verdict);
    const fileLink = el('a', {
      href: '#', onclick: (e) => { e.preventDefault(); downloadAuthed(`/submission/source?contest=${encodeURIComponent(CONTEST)}&id=${encodeURIComponent(s.subid)}&time=${encodeURIComponent(s.epoch)}`, s.subid + '.' + (s.lang || 'txt').toLowerCase()); },
    }, T('cód', 'src'));
    const vcell = el('td', {}, el('span', { class: 'verdict ' + vClass(s.verdict) },
      pending ? el('span', {}, el('span', { class: 'spin' }), ' ' + s.verdict) : s.verdict));
    const logCell = canLog ? el('td', {},
      el('a', { href: '#', onclick: (e) => { e.preventDefault(); openLogAuthed(`/submission/log?contest=${encodeURIComponent(CONTEST)}&id=${encodeURIComponent(s.subid)}&time=${encodeURIComponent(s.epoch)}`); } }, 'log')) : null;
    tb.append(el('tr', {},
      el('td', {}, String(s.sinceStart)),
      el('td', {}, el('b', {}, shortNameOf(s.problem)), ' ', el('span', { class: 'small muted' }, fullNameOf(s.problem))),
      el('td', {}, fileLink),
      vcell,
      el('td', {}, fmtDate(s.epoch)),
      logCell));
  });

  box.append(el('table', { class: 'moj' }, head, tb));
}

async function loadSubmissions() {
  let txt;
  try { txt = await apiGetText('/contest/history?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true }); }
  catch { return; }
  submissions = txt.split('\n').map(s => s.trim()).filter(Boolean).map(parseHistLine).filter(Boolean);
  renderSubFilter();
  renderSubmissions();
  retintProblems(); // re-tinge problemas que viraram accepted (sem reconstruir a lista)

  clearTimeout(pollTimer);
  if (submissions.some(s => isPending(s.verdict))) {
    pollTimer = setTimeout(loadSubmissions, 5000 + Math.random() * 5000); // 5–10s
  }
}

async function bootMain() {
  hide('loginView'); show('mainView');
  document.title = (basic.contest_name || 'Contest') + ' — MOJ';
  document.getElementById('contestTitle').textContent = basic.contest_name || 'Contest';
  startContestCountdown();
  document.getElementById('logoutBtn').onclick = doLogout;

  // userinfo + nav (em paralelo)
  const [ui, nav, bc] = await Promise.all([
    apiGet('/contest/userinfo?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true }).catch(() => null),
    apiGet('/contest/navbuttons?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true }).catch(() => null),
    apiGet('/contest/balloons?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true }).catch(() => null),
  ]);
  userinfo = ui;
  renderUser();
  const buttons = nav ? (Array.isArray(nav) ? nav : (nav.buttons || [])) : [];
  if (buttons.length) renderNav(buttons);
  balloons = bc ? (bc.balloons || bc) : {};

  // news/resources (opcionais — escondem se vazio/erro)
  apiGet('/contest/news?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true })
    .then(j => renderNews(Array.isArray(j) ? j : (j.items || j.news || []))).catch(() => hide('newsSection'));
  apiGet('/contest/resources?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true })
    .then(j => renderResources(Array.isArray(j) ? j : (j.items || []))).catch(() => hide('resourcesSection'));

  // problemas
  try {
    const j = await apiGet('/contest/problems?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true });
    problems = Array.isArray(j) ? j : (j.problems || []);
  } catch {
    document.getElementById('problemList').innerHTML = `<span class="error-box">${T('Falha ao carregar problemas.', 'Failed to load problems.')}</span>`;
    problems = [];
  }
  renderProblems();
  renderSubFilter();
  await loadSubmissions();
}

// ============================================================================
// BOOT
// ============================================================================
async function boot() {
  if (!CONTEST) {
    document.body.innerHTML = '<div class="container"><div class="error-box">Contest não informado (use ?c=&lt;id&gt;).</div></div>';
    return;
  }
  try {
    basic = await apiGet('/contest/basic?contest=' + encodeURIComponent(CONTEST), {});
  } catch (e) {
    document.body.innerHTML = '<div class="container"><div class="error-box">Contest não encontrado.</div></div>';
    return;
  }
  LOCALE = basic.locale || 'pt';

  const st = await status(CONTEST);
  if (st.logged_in) await bootMain();
  else bootLogin();
}
boot();
