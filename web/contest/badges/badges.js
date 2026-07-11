// contest/badges/badges.js — etiquetas imprimíveis de credenciais (admin + .cstaff).
// Admin vê a lista completa (ou o "arquivo" de cada sede via seletor de .cstaff); o
// .cstaff (chefe de sede) vê só o próprio recorte — quem corta é a API (/contest/badges).
// O .staff NÃO tem acesso (403 na API). A senha vem SEMPRE p/ quem pode ver a página; a
// variante "sem senha" é só escolha local de impressão.
// A folha é HTML em mm (posicionamento absoluto), casada com os gabaritos Pimaco A4;
// imprimir = window.print() com margens "Nenhuma" e escala 100%. Credenciais NUNCA são
// gravadas no cliente — só o estado dos controles vai ao localStorage.
import { apiGet } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { initContestShell } from '/shared/contest-shell.js';
import { T } from '/shared/i18n.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const sheets = document.getElementById('sheets');
const G = { contest: CONTEST, auth: true };
const enc = encodeURIComponent;
const CFGKEY = 'moj_badges_' + CONTEST;

// Gabaritos Pimaco A4 (linha A43xx, compatível Avery L71xx) + o crachá do MOJ 2025.
// Dimensões NOMINAIS (mm) — confira na embalagem; os campos editáveis são a fonte da
// verdade do render (o preset só os preenche). ph/pv = passo (etiqueta + espaçamento).
const PRESETS = [
  { id: 'a4365',   label: T('Pimaco A4365 · 99,1×67,7 · 8/folha (grande)', 'Pimaco A4365 · 99.1×67.7 · 8/sheet (large)'),   w: 99.1, h: 67.7, cols: 2, rows: 4, mt: 13.1, ml: 4.65, ph: 101.6, pv: 67.7 },
  { id: 'moj2025', label: T('Crachá MOJ 2025 · 88,9×50,8 · 10/folha', 'MOJ 2025 badge · 88.9×50.8 · 10/sheet'),        w: 88.9, h: 50.8, cols: 2, rows: 5, mt: 21.5, ml: 16.1, ph: 88.9,  pv: 50.8 },
  { id: 'a4361',   label: T('Pimaco A4361 · 63,5×46,6 · 18/folha', 'Pimaco A4361 · 63.5×46.6 · 18/sheet'),           w: 63.5, h: 46.6, cols: 3, rows: 6, mt: 8.7,  ml: 7.25, ph: 66.0,  pv: 46.6 },
  { id: 'a4363',   label: T('Pimaco A4363 · 99,1×38,1 · 14/folha (média)', 'Pimaco A4363 · 99.1×38.1 · 14/sheet (medium)'),   w: 99.1, h: 38.1, cols: 2, rows: 7, mt: 15.1, ml: 4.65, ph: 101.6, pv: 38.1 },
  { id: 'a4362',   label: T('Pimaco A4362 · 99,1×33,9 · 16/folha (média)', 'Pimaco A4362 · 99.1×33.9 · 16/sheet (medium)'),   w: 99.1, h: 33.9, cols: 2, rows: 8, mt: 12.9, ml: 4.65, ph: 101.6, pv: 33.9 },
  { id: 'a4360',   label: T('Pimaco A4360 · 63,5×38,1 · 21/folha (pequena)', 'Pimaco A4360 · 63.5×38.1 · 21/sheet (small)'), w: 63.5, h: 38.1, cols: 3, rows: 7, mt: 15.1, ml: 7.25, ph: 66.0,  pv: 38.1 },
  { id: 'custom',  label: T('Dimensões personalizadas', 'Custom dimensions') },
];
const DIMKEYS = ['w', 'h', 'cols', 'rows', 'mt', 'ml', 'ph', 'pv'];

