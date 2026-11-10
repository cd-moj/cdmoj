// contest/animeitor/animeitor.js — a mesa do operador do TELÃO (.animeitor; o admin também
// entra). Três seções: 📡 ANIMEITOR (a API nova: o MOJ empurra evento, placares/sedes, submissões e
// relógio — api-section.js, docs/ANIMEITOR.md), 📷 FOTOS E MÚSICAS dos times (galeria, trocar/remover,
// envio em lote pelo nome do arquivo, pacote .zip) e, dobrado como LEGADO, o 🎥 STREAMING por chave
// (o zip no protocolo do BOCA que o Animeitor antigo buscava em loop — docs/WEBCAST.md).
// A foto é gravada em WEBP pelo servidor (lib/team-photo.sh) e a música em MP3 como veio
// (lib/team-music.sh, sem ffmpeg em produção); aqui só se manda o arquivo.
import { apiGet, apiPost } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { fileToBase64 } from '/shared/auth.js';
import { initContestShell } from '/shared/contest-shell.js';
import { downloadAuthed, fmtDate, norm, debounce } from '/shared/admin-ui.js';
import { T, uiLocale } from '/shared/i18n.js';
import { setMediaSrc, mediaLink, setAudioSrc, releaseMedia } from '/shared/media-auth.js';
import { makeApiSection } from './api-section.js';
import { roleCan } from '/shared/roles.js';           // registro dos papéis (GERADO de server/etc/roles.tsv)

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const G = { contest: CONTEST, auth: true };
const enc = encodeURIComponent;

let PHOTOS = null;   // {teams:[…], total, with_photo, with_music, scoped}
let WC = null;       // {keys:[…], views:[…], url_path}
let API = null;      // a seção da API do Animeitor ({node, load}) — só .animeitor/admin
let REVEAL = null;   // {released, scoped, sites[], links[], verify} — os links do REVELEITOR da sede (.cstaff/.staff)
// A SEDE entra na MESMA tela com menos poder (molde do staff.js), e o recorte de quais times ela
// vê é da API (staff-filters.json) — aqui só se esconde o que ela não pode:
//   RO      (.cstaff e .staff) — sem as chaves do webcast e sem trocar o PADRÃO do contest;
//   NOWRITE (.staff)           — sem NENHUMA escrita: nada de enviar/trocar/remover, lote ou zip.
let RO = false;
let NOWRITE = false;
// O QUE a conta escreve (09/11/2026: .foto e .musica — registro server/etc/roles.tsv, capacidades `foto`/`musica`):
// a API corta (role_can + escopo); aqui só não se oferece o botão que daria 403
let CAN_PHOTO = true;
let CAN_MUSIC = true;
let SITE_ORG = false;   // .cstaff/.staff: o cartão do Reveleitor da sede

// ESTADO DA GALERIA (prova de verdade tem 1000+ times): filtro + página. Abre em PENDÊNCIAS —
// quem falta foto OU música, que é a fila de trabalho inteira de quem opera o telão.
// `mode` é exclusivo: ou vale o recorte de pendências (um OU entre as duas famílias, que os chips
// por família não conseguem expressar), ou vale a combinação foto×música. Nunca os dois.
// q = o texto NORMALIZADO (o que o filtro compara); qRaw = o que a pessoa digitou (o que a caixa mostra: devolver o
// normalizado cortava o espaço e tirava os acentos no meio da digitação)
const F = { mode: 'pending', photo: 'all', music: 'all', q: '', qRaw: '', cohort: '', univ: '', region: '' };
let PAGE_I = 0;
const PAGE = 48;     // 48 cartões = a grade cheia; o DOM fica pequeno e só estas fotos baixam
const MUSIC_MAX_MB = 15;   // o mesmo teto do handler (contest/animeitor/music.sh)

// MINIATURA (thumb=1, ~7 KB em vez de 37 KB) e cache-buster ESTÁVEL (v=<mtime>): com
// `t=Date.now()` cada render rebaixava a imagem inteira de novo.
// a FOTO PADRÃO do contest — o que a API devolve para quem não mandou foto (e o que vai no
// pacote no lugar dele). O mtime fura o cache da pré-visualização quando o operador troca.
const phUrl = (thumb) => {
  const m = (PHOTOS && PHOTOS.placeholder && PHOTOS.placeholder.mtime) || 0;
  return `/api/v1/contest/placeholder?contest=${enc(CONTEST)}` + (thumb ? '&thumb=1' : '') + `&v=${m}`;
};

const photoUrl = (t, thumb) =>
  `/api/v1/contest/team-photo?contest=${enc(CONTEST)}&user=${enc(t.login)}`
  + (thumb ? '&thumb=1' : '') + `&v=${t.mtime || 0}`;

// ♪ MÚSICA do time (a faixa que o telão toca quando ele resolve) — mesmo cache-buster da foto
const musicUrl = (t) =>
  `/api/v1/contest/team-music?contest=${enc(CONTEST)}&user=${enc(t.login)}&v=${t.music_mtime || 0}`;
const phMusicUrl = () => {
  const m = (PHOTOS && PHOTOS.placeholder && PHOTOS.placeholder.music_mtime) || 0;
  return `/api/v1/contest/placeholder?contest=${enc(CONTEST)}&kind=music&v=${m}`;
};

// UM player para a página inteira (48 <audio> por página seria peso à toa, e o telão toca uma
// faixa por vez): o botão só troca o src. Quem estiver tocando volta a ♪ quando a faixa acaba.
const AUDIO = new Audio();
let PLAYING = '';
AUDIO.addEventListener('ended', () => { PLAYING = ''; syncPlay(); });
function syncPlay(mark) {
  document.querySelectorAll('button.playbtn').forEach((b) => {
    const on = b.dataset.src === PLAYING;
    b.textContent = on ? (mark || '⏸') : '♪';
    b.classList.toggle('on', on);
  });
}
// ⚠ `PLAYING` e o `data-src` do botão guardam a URL — ela é a identidade da faixa.
function toggleAudio(src) {
  if (PLAYING === src) { AUDIO.pause(); PLAYING = ''; syncPlay(); return; }
  PLAYING = src; syncPlay('⏳');   // ⏳ até o <audio> aceitar a faixa; costuma nem piscar
  setAudioSrc(AUDIO, src)
    .then(() => AUDIO.play())
    .then(() => { if (PLAYING === src) syncPlay(); })
    .catch(() => { if (PLAYING === src) { PLAYING = ''; syncPlay(); } });
}
const playBtn = (src, title) => el('button',
  { class: 'btn ghost playbtn', 'data-src': src, title, onclick: () => toggleAudio(src) }, '♪');

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
  // solta a URL VELHA do memo do media-auth ANTES de mexer no mtime (o `v=` faz parte da chave):
  // quem troca 300 fotos numa sessão não pode empurrar o cache inteiro para fora.
  releaseMedia(photoUrl(t, true)); releaseMedia(photoUrl(t, false));
  Object.assign(t, { has_photo: true, format: r.format || 'webp', bytes: r.bytes || 0, mtime: Math.floor(Date.now() / 1000) });
  if (PHOTOS) PHOTOS.with_photo = PHOTOS.teams.filter((x) => x.has_photo).length;
  renderPhotos();
  if (box) msg(box, T('Foto atualizada: ', 'Photo updated: ', 'Foto actualizada: ') + (t.name || t.login), 'small');
}

