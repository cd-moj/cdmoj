// contest/animeitor/animeitor.js — a mesa do operador do TELÃO (.animeitor; o admin também
// entra). Duas seções: 📷 FOTOS dos times (galeria, trocar/remover, envio em lote pelo nome do
// arquivo, pacote .zip) e 🎥 STREAMING (as chaves do webcast que o sistema Animeitor busca em
// loop — ver docs/WEBCAST.md).
// A foto é gravada em WEBP pelo servidor (lib/team-photo.sh); aqui só se manda o arquivo.
import { apiGet, apiPost } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { fileToBase64 } from '/shared/auth.js';
import { initContestShell } from '/shared/contest-shell.js';
import { downloadAuthed, fmtDate } from '/shared/admin-ui.js';
import { T } from '/shared/i18n.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const G = { contest: CONTEST, auth: true };
const enc = encodeURIComponent;

let PHOTOS = null;   // {teams:[…], total, with_photo}
let WC = null;       // {keys:[…], views:[…], url_path}

const photoUrl = (login) =>
  `/api/v1/contest/team-photo?contest=${enc(CONTEST)}&user=${enc(login)}&t=${Date.now()}`;

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

async function sendPhoto(login, file, box) {
  const b64 = await fileToBase64(file);
  await apiPost('/contest/animeitor/photo?contest=' + enc(CONTEST), { login, file_b64: b64 }, G);
  await loadPhotos(); render();
  if (box) msg(box, T('Foto atualizada.', 'Photo updated.'), 'small');
}

function photoCard(t, box) {
  const inp = el('input', { type: 'file', accept: 'image/*', style: 'display:none' });
  inp.addEventListener('change', async () => {
    const f = inp.files && inp.files[0];
    if (!f) return;
    if (f.size > 8 * 1024 * 1024) { msg(box, T('Imagem muito grande (máx 8MB).', 'Image too large (max 8MB).'), 'error-box'); return; }
    msg(box, T('Enviando ', 'Uploading ') + t.login + '…');
    try { await sendPhoto(t.login, f, box); }
    catch (e) { msg(box, T('Falha: ', 'Failed: ') + (e.message || e), 'error-box'); }
  });
  return el('div', { class: 'card' },
    t.has_photo
      ? el('img', { class: 'ph', src: photoUrl(t.login), alt: t.name, loading: 'lazy' })
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
          await loadPhotos(); render();
        } catch (e) { msg(box, T('Falha: ', 'Failed: ') + (e.message || e), 'error-box'); }
      } }, T('remover', 'remove')) : ''),
  );
}

function photosSection() {
  const box = el('div', { class: 'small muted' });
  const bulk = el('input', { type: 'file', accept: 'image/*', multiple: true, style: 'display:none' });
  bulk.addEventListener('change', async () => {
    const fs = [...(bulk.files || [])];
    if (!fs.length) return;
    let ok = 0, bad = [];
    for (let i = 0; i < fs.length; i++) {
      msg(box, T('Enviando ', 'Uploading ') + (i + 1) + '/' + fs.length + '…');
      // o LOGIN vem do nome do arquivo (fulano.jpg -> fulano), como no painel de Times
      try { await apiPost('/contest/animeitor/photo?contest=' + enc(CONTEST),
              { login: fs[i].name, file_b64: await fileToBase64(fs[i]) }, G); ok++; }
      catch { bad.push(fs[i].name); }
    }
    await loadPhotos(); render();
    const b = document.getElementById('phMsg');
    if (b) msg(b, T(`${ok} foto(s) enviada(s).`, `${ok} photo(s) uploaded.`)
      + (bad.length ? T(' Não casaram com nenhum time: ', ' No team matched: ') + bad.join(', ') : ''),
      bad.length ? 'error-box' : 'small');
  });
  box.id = 'phMsg';

  const list = (PHOTOS && PHOTOS.teams) || [];
  const missing = list.filter((t) => !t.has_photo).length;
  return el('div', { class: 'section' },
    el('h2', {}, T('📷 Fotos dos times', '📷 Team photos')),
    el('p', { class: 'note' },
      T(`${(PHOTOS && PHOTOS.with_photo) || 0} de ${(PHOTOS && PHOTOS.total) || 0} times com foto`,
        `${(PHOTOS && PHOTOS.with_photo) || 0} of ${(PHOTOS && PHOTOS.total) || 0} teams with a photo`)
      + (missing ? T(` · ${missing} sem foto`, ` · ${missing} without one`) : '')),
    el('div', { class: 'row', style: 'gap:.5rem; margin-bottom:.7rem; flex-wrap:wrap' }, bulk,
      el('button', { class: 'btn', onclick: () => bulk.click() },
        T('⬆ Enviar em lote (nome do arquivo = login)', '⬆ Bulk upload (file name = login)')),
      el('button', { class: 'btn ghost', onclick: () => downloadAuthed(CONTEST,
          '/contest/animeitor/photos-zip?contest=' + enc(CONTEST), 'fotos-' + CONTEST + '.zip') },
        T('⬇ Baixar pacote (.zip)', '⬇ Download package (.zip)'))),
    box,
    el('div', { class: 'gal' }, ...list.map((t) => photoCard(t, box))),
  );
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
  app.append(streamSection(), photosSection());
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