// estado dos controles (persistido; NUNCA guarda credenciais)
const S = Object.assign({
  preset: 'a4365',
  dims: { w: 99.1, h: 67.7, cols: 2, rows: 4, mt: 13.1, ml: 4.65, ph: 101.6, pv: 67.7 },
  showPass: true,
  fEvent: true, fRegion: true, fUniv: true,     // conteúdo extra da etiqueta
  outline: false, skip: 0, regionFilter: '', staffView: '', incDisabled: false,
}, JSON.parse(localStorage.getItem(CFGKEY) || 'null') || {});
const save = () => localStorage.setItem(CFGKEY, JSON.stringify(S));

let DATA = null;         // última resposta da API
let IS_ADMIN = false;
let afterLoad = () => {}; // repopula selects (definido em render())
const statusBar = el('span', { class: 'small muted' });

async function load() {
  let q = '/contest/badges?contest=' + enc(CONTEST);
  if (IS_ADMIN && S.staffView) q += '&staff=' + enc(S.staffView);
  if (S.incDisabled) q += '&include_disabled=1';
  statusBar.textContent = T('carregando…', 'loading…');
  try { DATA = await apiGet(q, G); }
  catch (e) { DATA = null; sheets.innerHTML = ''; statusBar.textContent = T('Falha ao listar: ', 'Failed to list: ') + (e.message || T('erro', 'error')); return; }
  afterLoad();
  renderSheets();
}

// reduz a fonte do elemento até o conteúdo caber (nomes/instituições longos)
function fitText(elm, box, minPx) {
  let size = parseFloat(getComputedStyle(elm).fontSize);
  while (size > minPx && (box.scrollHeight > box.clientHeight + 1 || elm.scrollWidth > elm.clientWidth + 1)) {
    size -= 0.5; elm.style.fontSize = size + 'px';
  }
}

function labelNode(u, d) {
  const mm = (v) => v.toFixed(2) + 'mm';
  const role = /\.cstaff$/.test(u.login || '') ? T('chefe de sede', 'site chief')
    : (/\.staff$/.test(u.login || '') ? 'staff' : '');
  const inner = el('div', { class: 'lbl-inner' });
  // tamanhos proporcionais à altura da etiqueta (auto-reduzidos depois, se estourar)
  const nameSz = Math.max(3.2, Math.min(5.4, d.h * 0.105));
  const credSz = Math.max(2.8, Math.min(4.6, d.h * 0.082));
  inner.append(el('div', { class: 'name', style: 'font-size:' + mm(nameSz) }, u.name || u.login));
  if (S.fUniv && u.univ) inner.append(el('div', { class: 'univ', style: 'font-size:' + mm(Math.max(2.4, nameSz * 0.55)) }, u.univ));
  inner.append(el('div', { class: 'cred', style: 'font-size:' + mm(credSz) }, u.login));
  if (S.showPass) inner.append(el('div', { class: 'cred', style: 'font-size:' + mm(credSz) }, u.password || ''));
  const tag = (S.fRegion && u.region ? u.region : '') + (role ? (S.fRegion && u.region ? ' · ' : '') + role : '');
  if (tag) inner.append(el('div', { class: 'tag' }, tag));
  if (S.fEvent) {
    const dt = DATA.start_epoch > 0 ? new Date(DATA.start_epoch * 1000).toLocaleDateString('pt-BR') : '';
    inner.append(el('div', { class: 'foot' }, (DATA.contest_name || CONTEST) + (dt ? ' · ' + dt : '')));
  }
  return el('div', { class: 'lbl' }, inner);
}