// mesma ideia do sendPhoto: manda o mp3 do time e atualiza SÓ o cartão
async function sendMusic(t, file, box) {
  const b64 = await fileToBase64(file);
  const r = await apiPost('/contest/animeitor/music?contest=' + enc(CONTEST), { login: t.login, file_b64: b64 }, G);
  releaseMedia(musicUrl(t));
  Object.assign(t, { has_music: true, music_bytes: r.bytes || 0, music_mtime: Math.floor(Date.now() / 1000) });
  if (PHOTOS) PHOTOS.with_music = PHOTOS.teams.filter((x) => x.has_music).length;
  renderPhotos();
  if (box) msg(box, T('Música atualizada: ', 'Music updated: ', 'Música actualizada: ') + (t.name || t.login), 'small');
}

// a linha ♪ do cartão: tocar (a do time ou a padrão), enviar/trocar e remover
function musicRow(t, box) {
  const inp = el('input', { type: 'file', accept: 'audio/mpeg,.mp3', style: 'display:none' });
  inp.addEventListener('change', async () => {
    const f = inp.files && inp.files[0];
    if (!f) return;
    if (f.size > MUSIC_MAX_MB * 1024 * 1024) {
      msg(box, T(`Música muito grande (máx ${MUSIC_MAX_MB}MB).`, `Music too large (max ${MUSIC_MAX_MB}MB).`, `Música demasiado grande (máx ${MUSIC_MAX_MB}MB).`), 'error-box'); return;
    }
    msg(box, T('Enviando música de ', 'Uploading music of ', 'Subiendo música de ') + t.login + '…');
    try { await sendMusic(t, f, box); }
    catch (e) { msg(box, T('Falha: ', 'Failed: ', 'Error: ') + (e.message || e), 'error-box'); }
  });
  // botões da música são ÍCONES (⬆ / ×): o cartão tem ~170 px e os rótulos por extenso jogavam
  // o "remover" para uma segunda linha, deixando a grade com cartões de alturas diferentes
  return el('div', { class: 'acts mus' }, inp,
    playBtn(t.has_music ? musicUrl(t) : phMusicUrl(),
      t.has_music ? T('tocar a música do time', 'play the team music', 'reproducir la música del equipo')
                  : T('tocar a música padrão', 'play the default music', 'reproducir la música predeterminada')),
    el('span', { class: 'lg' }, t.has_music
      ? `${Math.round((t.music_bytes || 0) / 1024)} KB`
      : T('padrão', 'default', 'predeterminado')),
    !CAN_MUSIC ? '' : el('button', { class: 'btn ghost', onclick: () => inp.click(),
      title: t.has_music ? T('trocar a música', 'replace the music', 'reemplazar la música')
                         : T('enviar a música', 'upload the music', 'subir la música') }, '⬆'),
    (t.has_music && CAN_MUSIC) ? el('button', { class: 'btn ghost danger',
      title: T('remover a música', 'remove the music', 'quitar la música'), onclick: async () => {
      if (!confirm(T('Remover a música de ', 'Remove the music of ', 'Quitar la música de ') + (t.name || t.login) + '?')) return;
      try {
        await apiPost('/contest/animeitor/music?contest=' + enc(CONTEST), { action: 'delete', login: t.login }, G);
        releaseMedia(musicUrl(t));
        Object.assign(t, { has_music: false, music_bytes: 0, music_mtime: 0 });
        if (PHOTOS) PHOTOS.with_music = PHOTOS.teams.filter((x) => x.has_music).length;
        renderPhotos();
      } catch (e) { msg(box, T('Falha: ', 'Failed: ', 'Error: ') + (e.message || e), 'error-box'); }
    } }, '×') : '');
}

function photoCard(t, box) {
  const inp = el('input', { type: 'file', accept: 'image/*', style: 'display:none' });
  inp.addEventListener('change', async () => {
    const f = inp.files && inp.files[0];
    if (!f) return;
    if (f.size > 8 * 1024 * 1024) { msg(box, T('Imagem muito grande (máx 8MB).', 'Image too large (max 8MB).', 'Imagen demasiado grande (máx 8MB).'), 'error-box'); return; }
    msg(box, T('Enviando ', 'Uploading ', 'Subiendo ') + t.login + '…');
    try { await sendPhoto(t, f, box); }
    catch (e) { msg(box, T('Falha: ', 'Failed: ', 'Error: ') + (e.message || e), 'error-box'); }
  });
  return el('div', { class: 'card' },
    t.has_photo
      // miniatura + lazy: só as fotos da página corrente são baixadas, e a 2ª visita vem do cache
      ? mediaLink(photoUrl(t, false), { title: T('ver em tamanho real', 'view full size', 'ver en tamaño real') },
          setMediaSrc(el('img', { class: 'ph', alt: t.name, loading: 'lazy', decoding: 'async' }),
                      photoUrl(t, true), { lazy: true }))
      : el('div', { class: 'ph none' }, T('sem foto', 'no photo', 'sin foto')),
    el('div', { class: 'nm' }, t.name || t.login),
    el('div', { class: 'lg' }, (t.univ ? '[' + t.univ + '] ' : '') + t.login),
    el('div', { class: 'lg' }, t.has_photo ? `${t.format} · ${Math.round((t.bytes || 0) / 1024)} KB` : ''),
    !CAN_PHOTO ? '' : el('div', { class: 'acts' }, inp,
      el('button', { class: 'btn ghost', onclick: () => inp.click() },
        t.has_photo ? T('trocar', 'replace', 'reemplazar') : T('enviar', 'upload', 'subir')),
      t.has_photo ? el('button', { class: 'btn ghost danger', onclick: async () => {
        if (!confirm(T('Remover a foto de ', 'Remove the photo of ', 'Quitar la foto de ') + (t.name || t.login) + '?')) return;
        try {
          await apiPost('/contest/animeitor/photo?contest=' + enc(CONTEST), { action: 'delete', login: t.login }, G);
          releaseMedia(photoUrl(t, true)); releaseMedia(photoUrl(t, false));
          Object.assign(t, { has_photo: false, format: '', bytes: 0, mtime: 0 });
          if (PHOTOS) PHOTOS.with_photo = PHOTOS.teams.filter((x) => x.has_photo).length;
          renderPhotos();
        } catch (e) { msg(box, T('Falha: ', 'Failed: ', 'Error: ') + (e.message || e), 'error-box'); }
      } }, T('remover', 'remove', 'quitar')) : ''),
    musicRow(t, box),
  );
}

