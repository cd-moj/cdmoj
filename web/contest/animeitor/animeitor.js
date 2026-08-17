// contest/animeitor/animeitor.js — a mesa do operador do TELÃO (.animeitor; o admin também
// entra). Duas seções: 📷 FOTOS dos times (galeria, trocar/remover, envio em lote pelo nome do
// arquivo, pacote .zip) e 🎥 STREAMING (as chaves do webcast que o sistema Animeitor busca em
// loop — ver docs/WEBCAST.md).
// A foto é gravada em WEBP pelo servidor (lib/team-photo.sh); aqui só se manda o arquivo.
import { apiGet, apiPost } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { fileToBase64 } from '/shared/auth.js';
import { initContestShell } from '/shared/contest-shell.js';
import { downloadAuthed, fmtDate, norm, debounce } from '/shared/admin-ui.js';
import { T } from '/shared/i18n.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const G = { contest: CONTEST, auth: true };
const enc = encodeURIComponent;

let PHOTOS = null;   // {teams:[…], total, with_photo}
let WC = null;       // {keys:[…], views:[…], url_path}

// ESTADO DA GALERIA (prova de verdade tem 1000+ times): filtro + página. Abre em "sem foto",
// que é a fila de trabalho de quem opera o telão.
const F = { photo: 'no', q: '', cohort: '', univ: '', region: '' };
let PAGE_I = 0;
const PAGE = 48;     // 48 cartões = a grade cheia; o DOM fica pequeno e só estas fotos baixam

// MINIATURA (thumb=1, ~7 KB em vez de 37 KB) e cache-buster ESTÁVEL (v=<mtime>): com
// `t=Date.now()` cada render rebaixava a imagem inteira de novo.
const photoUrl = (t, thumb) =>
  `/api/v1/contest/team-photo?contest=${enc(CONTEST)}&user=${enc(t.login)}`
  + (thumb ? '&thumb=1' : '') + `&v=${t.mtime || 0}`;

// URL que o Animeitor deve buscar. Host atual: dentro do contest é o subdomínio dele, que é
// exatamente o endereço que o operador tem à mão.
const wcUrl = (key) =>
  `${location.origin}${(WC && WC.url_path) || '/api/v1/contest/webcast'}?contest=${enc(CONTEST)}&key=${enc(key)}`;

function msg(box, text, cls) {
  box.innerHTML = '';
  if (text) box.append(el('span', { class: cls || 'small muted' }, text));
}

// ---------- 📷 fotos ----------------------------------------------------------
async function loadPhotos() {
  PHOTOS = await apiGet('/contest/animeitor/photos?contest=' + enc(CONTEST), G);
}

// upload de UM time: atualiza só o cartão (a resposta traz bytes/format) — recarregar a
// listagem inteira a cada foto seria absurdo numa prova de 1000 times.
async function sendPhoto(t, file, box) {
  const b64 = await fileToBase64(file);
  const r = await apiPost('/contest/animeitor/photo?contest=' + enc(CONTEST), { login: t.login, file_b64: b64 }, G);
  Object.assign(t, { has_photo: true, format: r.format || 'webp', bytes: r.bytes || 0, mtime: Math.floor(Date.now() / 1000) });
  if (PHOTOS) PHOTOS.with_photo = PHOTOS.teams.filter((x) => x.has_photo).length;
  renderPhotos();
  if (box) msg(box, T('Foto atualizada: ', 'Photo updated: ') + (t.name || t.login), 'small');
}

function photoCard(t, box) {
  const inp = el('input', { type: 'file', accept: 'image/*', style: 'display:none' });
  inp.addEventListener('change', async () => {
    const f = inp.files && inp.files[0];
    if (!f) return;
    if (f.size > 8 * 1024 * 1024) { msg(box, T('Imagem muito grande (máx 8MB).', 'Image too large (max 8MB).'), 'error-box'); return; }
    msg(box, T('Enviando ', 'Uploading ') + t.login + '…');
    try { await sendPhoto(t, f, box); }
    catch (e) { msg(box, T('Falha: ', 'Failed: ') + (e.message || e), 'error-box'); }
  });
  return el('div', { class: 'card' },
    t.has_photo
      // miniatura + lazy: só as fotos da página corrente são baixadas, e a 2ª visita vem do cache
      ? el('a', { href: photoUrl(t, false), target: '_blank', title: T('ver em tamanho real', 'view full size') },
          el('img', { class: 'ph', src: photoUrl(t, true), alt: t.name, loading: 'lazy', decoding: 'async' }))
      : el('div', { class: 'ph none' }, T('sem foto', 'no photo')),
    el('div', { class: 'nm' }, t.name || t.login),
    el('div', { class: 'lg' }, (t.univ ? '[' + t.univ + '] ' : '') + t.login),
    el('div', { class: 'lg' }, t.has_photo ? `${t.format} · ${Math.round((t.bytes || 0) / 1024)} KB` : ''),
    el('div', { class: 'acts' }, inp,
      el('button', { class: 'btn ghost', onclick: () => inp.click() },
        t.has_photo ? T('trocar', 'replace') : T('enviar', 'upload')),
      t.has_photo ? el('button', { class: 'btn ghost danger', onclick: async () => {
        if (!confirm(T('Remover a foto de ', 'Remove the photo of ') + (t.name || t.login) + '?')) return;
        try {
          await apiPost('/contest/animeitor/photo?contest=' + enc(CONTEST), { action: 'delete', login: t.login }, G);
          Object.assign(t, { has_photo: false, format: '', bytes: 0, mtime: 0 });
          if (PHOTOS) PHOTOS.with_photo = PHOTOS.teams.filter((x) => x.has_photo).length;
          renderPhotos();
        } catch (e) { msg(box, T('Falha: ', 'Failed: ') + (e.message || e), 'error-box'); }
      } }, T('remover', 'remove')) : ''),
  );
}