function renderSheets() {
  sheets.innerHTML = '';
  document.body.classList.toggle('outline', !!S.outline);
  if (!DATA) return;
  let users = DATA.users || [];
  if (S.regionFilter) users = users.filter((u) => (u.region || T('(sem região)', '(no region)')) === S.regionFilter);
  const d = S.dims, cols = Math.max(1, d.cols | 0), rows = Math.max(1, d.rows | 0);
  const perPage = cols * rows;
  const skip = Math.min(Math.max(0, S.skip | 0), perPage - 1);
  statusBar.textContent = users.length + T(' etiqueta(s)', ' badge(s)') +
    (DATA.staff_view ? T(' · arquivo de ', ' · file of ') + DATA.staff_view : '') +
    ' · ' + Math.ceil((users.length + skip) / perPage) + T(' folha(s) de ', ' sheet(s) of ') + perPage +
    (S.showPass ? T(' · COM senha', ' · WITH password') : T(' · sem senha', ' · without password'));
  if (!users.length) {
    sheets.append(el('p', { class: 'muted small no-print', style: 'text-align:center' }, T('Nenhum usuário para etiquetar.', 'No users to print badges for.')));
    return;
  }
  const fits = [];
  users.forEach((u, i) => {
    const pos = i + skip, slot = pos % perPage;
    if (i === 0 || slot === 0) sheets.append(el('div', { class: 'sheet' }));   // nova folha
    const sheet = sheets.lastChild;
    const lbl = labelNode(u, d);
    lbl.style.left = (d.ml + (slot % cols) * d.ph) + 'mm';
    lbl.style.top = (d.mt + Math.floor(slot / cols) * d.pv) + 'mm';
    lbl.style.width = d.w + 'mm';
    lbl.style.height = d.h + 'mm';
    sheet.append(lbl);
    fits.push(lbl);
  });
  // fit com tudo no DOM (mede tamanhos reais)
  fits.forEach((lbl) => {
    const inner = lbl.firstChild;
    fitText(inner.querySelector('.name'), inner, 8);
    const uv = inner.querySelector('.univ'); if (uv) fitText(uv, inner, 7);
  });
}