// ---- filtro (tudo no cliente, sobre a lista já carregada) ----
const teamsAll = () => (PHOTOS && PHOTOS.teams) || [];
// os predicados são separados p/ a CONTAGEM VIVA dos chips: cada família ignora só a SI MESMA
// (faceta de verdade, como no /treino) — é o que faz o número do chip ser exatamente o número de
// cartões que aparecem ao clicar nele.
const matchQ = (t) => !F.q || norm(`${t.name} ${t.login} ${t.univ}`).includes(F.q);
const matchSel = (t) => (!F.cohort || t.cohort === F.cohort)
                     && (!F.univ || t.univ === F.univ)
                     && (!F.region || t.region === F.region);
const matchPhoto = (t) => F.photo === 'all' || (F.photo === 'yes' ? t.has_photo : !t.has_photo);
const matchMusic = (t) => F.music === 'all' || (F.music === 'yes' ? t.has_music : !t.has_music);
const isPending = (t) => !t.has_photo || !t.has_music;
// o recorte corrente: pendências OU a combinação das duas famílias
const matchMode = (t) => (F.mode === 'pending' ? isPending(t) : matchPhoto(t) && matchMusic(t));
const filtered = () => teamsAll().filter((t) => matchMode(t) && matchSel(t) && matchQ(t));

function selOf(field, label, id) {
  const vals = [...new Set(teamsAll().map((t) => t[field]).filter(Boolean))].sort();
  if (!vals.length) return '';
  const sel = el('select', { id },
    el('option', { value: '' }, T('todas', 'all', 'todas')),
    ...vals.map((v) => el('option', { value: v }, v)));
  sel.value = F[field] || '';
  sel.addEventListener('change', () => { F[field] = sel.value; PAGE_I = 0; renderPhotos(); });
  return el('label', {}, label, sel);
}

// uma fileira de chips por família (foto | música). O universo contado é o `pool`: em modo
// família, é a base JÁ com a OUTRA família aplicada (o número bate com a tela); em pendências,
// é a base pura — porque clicar num chip SAI do modo pendências, e é isso que vai aparecer.
function chipRow(fam, label, pool, labels, ids) {
  const has = (t) => (fam === 'photo' ? t.has_photo : t.has_music);
  const nYes = pool.filter(has).length;
  const chip = (key, txt, n, id) => el('button', {
    id,
    class: 'btn ' + (F.mode === 'family' && F[fam] === key ? '' : 'ghost'),
    onclick: () => { F.mode = 'family'; F[fam] = key; PAGE_I = 0; renderPhotos(); },
  }, `${txt} (${n})`);
  return el('div', { class: 'row', style: 'gap:.3rem; align-items:center' },
    el('span', { class: 'small muted' }, label),
    chip('no', labels[0], pool.length - nYes, ids[0]),
    chip('yes', labels[1], nYes, ids[1]),
    chip('all', T('Todos', 'All', 'Todos'), pool.length, ids[2]));
}

function photosBar(box) {
  const base = teamsAll().filter((t) => matchSel(t) && matchQ(t));
  const nPend = base.filter(isPending).length;
  // em modo família cada fileira conta com a OUTRA aplicada; em pendências, sobre a base pura
  const poolPhoto = F.mode === 'family' ? base.filter(matchMusic) : base;
  const poolMusic = F.mode === 'family' ? base.filter(matchPhoto) : base;

  const q = el('input', { id: 'fQ', class: 'filter', type: 'search',
    placeholder: T('buscar time, login, universidade…', 'search team, login, university…', 'buscar equipo, usuario, universidad…') });
  q.value = F.qRaw;
  // debounce: com 1000 times o re-render a cada tecla seria perceptível. O re-render recria esta caixa: o
  // renderPhotos devolve o foco e o cursor a ela
  q.addEventListener('input', debounce(() => { F.qRaw = q.value; F.q = norm(q.value.trim()); PAGE_I = 0; renderPhotos(); }, 150));

  return el('div', { class: 'fbar' },
    // a FILA DE TRABALHO inteira num clique: falta foto, falta música, ou faltam as duas
    el('button', { id: 'fPending', class: 'btn ' + (F.mode === 'pending' ? '' : 'ghost'),
      title: T('times sem foto, sem música ou sem os dois',
               'teams missing a photo, missing music, or missing both',
               'equipos sin foto, sin música o sin ambas'),
      onclick: () => { F.mode = 'pending'; F.photo = 'all'; F.music = 'all'; PAGE_I = 0; renderPhotos(); },
    }, `⚠ ${T('Pendências', 'To do', 'Pendientes')} (${nPend})`),
    chipRow('photo', T('Foto:', 'Photo:', 'Foto:'), poolPhoto,
      [T('Sem foto', 'Missing', 'Falta'), T('Com foto', 'With photo', 'Con foto')],
      ['fPhotoNo', 'fPhotoYes', 'fPhotoAll']),
    chipRow('music', T('Música:', 'Music:', 'Música:'), poolMusic,
      [T('Sem música', 'Missing', 'Falta'), T('Com música', 'With music', 'Con música')],
      ['fMusicNo', 'fMusicYes', 'fMusicAll']),
    selOf('cohort', T('Coorte:', 'Cohort:', 'Cohorte:'), 'fCohort'),
    selOf('univ', T('Universidade:', 'University:', 'Universidad:'), 'fUniv'),
    RO ? '' : selOf('region', T('Sede:', 'Site:', 'Sede:'), 'fRegion'),   // uma sede só: o select seria ruído
    q,
    // limpar é limpar: mostra TODOS (não volta a ligar o recorte de pendências)
    el('button', { id: 'fClear', class: 'btn ghost', onclick: () => {
      F.mode = 'family'; F.photo = 'all'; F.music = 'all';
      F.q = ''; F.qRaw = ''; F.cohort = ''; F.univ = ''; F.region = '';
      PAGE_I = 0; renderPhotos();
    } }, T('limpar', 'clear', 'limpiar')),
    el('span', { class: 'fcount', id: 'fCount' }, ''),
  );
}

// pager do padrão da casa (treino/problemas): ‹ página X / Y ›
function pager(pages) {
  if (pages <= 1) return '';
  return el('div', { class: 'row', style: 'gap:.4rem; align-items:center; margin:.5rem 0' },
    el('button', { class: 'btn ghost', onclick: () => { if (PAGE_I > 0) { PAGE_I--; renderPhotos(); } } }, '‹'),
    el('span', { class: 'small' }, ` ${T('página', 'page', 'página')} ${PAGE_I + 1} / ${pages} `),
    el('button', { class: 'btn ghost', onclick: () => { if (PAGE_I < pages - 1) { PAGE_I++; renderPhotos(); } } }, '›'));
}