// ---- filtro (tudo no cliente, sobre a lista já carregada) ----
const teamsAll = () => (PHOTOS && PHOTOS.teams) || [];
// os predicados são separados p/ a CONTAGEM VIVA dos chips (contar sem o próprio filtro de foto)
const matchQ = (t) => !F.q || norm(`${t.name} ${t.login} ${t.univ}`).includes(F.q);
const matchSel = (t) => (!F.cohort || t.cohort === F.cohort)
                     && (!F.univ || t.univ === F.univ)
                     && (!F.region || t.region === F.region);
const matchPhoto = (t) => F.photo === 'all' || (F.photo === 'yes' ? t.has_photo : !t.has_photo);
const filtered = () => teamsAll().filter((t) => matchPhoto(t) && matchSel(t) && matchQ(t));

function selOf(field, label, id) {
  const vals = [...new Set(teamsAll().map((t) => t[field]).filter(Boolean))].sort();
  if (!vals.length) return '';
  const sel = el('select', { id },
    el('option', { value: '' }, T('todas', 'all')),
    ...vals.map((v) => el('option', { value: v }, v)));
  sel.value = F[field] || '';
  sel.addEventListener('change', () => { F[field] = sel.value; PAGE_I = 0; renderPhotos(); });
  return el('label', {}, label, sel);
}

function photosBar(box) {
  // contagem VIVA dos chips: conta com os OUTROS filtros aplicados (o de foto não conta a si
  // mesmo) — mesma semântica das facetas do treino
  const base = teamsAll().filter((t) => matchSel(t) && matchQ(t));
  const nYes = base.filter((t) => t.has_photo).length;
  const chip = (key, label, n) => el('button', {
    class: 'btn ' + (F.photo === key ? '' : 'ghost'),
    onclick: () => { F.photo = key; PAGE_I = 0; renderPhotos(); },
  }, `${label} (${n})`);

  const q = el('input', { id: 'fQ', class: 'filter', type: 'search',
    placeholder: T('buscar time, login, universidade…', 'search team, login, university…') });
  q.value = F.q;
  // debounce: com 1000 times o re-render a cada tecla seria perceptível
  q.addEventListener('input', debounce(() => { F.q = norm(q.value.trim()); PAGE_I = 0; renderPhotos(); }, 150));

  return el('div', { class: 'fbar' },
    el('div', { class: 'row', style: 'gap:.3rem' },
      chip('no', T('Sem foto', 'Missing'), base.length - nYes),
      chip('yes', T('Com foto', 'With photo'), nYes),
      chip('all', T('Todos', 'All'), base.length)),
    selOf('cohort', T('Coorte:', 'Cohort:'), 'fCohort'),
    selOf('univ', T('Universidade:', 'University:'), 'fUniv'),
    selOf('region', T('Sede:', 'Site:'), 'fRegion'),
    q,
    el('button', { id: 'fClear', class: 'btn ghost', onclick: () => {
      F.photo = 'all'; F.q = ''; F.cohort = ''; F.univ = ''; F.region = ''; PAGE_I = 0; renderPhotos();
    } }, T('limpar', 'clear')),
    el('span', { class: 'fcount', id: 'fCount' }, ''),
  );
}

// pager do padrão da casa (treino/problemas): ‹ página X / Y ›
function pager(pages) {
  if (pages <= 1) return '';
  return el('div', { class: 'row', style: 'gap:.4rem; align-items:center; margin:.5rem 0' },
    el('button', { class: 'btn ghost', onclick: () => { if (PAGE_I > 0) { PAGE_I--; renderPhotos(); } } }, '‹'),
    el('span', { class: 'small' }, ` ${T('página', 'page')} ${PAGE_I + 1} / ${pages} `),
    el('button', { class: 'btn ghost', onclick: () => { if (PAGE_I < pages - 1) { PAGE_I++; renderPhotos(); } } }, '›'));
}