function render() {
  app.innerHTML = '';
  const mkChk = (label, key, refetch) => {
    const c = el('input', { type: 'checkbox' }); c.checked = !!S[key];
    c.addEventListener('change', () => { S[key] = c.checked; save(); refetch ? load() : renderSheets(); });
    return el('label', {}, c, ' ' + label);
  };

  // variante com/sem senha (escolha LOCAL de impressão — a credencial já veio da API)
  const passSel = el('select', {},
    el('option', { value: '1' }, T('🔑 com senha', '🔑 with password')),
    el('option', { value: '' }, T('sem senha', 'without password')));
  passSel.value = S.showPass ? '1' : '';
  passSel.addEventListener('change', () => { S.showPass = passSel.value === '1'; save(); renderSheets(); });

  // preset Pimaco → preenche as dimensões editáveis (fonte da verdade do render)
  const presetSel = el('select', {}, PRESETS.map((p) => el('option', { value: p.id }, p.label)));
  presetSel.value = PRESETS.some((p) => p.id === S.preset) ? S.preset : 'custom';
  const dimInputs = {};
  const numField = (label, key, step) => {
    const i = el('input', { type: 'number', step: step || '0.05', min: '0', value: S.dims[key] });
    dimInputs[key] = i;
    i.addEventListener('change', () => {
      S.dims[key] = parseFloat(i.value) || 0;
      S.preset = 'custom'; presetSel.value = 'custom';
      save(); renderSheets();
    });
    return el('label', {}, label + ' ', i);
  };
  const dimBox = el('div', { class: 'dim-grid' },
    numField(T('largura', 'width'), 'w'), numField(T('altura', 'height'), 'h'),
    numField(T('colunas', 'columns'), 'cols', '1'), numField(T('linhas', 'rows'), 'rows', '1'),
    numField(T('marg. sup.', 'top margin'), 'mt'), numField(T('marg. esq.', 'left margin'), 'ml'),
    numField(T('passo horiz.', 'horiz. pitch'), 'ph'), numField(T('passo vert.', 'vert. pitch'), 'pv'));
  presetSel.addEventListener('change', () => {
    S.preset = presetSel.value;
    const p = PRESETS.find((x) => x.id === S.preset);
    if (p && p.id !== 'custom') {
      DIMKEYS.forEach((k) => { S.dims[k] = p[k]; dimInputs[k].value = p[k]; });
    }
    save(); renderSheets();
  });

  // filtros: região (client-side) e, p/ admin, o "arquivo" de cada staff (refaz o fetch)
  const regionSel = el('select', {}, el('option', { value: '' }, T('todas as regiões', 'all regions')));
  regionSel.addEventListener('change', () => { S.regionFilter = regionSel.value; save(); renderSheets(); });
  const staffSel = el('select', {}, el('option', { value: '' }, T('lista completa', 'full list')));
  staffSel.addEventListener('change', () => { S.staffView = staffSel.value; save(); load(); });

  const skipIn = el('input', { type: 'number', min: '0', step: '1', value: S.skip | 0, title: T('etiquetas já usadas na 1ª folha', 'badges already used on the 1st sheet') });
  skipIn.addEventListener('change', () => { S.skip = Math.max(0, skipIn.value | 0); save(); renderSheets(); });

  afterLoad = fillSelects;

  function fillSelects() {
    if (!DATA) return;
    const regs = [...new Set((DATA.users || []).map((u) => u.region || T('(sem região)', '(no region)')))];
    regionSel.innerHTML = ''; regionSel.append(el('option', { value: '' }, T('todas as regiões', 'all regions')));
    regs.forEach((r) => regionSel.append(el('option', { value: r }, r)));
    if (!regs.includes(S.regionFilter)) S.regionFilter = '';
    regionSel.value = S.regionFilter;
    if (IS_ADMIN) {
      staffSel.innerHTML = ''; staffSel.append(el('option', { value: '' }, T('lista completa', 'full list')));
      (DATA.staff || []).forEach((s) => staffSel.append(
        el('option', { value: s.login }, T('arquivo de ', 'file of ') + s.login + (s.fullname ? ' — ' + s.fullname : ''))));
      if (!(DATA.staff || []).some((s) => s.login === S.staffView)) S.staffView = '';
      staffSel.value = S.staffView;
    }
  }

  app.append(el('div', { class: 'section controls' },
    el('div', { class: 'row' },
      el('label', {}, T('Variante ', 'Variant '), passSel),
      mkChk(T('contest + data', 'contest + date'), 'fEvent'), mkChk(T('sede/região', 'site/region'), 'fRegion'), mkChk(T('instituição', 'institution'), 'fUniv'),
      mkChk(T('contorno (calibrar)', 'outline (calibrate)'), 'outline')),
    el('div', { class: 'row', style: 'margin-top:.5rem' },
      el('label', {}, T('Etiqueta ', 'Label '), presetSel), dimBox),
    el('div', { class: 'row', style: 'margin-top:.5rem' },
      IS_ADMIN ? el('label', {}, T('Arquivo ', 'File '), staffSel) : '',
      el('label', {}, T('Região ', 'Region '), regionSel),
      IS_ADMIN ? mkChk(T('incluir desabilitados', 'include disabled'), 'incDisabled', true) : '',
      el('label', {}, T('pular ', 'skip '), skipIn, T(' etiqueta(s)', ' badge(s)')),
      el('div', { class: 'spacer' }), statusBar,
      el('button', { class: 'btn', onclick: () => window.print() }, T('🖨️ Imprimir', '🖨️ Print')))));
  load();
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">' + T('Contest não informado.', 'Contest not specified.') + '</div>'; return; }
  const { st } = await initContestShell(CONTEST);
  if (!st || !st.logged_in) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, T('🔒 Entre no contest', '🔒 Log in to the contest')),
      el('a', { class: 'btn', href: '/contest/?c=' + enc(CONTEST) }, T('Ir para o contest', 'Go to the contest'))));
    return;
  }
  if (!st.is_cstaff && !st.is_admin) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, T('🔒 Acesso restrito', '🔒 Restricted access')),
      el('p', { class: 'muted' }, T('Etiquetas de credenciais são do admin e do chefe de sede (.cstaff).', 'Credential badges are for admins and the site chief (.cstaff).'))));
    return;
  }
  IS_ADMIN = !!st.is_admin;
  if (!IS_ADMIN) S.staffView = '';
  render();
}
boot();