// linha da MÚSICA PADRÃO (dentro do cartão do padrão): é a que toca para quem não mandou a sua
function placeholderMusicRow(box) {
  const ph = (PHOTOS && PHOTOS.placeholder) || {};
  const custom = !!ph.music_custom;
  const inp = el('input', { type: 'file', accept: 'audio/mpeg,.mp3', style: 'display:none' });
  inp.addEventListener('change', async () => {
    const f = inp.files && inp.files[0];
    if (!f) return;
    if (f.size > MUSIC_MAX_MB * 1024 * 1024) {
      msg(box, T(`Música muito grande (máx ${MUSIC_MAX_MB}MB).`, `Music too large (max ${MUSIC_MAX_MB}MB).`, `Música demasiado grande (máx ${MUSIC_MAX_MB}MB).`), 'error-box'); return;
    }
    msg(box, T('Enviando a música padrão…', 'Uploading the default music…', 'Subiendo la música predeterminada…'));
    try {
      const r = await apiPost('/contest/animeitor/placeholder?contest=' + enc(CONTEST),
        { kind: 'music', file_b64: await fileToBase64(f) }, G);
      if (PHOTOS) PHOTOS.placeholder = { ...PHOTOS.placeholder, music_custom: r.music.custom, music_mtime: r.music.mtime };
      renderPhotos();
      msg(document.getElementById('phMsg') || box, T('Música padrão trocada.', 'Default music replaced.', 'Música predeterminada reemplazada.'), 'small');
    } catch (e) { msg(box, T('Falha: ', 'Failed: ', 'Error: ') + (e.message || e), 'error-box'); }
  });
  return el('div', { class: 'row', style: 'gap:.3rem; margin-top:.35rem; align-items:center; flex-wrap:wrap' }, inp,
    playBtn(phMusicUrl(), T('tocar a música padrão', 'play the default music', 'reproducir la música predeterminada')),
    el('span', { class: 'small muted' }, T('Música padrão', 'Default music', 'Música predeterminada'),
      custom ? T(' · sua faixa', ' · your track', ' · tu pista') : T(' · a do MOJ', ' · the MOJ one', ' · la del MOJ')),
    // o chefe de sede ouve, mas não troca: o padrão é do contest inteiro
    RO ? '' : el('button', { class: 'btn ghost', onclick: () => inp.click() }, T('trocar música', 'replace music', 'reemplazar música')),
    (custom && !RO) ? el('button', { class: 'btn ghost', onclick: async () => {
      if (!confirm(T('Voltar à música padrão do MOJ?', 'Restore the MOJ default music?', '¿Restaurar la música predeterminada del MOJ?'))) return;
      const r = await apiPost('/contest/animeitor/placeholder?contest=' + enc(CONTEST),
        { kind: 'music', action: 'reset' }, G);
      if (PHOTOS) PHOTOS.placeholder = { ...PHOTOS.placeholder, music_custom: r.music.custom, music_mtime: r.music.mtime };
      renderPhotos();
    } }, T('voltar ao padrão do MOJ', 'restore MOJ default', 'restaurar la predeterminada del MOJ')) : '');
}

// cartão do PADRÃO: a foto (e a música) que vão para o telão de quem não mandou as suas
function placeholderCard(box) {
  const custom = !!(PHOTOS && PHOTOS.placeholder && PHOTOS.placeholder.custom);
  const inp = el('input', { type: 'file', accept: 'image/*', style: 'display:none' });
  inp.addEventListener('change', async () => {
    const f = inp.files && inp.files[0];
    if (!f) return;
    if (f.size > 8 * 1024 * 1024) { msg(box, T('Imagem muito grande (máx 8MB).', 'Image too large (max 8MB).', 'Imagen demasiado grande (máx 8MB).'), 'error-box'); return; }
    msg(box, T('Enviando a foto padrão…', 'Uploading the default photo…', 'Subiendo la foto predeterminada…'));
    try {
      const r = await apiPost('/contest/animeitor/placeholder?contest=' + enc(CONTEST),
        { file_b64: await fileToBase64(f) }, G);
      if (PHOTOS) PHOTOS.placeholder = { ...PHOTOS.placeholder, custom: r.custom, mtime: r.mtime };
      renderPhotos();
      msg(document.getElementById('phMsg') || box, T('Foto padrão trocada.', 'Default photo replaced.', 'Foto predeterminada reemplazada.'), 'small');
    } catch (e) { msg(box, T('Falha: ', 'Failed: ', 'Error: ') + (e.message || e), 'error-box'); }
  });
  return el('div', { class: 'phdef' },
    setMediaSrc(el('img', { alt: T('foto padrão', 'default photo', 'foto predeterminada'), loading: 'lazy' }), phUrl(true), { lazy: true }),
    el('div', {},
      el('div', { class: 'nm' }, T('Foto padrão', 'Default photo', 'Foto predeterminada'),
        el('span', { class: 'small muted' }, custom ? T(' · sua imagem', ' · your image', ' · tu imagen')
                                                    : T(' · a do MOJ', ' · the MOJ one', ' · la del MOJ'))),
      el('div', { class: 'small muted' },
        T('É o que a API responde — e o que vai no pacote — para quem ainda não mandou a sua.',
          'This is what the API answers — and what goes in the package — for teams without their own.',
          'Es lo que responde la API — y lo que va en el paquete — para quienes todavía no enviaron la suya.')),
      el('div', { class: 'row', style: 'gap:.3rem; margin-top:.35rem; align-items:center; flex-wrap:wrap' }, inp,
        RO ? '' : el('button', { class: 'btn ghost', onclick: () => inp.click() }, T('trocar imagem', 'replace image', 'reemplazar imagen')),
        (custom && !RO) ? el('button', { class: 'btn ghost', onclick: async () => {
          if (!confirm(T('Voltar à foto padrão do MOJ?', 'Restore the MOJ default photo?', '¿Restaurar la foto predeterminada del MOJ?'))) return;
          const r = await apiPost('/contest/animeitor/placeholder?contest=' + enc(CONTEST), { action: 'reset' }, G);
          if (PHOTOS) PHOTOS.placeholder = { ...PHOTOS.placeholder, custom: r.custom, mtime: r.mtime };
          renderPhotos();
        } }, T('voltar ao padrão do MOJ', 'restore MOJ default', 'restaurar la predeterminada del MOJ')) : ''),
      placeholderMusicRow(box)));
}