// re-render SÓ da seção de fotos (o streaming não é tocado por filtro/página)
function renderPhotos() {
  const host = document.getElementById('photosSec');
  if (!host) return;
  const box = el('div', { class: 'small muted', id: 'phMsg' });
  const prev = document.getElementById('phMsg');
  if (prev) box.append(...prev.childNodes);           // preserva a mensagem do último upload

  const rows = filtered();
  const pages = Math.max(1, Math.ceil(rows.length / PAGE));
  if (PAGE_I >= pages) PAGE_I = pages - 1;
  const slice = rows.slice(PAGE_I * PAGE, PAGE_I * PAGE + PAGE);

  host.innerHTML = '';
  host.append(
    el('h2', {}, T('📷 Fotos dos times', '📷 Team photos')),
    el('p', { class: 'note' },
      T(`${(PHOTOS && PHOTOS.with_photo) || 0} de ${(PHOTOS && PHOTOS.total) || 0} times já têm foto.`,
        `${(PHOTOS && PHOTOS.with_photo) || 0} of ${(PHOTOS && PHOTOS.total) || 0} teams already have a photo.`)),
    el('div', { class: 'row', style: 'gap:.5rem; margin-bottom:.4rem; flex-wrap:wrap' }, bulkInput(box),
      el('button', { class: 'btn', onclick: () => document.getElementById('phBulk').click() },
        T('⬆ Enviar em lote (nome do arquivo = login)', '⬆ Bulk upload (file name = login)')),
      el('button', { class: 'btn ghost', onclick: () => downloadAuthed(CONTEST,
          '/contest/animeitor/photos-zip?contest=' + enc(CONTEST), 'fotos-' + CONTEST + '.zip') },
        T('⬇ Baixar pacote (.zip)', '⬇ Download package (.zip)'))),
    photosBar(box), box,
    rows.length ? el('div', { class: 'gal' }, ...slice.map((t) => photoCard(t, box)))
                : el('p', { class: 'muted' }, T('Nenhum time casa com o filtro.', 'No team matches the filter.')),
    pager(pages),
  );
  const c = document.getElementById('fCount');
  if (c) c.textContent = (rows.length === teamsAll().length)
    ? T(`${rows.length} times`, `${rows.length} teams`)
    : T(`Mostrando ${rows.length} de ${teamsAll().length} times`, `Showing ${rows.length} of ${teamsAll().length} teams`);
}

function bulkInput(box) {
  const bulk = el('input', { id: 'phBulk', type: 'file', accept: 'image/*', multiple: true, style: 'display:none' });
  bulk.addEventListener('change', async () => {
    const fs = [...(bulk.files || [])];
    if (!fs.length) return;
    let ok = 0; const bad = [];
    for (let i = 0; i < fs.length; i++) {
      msg(box, T('Enviando ', 'Uploading ') + (i + 1) + '/' + fs.length + '…');
      // o LOGIN vem do nome do arquivo (fulano.jpg -> fulano), como no painel de Times
      try {
        await apiPost('/contest/animeitor/photo?contest=' + enc(CONTEST),
          { login: fs[i].name, file_b64: await fileToBase64(fs[i]) }, G);
        ok++;
      } catch { bad.push(fs[i].name); }
    }
    await loadPhotos(); renderPhotos();
    const b = document.getElementById('phMsg');
    if (b) msg(b, T(`${ok} foto(s) enviada(s).`, `${ok} photo(s) uploaded.`)
      + (bad.length ? T(' Não casaram com nenhum time: ', ' No team matched: ') + bad.join(', ') : ''),
      bad.length ? 'error-box' : 'small');
  });
  return bulk;
}