// re-render SÓ da seção de fotos (o streaming não é tocado por filtro/página)
function renderPhotos() {
  const host = document.getElementById('photosSec');
  if (!host) return;
  // a busca está DENTRO da seção recriada: quem digitava perdia o foco a cada pausa. Guarda foco e cursor e os
  // devolve à caixa nova no fim
  const act = document.activeElement;
  const typing = act && act.id === 'fQ' ? [act.selectionStart, act.selectionEnd] : null;
  const box = el('div', { class: 'small muted', id: 'phMsg' });
  const prev = document.getElementById('phMsg');
  if (prev) box.append(...prev.childNodes);           // preserva a mensagem do último upload

  const rows = filtered();
  const pages = Math.max(1, Math.ceil(rows.length / PAGE));
  if (PAGE_I >= pages) PAGE_I = pages - 1;
  const slice = rows.slice(PAGE_I * PAGE, PAGE_I * PAGE + PAGE);

  const nP = (PHOTOS && PHOTOS.with_photo) || 0;
  const nM = (PHOTOS && PHOTOS.with_music) || 0;
  const nT = (PHOTOS && PHOTOS.total) || 0;
  host.innerHTML = '';
  host.append(
    el('h2', {}, T('📷 Fotos e ♪ músicas dos times', '📷 Team photos and ♪ music', '📷 Fotos y ♪ música de los equipos')),
    el('p', { class: 'note' },
      T(`${nP} de ${nT} times já têm foto; ${nM} têm música própria (o resto toca a padrão).`,
        `${nP} of ${nT} teams already have a photo; ${nM} have their own music (the rest play the default).`,
        `${nP} de ${nT} equipos ya tienen foto; ${nM} tienen música propia (el resto reproduce la predeterminada).`),
      // o recorte é da API (staff-filters): dizer isso evita o susto de "sumiram times"
      (PHOTOS && PHOTOS.scoped)
        ? el('span', { class: 'small muted' }, NOWRITE
            ? T(' Você vê os times da SUA SEDE (somente leitura).', ' You see YOUR SITE’s teams (read-only).', ' Ves los equipos de TU SEDE (solo lectura).')
            : T(' Você vê e gere apenas os times da SUA SEDE.', ' You see and manage only YOUR SITE’s teams.', ' Ves y gestionas solo los equipos de TU SEDE.'))
        : ''),
    placeholderCard(box),
    // lote e pacote são ESCRITA/exportação: o .staff não tem nenhum dos dois
    NOWRITE ? '' : el('div', { class: 'row', style: 'gap:.5rem; margin-bottom:.4rem; flex-wrap:wrap' }, bulkInput(box),
      el('button', { class: 'btn', onclick: () => document.getElementById('phBulk').click() },
        T('⬆ Enviar em lote — fotos, músicas ou .zip (nome do arquivo = login)',
          '⬆ Bulk upload — photos, music or .zip (file name = login)',
          '⬆ Subir en lote — fotos, música o .zip (nombre del archivo = usuario)')),
      el('button', { class: 'btn ghost', onclick: () => downloadAuthed(CONTEST,
          '/contest/animeitor/photos-zip?contest=' + enc(CONTEST), 'fotos-' + CONTEST + '.zip') },
        T('⬇ Baixar pacote (.zip)', '⬇ Download package (.zip)', '⬇ Descargar paquete (.zip)'))),
    photosBar(box), box,
    rows.length ? el('div', { class: 'gal' }, ...slice.map((t) => photoCard(t, box)))
                : el('p', { class: 'muted' }, T('Nenhum time casa com o filtro.', 'No team matches the filter.', 'Ningún equipo coincide con el filtro.')),
    pager(pages),
  );
  if (typing) {
    const q = document.getElementById('fQ');
    if (q) { q.focus(); try { q.setSelectionRange(typing[0], typing[1]); } catch (e) { /* tipo sem seleção */ } }
  }
  syncPlay();                                        // o cartão que estava tocando continua ⏸
  const c = document.getElementById('fCount');
  if (c) c.textContent = (rows.length === teamsAll().length)
    ? T(`${rows.length} times`, `${rows.length} teams`, `${rows.length} equipos`)
    : T(`Mostrando ${rows.length} de ${teamsAll().length} times`, `Showing ${rows.length} of ${teamsAll().length} teams`, `Mostrando ${rows.length} de ${teamsAll().length} equipos`);
}


const isPhotoName = (n) => /\.(png|jpe?g|webp|gif|bmp)$/i.test(n || '');

// O LOTE (09/11/2026, pedido do Emílio): fotos, músicas e PACOTES .zip no mesmo seletor. O zip é aberto AQUI
// (shared/zip-read.js) e cada arquivo segue pela rota de sempre, um POST por arquivo — o servidor nunca descompacta.
// Antes de enviar, uma CONFERÊNCIA (dry-run): cada arquivo, o time que ele achou pelo nome (login), se é novo ou
// troca, e o que fica de fora (sem time, formato que não é foto/MP3, repetido). Nada sobe sem o "Enviar".
function bulkInput(box) {
  const bulk = el('input', { id: 'phBulk', type: 'file', accept: 'image/*,audio/mpeg,.mp3,.zip,application/zip',
    multiple: true, style: 'display:none' });
  bulk.addEventListener('change', async () => {
    const fs = [...(bulk.files || [])];
    bulk.value = '';                                       // escolher o mesmo arquivo de novo dispara de novo
    if (!fs.length) return;
    const items = [];
    try {
      for (const f of fs) {
        if (/\.zip$/i.test(f.name) || f.type === 'application/zip' || f.type === 'application/x-zip-compressed') {
          msg(box, T('Abrindo ', 'Opening ', 'Abriendo ') + f.name + '…');
          const { readZip } = await import('/shared/zip-read.js');
          for (const e of await readZip(f)) items.push({ name: e.base, from: f.name + ' › ' + e.name, blob: e.blob, size: e.size });
        } else items.push({ name: f.name, from: '', blob: async () => f, size: f.size });
      }
    } catch (e) { msg(box, T('Falha ao abrir o pacote: ', 'Failed to open the package: ', 'No se pudo abrir el paquete: ') + (e.message || e), 'error-box'); return; }
    showBulkPlan(box, bulkPlan(items));
  });
  return bulk;
}

// bulkPlan(items) → [{item, kind:'photo'|'music'|null, team, status}]  status: new | replace | no_team | format | dup
function bulkPlan(items) {
  const byLogin = new Map(teamsAll().map((t) => [String(t.login || '').toLowerCase(), t]));
  const seen = new Map();
  const plan = items.map((it) => {
    const kind = /\.mp3$/i.test(it.name) ? 'music' : (isPhotoName(it.name) ? 'photo' : null);
    const login = it.name.replace(/\.[^.]+$/, '').toLowerCase();
    const team = byLogin.get(login) || null;
    let status = !kind ? 'format' : (!team ? 'no_team' : ((kind === 'music' ? !CAN_MUSIC : !CAN_PHOTO) ? 'denied'
      : ((kind === 'music' ? team.has_music : team.has_photo) ? 'replace' : 'new')));
    const r = { item: it, kind, team, login, status };
    if (kind && team) {                                   // o MESMO time e tipo duas vezes: vale o último
      const k = kind + '|' + login;
      if (seen.has(k)) seen.get(k).status = 'dup';
      seen.set(k, r);
    }
    return r;
  });
  return plan;
}

const BULK_ST = {
  new: () => T('novo', 'new', 'nuevo'),
  replace: () => T('troca o atual', 'replaces the current one', 'reemplaza el actual'),
  no_team: () => T('nenhum time com esse login', 'no team with this login', 'ningún equipo con ese usuario'),
  format: () => T('não é foto nem MP3', 'not a photo or MP3', 'no es foto ni MP3'),
  dup: () => T('repetido (vale o último)', 'repeated (the last one counts)', 'repetido (vale el último)'),
  denied: () => T('sua conta não envia este tipo', 'your account does not upload this type', 'tu cuenta no sube este tipo'),
};

function showBulkPlan(box, plan) {
  const go = plan.filter((r) => r.status === 'new' || r.status === 'replace');
  const cnt = (st) => plan.filter((r) => r.status === st).length;
  const nP = go.filter((r) => r.kind === 'photo').length, nM = go.length - nP;
  box.innerHTML = '';
  const rows = plan.slice().sort((a, b) => (a.status === b.status ? a.item.name.localeCompare(b.item.name) : (['no_team', 'format', 'denied', 'dup', 'replace', 'new'].indexOf(a.status) - ['no_team', 'format', 'denied', 'dup', 'replace', 'new'].indexOf(b.status))));
  const LIM = 300;
  const tb = el('tbody', {}, ...rows.slice(0, LIM).map((r) => el('tr', {},
    el('td', {}, r.item.name, r.item.from ? el('div', { class: 'small muted' }, r.item.from) : ''),
    el('td', {}, r.kind === 'music' ? T('🎵 música', '🎵 music', '🎵 música') : r.kind === 'photo' ? T('📷 foto', '📷 photo', '📷 foto') : '—'),
    el('td', {}, r.team ? (r.team.login + (r.team.team || r.team.name ? ' — ' + (r.team.team || r.team.name) : '')) : '—'),
    el('td', { style: (r.status === 'new' || r.status === 'replace') ? '' : 'color:#B91C1C' }, BULK_ST[r.status]()))));
  const sendBtn = el('button', { class: 'btn' }, T(`⬆ Enviar ${go.length} arquivo(s)`, `⬆ Upload ${go.length} file(s)`, `⬆ Subir ${go.length} archivo(s)`));
  sendBtn.disabled = !go.length;
  const cancel = el('button', { class: 'btn ghost', onclick: () => msg(box, '') }, T('Cancelar', 'Cancel', 'Cancelar'));
  sendBtn.addEventListener('click', () => runBulk(box, go));
  box.append(el('div', { class: 'section', style: 'margin:.4rem 0' },
    el('h3', { style: 'margin:.1rem 0 .3rem' }, T('Conferência antes de enviar', 'Check before uploading', 'Revisión antes de subir')),
    el('p', { class: 'small' },
      T(`${nP} foto(s) e ${nM} música(s) vão subir (${cnt('replace')} troca(m) a atual). Fica de fora: ${cnt('no_team')} sem time, ${cnt('format')} em outro formato, ${cnt('dup')} repetido(s). O nome do arquivo (sem a extensão) é o login do time.`,
        `${nP} photo(s) and ${nM} music file(s) will be uploaded (${cnt('replace')} replace the current one). Left out: ${cnt('no_team')} without a team, ${cnt('format')} in another format, ${cnt('dup')} repeated. The file name (without the extension) is the team login.`,
        `Se subirán ${nP} foto(s) y ${nM} música(s) (${cnt('replace')} reemplaza(n) la actual). Quedan fuera: ${cnt('no_team')} sin equipo, ${cnt('format')} en otro formato, ${cnt('dup')} repetido(s). El nombre del archivo (sin la extensión) es el usuario del equipo.`)),
    el('div', { class: 'row', style: 'gap:.5rem; margin:.3rem 0' }, sendBtn, cancel),
    el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, T('Arquivo', 'File', 'Archivo')), el('th', {}, T('Tipo', 'Type', 'Tipo')),
        el('th', {}, T('Time', 'Team', 'Equipo')), el('th', {}, T('Situação', 'Status', 'Estado')))), tb)),
    plan.length > LIM ? el('p', { class: 'small muted' }, T(`… e mais ${plan.length - LIM}.`, `… and ${plan.length - LIM} more.`, `… y ${plan.length - LIM} más.`)) : ''));
}

async function runBulk(box, go) {
  let okP = 0; let okM = 0; const bad = [];
  for (let i = 0; i < go.length; i++) {
    const r = go[i];
    msg(box, T('Enviando ', 'Uploading ', 'Subiendo ') + (i + 1) + '/' + go.length + '…');
    try {
      const blob = await r.item.blob();
      await apiPost('/contest/animeitor/' + (r.kind === 'music' ? 'music' : 'photo') + '?contest=' + enc(CONTEST),
        { login: r.item.name, file_b64: await fileToBase64(blob) }, G);
      if (r.kind === 'music') okM++; else okP++;
    } catch { bad.push(r.item.name); }
  }
  await loadPhotos(); renderPhotos();
  const b = document.getElementById('phMsg');
  if (b) msg(b, T(`${okP} foto(s) e ${okM} música(s) enviada(s).`, `${okP} photo(s) and ${okM} music file(s) uploaded.`, `${okP} foto(s) y ${okM} archivo(s) de música subido(s).`)
    + (bad.length ? T(' Falharam (formato recusado pelo servidor): ',
                      ' Failed (format rejected by the server): ',
                      ' Fallaron (formato rechazado por el servidor): ') + bad.join(', ') : ''),
    bad.length ? 'error-box' : 'small');
}