// ---------- 🎥 streaming ------------------------------------------------------
function keyRow(k) {
  const url = wcUrl(k.key);
  const view = ((WC.views || []).find((v) => v.id === k.view) || {}).name || k.view;
  const revoked = k.revoked_at > 0;
  return el('tr', { class: revoked ? 'revoked' : '' },
    el('td', {}, el('b', {}, view), k.label ? el('div', { class: 'small muted' }, k.label) : ''),
    el('td', {}, revoked
      ? el('span', { class: 'small muted' }, T('revogada em ', 'revoked at ') + fmtDate(k.revoked_at))
      : el('span', { class: 'keyurl' }, url)),
    el('td', { class: 'n' }, String(k.fetches || 0)),
    el('td', { class: 'small muted' }, k.last_at
      ? fmtDate(k.last_at) + (k.last_ip ? ' · ' + k.last_ip : '')
      : T('nunca buscada', 'never fetched')),
    el('td', {}, revoked ? '' : el('div', { class: 'row', style: 'gap:.3rem' },
      el('button', { class: 'btn ghost', onclick: async () => {
        try { await navigator.clipboard.writeText(url); alert(T('URL copiada.', 'URL copied.')); }
        catch { prompt(T('Copie a URL:', 'Copy the URL:'), url); }
      } }, T('copiar', 'copy')),
      el('a', { class: 'btn ghost', href: url, target: '_blank' }, T('testar', 'test')),
      el('button', { class: 'btn ghost danger', onclick: async () => {
        if (!confirm(T('Revogar esta chave? O Animeitor que a usa para de receber o placar.',
                       'Revoke this key? The Animeitor using it stops receiving the scoreboard.'))) return;
        await apiPost('/contest/animeitor/webcast?contest=' + enc(CONTEST), { action: 'revoke', id: k.id }, G);
        WC = await apiGet('/contest/animeitor/webcast?contest=' + enc(CONTEST), G); render();
      } }, T('revogar', 'revoke')))),
  );
}

function streamSection() {
  const sel = el('select', {}, ...((WC.views || []).map((v) => el('option', { value: v.id }, v.name))));
  const lbl = el('input', { type: 'text', placeholder: T('apelido (ex.: telão principal)', 'label (e.g. main screen)'), style: 'max-width:16rem' });
  const box = el('div', { class: 'small muted' });
  const keys = (WC.keys || []);
  return el('div', { class: 'section' },
    el('h2', {}, T('🎥 Streaming de placar (Animeitor)', '🎥 Scoreboard streaming (Animeitor)')),
    el('p', { class: 'note' },
      T('Cada chave gera uma URL que o Animeitor busca em loop e devolve o pacote .zip no formato do BOCA (contest/runs/time/version). O placar do pacote vai SEMPRE descongelado — quem anima a virada é o Animeitor.',
        'Each key yields a URL the Animeitor polls, returning the .zip package in BOCA format (contest/runs/time/version). The package is ALWAYS unfrozen — the reveal animation is the Animeitor’s job.')),
    el('p', { class: 'note' }, '⚠ ',
      T('Quem tem a URL vê o placar descongelado durante a prova. Trate como senha e revogue depois do evento.',
        'Whoever holds the URL sees the unfrozen scoreboard during the contest. Treat it as a password and revoke it after the event.')),
    el('div', { class: 'row', style: 'gap:.5rem; align-items:center; flex-wrap:wrap; margin:.6rem 0' },
      el('span', { class: 'small muted' }, T('Placar:', 'Board:')), sel, lbl,
      el('button', { class: 'btn', onclick: async () => {
        msg(box, T('Criando…', 'Creating…'));
        try {
          await apiPost('/contest/animeitor/webcast?contest=' + enc(CONTEST),
            { action: 'create', view: sel.value, label: lbl.value }, G);
          WC = await apiGet('/contest/animeitor/webcast?contest=' + enc(CONTEST), G);
          lbl.value = ''; render();
        } catch (e) { msg(box, T('Falha: ', 'Failed: ') + (e.message || e), 'error-box'); }
      } }, T('+ Nova chave', '+ New key'))),
    box,
    keys.length ? el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {},
        el('th', {}, T('Placar', 'Board')), el('th', {}, 'URL'),
        el('th', { class: 'n' }, T('Buscas', 'Fetches')),
        el('th', {}, T('Último acesso', 'Last fetch')), el('th', {}, ''))),
      el('tbody', {}, ...keys.map(keyRow))))
      : el('p', { class: 'muted' }, T('Nenhuma chave criada ainda.', 'No key created yet.')),
  );
}

// ---------- render ------------------------------------------------------------
function render() {
  app.innerHTML = '';
  // a seção de fotos tem hospedeiro FIXO: filtro/página redesenham só ela (renderPhotos),
  // sem tocar nas chaves do streaming
  app.append(streamSection(), el('div', { class: 'section', id: 'photosSec' }));
  renderPhotos();
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">' + T('Contest não informado.', 'No contest given.') + '</div>'; return; }
  const { st } = await initContestShell(CONTEST);
  if (!st || !st.logged_in) { location.replace('/contest/?c=' + enc(CONTEST)); return; }
  if (!(st.is_animeitor || st.is_admin)) {
    app.innerHTML = '<div class="error-box">' + T('Esta área é da conta de placar (.animeitor).',
      'This area belongs to the scoreboard account (.animeitor).') + '</div>';
    return;
  }
  try {
    [WC] = await Promise.all([apiGet('/contest/animeitor/webcast?contest=' + enc(CONTEST), G), loadPhotos()]);
  } catch (e) {
    app.innerHTML = '<div class="error-box">' + (e.message || e) + '</div>'; return;
  }
  render();
}
boot();