// ---------- 🎥 streaming ------------------------------------------------------
function keyRow(k) {
  const url = wcUrl(k.key);
  const view = ((WC.views || []).find((v) => v.id === k.view) || {}).name || k.view;
  const revoked = k.revoked_at > 0;
  return el('tr', { class: revoked ? 'revoked' : '' },
    el('td', {}, el('b', {}, view), k.label ? el('div', { class: 'small muted' }, k.label) : ''),
    el('td', {}, revoked
      ? el('span', { class: 'small muted' }, T('revogada em ', 'revoked at ', 'revocada el ') + fmtDate(k.revoked_at))
      : el('span', { class: 'keyurl' }, url)),
    el('td', { class: 'n' }, String(k.fetches || 0)),
    el('td', { class: 'small muted' }, k.last_at
      ? fmtDate(k.last_at) + (k.last_ip ? ' · ' + k.last_ip : '')
      : T('nunca buscada', 'never fetched', 'nunca consultada')),
    el('td', {}, revoked ? '' : el('div', { class: 'row', style: 'gap:.3rem' },
      el('button', { class: 'btn ghost', onclick: async () => {
        try { await navigator.clipboard.writeText(url); alert(T('URL copiada.', 'URL copied.', 'URL copiada.')); }
        catch { prompt(T('Copie a URL:', 'Copy the URL:', 'Copia la URL:'), url); }
      } }, T('copiar', 'copy', 'copiar')),
      el('a', { class: 'btn ghost', href: url, target: '_blank' }, T('testar', 'test', 'probar')),
      el('button', { class: 'btn ghost danger', onclick: async () => {
        if (!confirm(T('Revogar esta chave? O Animeitor que a usa para de receber o placar.',
                       'Revoke this key? The Animeitor using it stops receiving the scoreboard.',
                       '¿Revocar esta clave? El Animeitor que la usa deja de recibir el marcador.'))) return;
        await apiPost('/contest/animeitor/webcast?contest=' + enc(CONTEST), { action: 'revoke', id: k.id }, G);
        WC = await apiGet('/contest/animeitor/webcast?contest=' + enc(CONTEST), G); render();
      } }, T('revogar', 'revoke', 'revocar')))),
  );
}

function streamSection() {
  const sel = el('select', {}, ...((WC.views || []).map((v) => el('option', { value: v.id }, v.name))));
  const lbl = el('input', { type: 'text', placeholder: T('apelido (ex.: telão principal)', 'label (e.g. main screen)', 'etiqueta (ej.: pantalla principal)'), style: 'max-width:16rem' });
  const box = el('div', { class: 'small muted' });
  const keys = (WC.keys || []);
  return el('div', { class: 'section' },
    el('h2', {}, T('🎥 Streaming de placar (Animeitor)', '🎥 Scoreboard streaming (Animeitor)', '🎥 Transmisión del marcador (Animeitor)')),
    el('p', { class: 'note' },
      T('Cada chave gera uma URL que o Animeitor busca em loop e devolve o pacote .zip no formato do BOCA (contest/runs/time/version). O placar do pacote vai SEMPRE descongelado — quem anima a virada é o Animeitor.',
        'Each key yields a URL the Animeitor polls, returning the .zip package in BOCA format (contest/runs/time/version). The package is ALWAYS unfrozen — the reveal animation is the Animeitor’s job.',
        'Cada clave genera una URL que el Animeitor consulta en bucle y devuelve el paquete .zip en el formato de BOCA (contest/runs/time/version). El marcador del paquete va SIEMPRE descongelado — quien anima la revelación es el Animeitor.')),
    el('p', { class: 'note' }, '⚠ ',
      T('Quem tem a URL vê o placar descongelado durante a prova. Trate como senha e revogue depois do evento.',
        'Whoever holds the URL sees the unfrozen scoreboard during the contest. Treat it as a password and revoke it after the event.',
        'Quien tenga la URL ve el marcador descongelado durante la competencia. Trátala como una contraseña y revócala después del evento.')),
    el('div', { class: 'row', style: 'gap:.5rem; align-items:center; flex-wrap:wrap; margin:.6rem 0' },
      el('span', { class: 'small muted' }, T('Placar:', 'Board:', 'Marcador:')), sel, lbl,
      el('button', { class: 'btn', onclick: async () => {
        msg(box, T('Criando…', 'Creating…', 'Creando…'));
        try {
          await apiPost('/contest/animeitor/webcast?contest=' + enc(CONTEST),
            { action: 'create', view: sel.value, label: lbl.value }, G);
          WC = await apiGet('/contest/animeitor/webcast?contest=' + enc(CONTEST), G);
          lbl.value = ''; render();
        } catch (e) { msg(box, T('Falha: ', 'Failed: ', 'Error: ') + (e.message || e), 'error-box'); }
      } }, T('+ Nova chave', '+ New key', '+ Nueva clave'))),
    box,
    keys.length ? el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {},
        el('th', {}, T('Placar', 'Board', 'Marcador')), el('th', {}, 'URL'),
        el('th', { class: 'n' }, T('Buscas', 'Fetches', 'Consultas')),
        el('th', {}, T('Último acesso', 'Last fetch', 'Última consulta')), el('th', {}, ''))),
      el('tbody', {}, ...keys.map(keyRow))))
      : el('p', { class: 'muted' }, T('Nenhuma chave criada ainda.', 'No key created yet.', 'Todavía no se creó ninguna clave.')),
  );
}

// ---------- 🎬 reveleitor da SEDE (.cstaff/.staff) ------------------------------
// A revelação do Animeitor tem um link SECRETO por sede (mostra as respostas depois do congelamento).
// O `.animeitor` libera; a API devolve a esta conta SÓ os da sede dela (staff-filters), em todos os
// placares em que a sede aparece. Sem liberação o cartão não existe; sem sede definida, avisa.
// `verify` = a CONFERÊNCIA do MOJ só das sedes dela: o Animeitor tem todas as submissões? "Validado" = a
// prova acabou p/ todas as sedes, nada pendente e tudo bate — é o sinal verde p/ a cerimônia.
function verifyBadge(v) {
  if (!v || !v.at) return el('p', { class: 'muted small' }, T('O MOJ ainda não conferiu o Animeitor para a sua sede.', 'MOJ has not checked the Animeitor for your site yet.', 'El MOJ todavía no verificó el Animeitor para tu sede.'));
  const at = new Date((v.final ? (v.final_at || v.at) : v.at) * 1000).toLocaleTimeString(uiLocale());
  if (v.final) return el('p', { class: 'small', style: 'color:var(--ok,#1e7e34);font-weight:600' }, '✓ ', T(`Validado (${at}): a prova acabou e o Animeitor tem todas as submissões da sua sede.`, `Validated (${at}): the contest is over and the Animeitor has every submission of your site.`, `Validado (${at}): la competencia terminó y el Animeitor tiene todos los envíos de tu sede.`));
  if (v.ok) return el('p', { class: 'small' }, '✓ ', T(`Conferido às ${at}: o Animeitor tem todas as submissões da sua sede. A validação final sai quando a prova acabar para todas as sedes e nada estiver em julgamento.`,
    `Checked at ${at}: the Animeitor has every submission of your site. The final validation comes when the contest is over for every site and nothing is being judged.`,
    `Verificado a las ${at}: el Animeitor tiene todos los envíos de tu sede. La validación final llega cuando la competencia termine para todas las sedes y nada esté en evaluación.`));
  return el('p', { class: 'error-box' }, '⚠ ', T(`Na última conferência (${at}) o Animeitor NÃO tinha todas as submissões da sua sede. O MOJ já reenviou e confere de novo em instantes; espere o "validado" antes da cerimônia ou fale com o operador do telão.`,
    `At the last check (${at}) the Animeitor did NOT have every submission of your site. MOJ has already resent them and checks again shortly; wait for "validated" before the ceremony or talk to the big-screen operator.`,
    `En la última verificación (${at}) el Animeitor NO tenía todos los envíos de tu sede. El MOJ ya los reenvió y vuelve a verificar en instantes; espera el "validado" antes de la ceremonia o habla con el operador de la pantalla.`));
}
function revealCard() {
  const R = REVEAL; if (!R || !R.released) return '';
  const copy = (u) => el('button', { class: 'btn ghost', onclick: async () => { try { await navigator.clipboard.writeText(u); } catch { prompt(T('Copie:', 'Copy:', 'Copia:'), u); } } }, T('copiar', 'copy', 'copiar'));
  const body = [];
  if (!R.scoped) body.push(el('div', { class: 'error-box' }, T('A sua conta não tem sede definida, então não há link para mostrar. Peça ao administrador do contest para definir a sua sede (Pessoas › escopo do staff).',
    'Your account has no site defined, so there is no link to show. Ask the contest administrator to define your site (People › staff scope).',
    'Tu cuenta no tiene sede definida, así que no hay enlace para mostrar. Pídele al administrador de la competencia que defina tu sede (Personas › alcance del staff).')));
  else if (!(R.links || []).length) body.push(el('p', { class: 'muted' }, T('Não há link de revelação para a sua sede (' + (R.sites || []).join(', ') + '). Avise o operador do telão.',
    'There is no reveal link for your site (' + (R.sites || []).join(', ') + '). Tell the big-screen operator.',
    'No hay enlace de revelación para tu sede (' + (R.sites || []).join(', ') + '). Avisa al operador de la pantalla.')));
  else body.push(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
    el('thead', {}, el('tr', {}, el('th', {}, T('Placar', 'Scoreboard', 'Marcador')), el('th', {}, T('Sede', 'Site', 'Sede')), el('th', {}, ''))),
    el('tbody', {}, ...R.links.map((x) => el('tr', {}, el('td', {}, el('b', {}, x.contest)), el('td', {}, x.site),
      el('td', {}, el('div', { class: 'row', style: 'gap:.4rem' },
        el('a', { class: 'btn', href: x.url, target: '_blank', rel: 'noopener' }, T('abrir a revelação', 'open the reveal', 'abrir la revelación')), copy(x.url)))))))));
  return el('div', { class: 'section', id: 'reveleitor' },
    el('h2', {}, T('🎬 Reveleitor da sua sede', '🎬 Reveal for your site', '🎬 Reveleitor de tu sede')),
    el('p', { class: 'note' }, '⚠ ', T('Este link mostra as respostas reais depois do congelamento do placar. Abra só no computador do telão da sede, na hora da cerimônia, e não repasse.',
      'This link shows the real answers after the scoreboard freeze. Open it only on the site big-screen computer, at ceremony time, and do not pass it on.',
      'Este enlace muestra las respuestas reales después del congelamiento del marcador. Ábrelo solo en la computadora de la pantalla de la sede, a la hora de la ceremonia, y no lo compartas.')),
    R.scoped && (R.links || []).length ? verifyBadge(R.verify) : '',
    ...body);
}

// ---------- render ------------------------------------------------------------
function render() {
  app.innerHTML = '';
  // a seção de fotos tem hospedeiro FIXO: filtro/página redesenham só ela (renderPhotos),
  // sem tocar nas chaves do streaming (que o chefe de sede nem vê)
  // o streaming por chave (zip do BOCA) é LEGADO: fica dobrado, abaixo da integração nova. O nó da
  // seção nova é o MESMO a cada render (o estado dela — tabela em edição, timer — não se perde).
  app.append((RO && SITE_ORG) ? revealCard() : '', RO || !API ? '' : API.node,
    RO ? '' : el('details', { class: 'section', open: (WC && (WC.keys || []).some((k) => !k.revoked_at)) ? true : null },
      el('summary', { style: 'cursor:pointer' }, T('🎥 Webcast BOCA (legado): o pacote .zip que o Animeitor antigo busca por chave', '🎥 BOCA webcast (legacy): the .zip package the old Animeitor polls by key', '🎥 Webcast BOCA (legado): el paquete .zip que el Animeitor antiguo consulta por clave')),
      streamSection()),
    el('div', { class: 'section', id: 'photosSec' }));
  renderPhotos();
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">' + T('Contest não informado.', 'No contest given.', 'No se indicó ninguna competencia.') + '</div>'; return; }
  const { st } = await initContestShell(CONTEST, { alerts: false });   // a mesa do telão: sem banner
  if (!st || !st.logged_in) { location.replace('/contest/?c=' + enc(CONTEST)); return; }
  const role = st.role || '';
  if (!(st.is_animeitor || st.is_admin || st.is_cstaff || st.is_staff || role === 'foto' || role === 'musica')) {
    app.innerHTML = '<div class="error-box">' + T('Esta área é da conta de placar (.animeitor).',
      'This area belongs to the scoreboard account (.animeitor).',
      'Esta área es de la cuenta de marcador (.animeitor).') + '</div>';
    return;
  }
  RO = !!(st.is_cstaff || st.is_staff || role === 'foto' || role === 'musica') && !st.is_admin && !st.is_animeitor;
  CAN_PHOTO = !!st.is_admin || roleCan(st.login, 'foto');
  CAN_MUSIC = !!st.is_admin || roleCan(st.login, 'musica');
  NOWRITE = !CAN_PHOTO && !CAN_MUSIC;                 // .staff puro: só olha e ouve
  SITE_ORG = !!(st.is_cstaff || st.is_staff);         // o cartão do Reveleitor é da organização da sede
  try {
    // o cstaff NÃO pede as chaves (403 na API): pedir aqui derrubaria a página inteira no catch
    // (o reveleitor da sede é opcional: rota ainda não deployada ou telão fora do ar não derruba a galeria)
    [WC, , REVEAL] = await Promise.all([
      RO ? Promise.resolve(null) : apiGet('/contest/animeitor/webcast?contest=' + enc(CONTEST), G),
      loadPhotos(),
      (RO && SITE_ORG) ? apiGet('/contest/animeitor/reveal?contest=' + enc(CONTEST), G).catch(() => null) : Promise.resolve(null)]);
  } catch (e) {
    app.innerHTML = '<div class="error-box">' + (e.message || e) + '</div>'; return;
  }
  render();
  // a seção nova carrega DEPOIS e por conta própria: falha nela (servidor do telão fora do ar, rota
  // ainda não deployada) não pode apagar a galeria
  if (!RO) {
    API = makeApiSection(CONTEST, G);
    API.load().then(() => render()).catch((e) => { API.node.innerHTML = ''; API.node.append(el('h2', {}, T('📡 Animeitor (telão)', '📡 Animeitor (big screen)', '📡 Animeitor (pantalla)')), el('div', { class: 'error-box' }, e.message || String(e))); render(); });
  }
}
boot();
