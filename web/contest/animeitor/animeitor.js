// contest/animeitor/animeitor.js — a mesa do operador do TELÃO (.animeitor; o admin também
// entra). Duas seções: 📷 FOTOS E MÚSICAS dos times (galeria, trocar/remover, envio em lote pelo
// nome do arquivo, pacote .zip) e 🎥 STREAMING (as chaves do webcast que o sistema Animeitor
// busca em loop — ver docs/WEBCAST.md).
// A foto é gravada em WEBP pelo servidor (lib/team-photo.sh) e a música em MP3 como veio
// (lib/team-music.sh, sem ffmpeg em produção); aqui só se manda o arquivo.
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

let PHOTOS = null;   // {teams:[…], total, with_photo, with_music, scoped}
let WC = null;       // {keys:[…], views:[…], url_path}
// .cstaff (chefe de sede) entra na MESMA tela com menos poder (molde do staff.js): sobe foto e
// música só dos times da SEDE dele — o recorte é da API (staff-filters.json), aqui só se esconde
// o que ele não pode: as chaves do webcast e a troca do padrão do contest.
let RO = false;

// ESTADO DA GALERIA (prova de verdade tem 1000+ times): filtro + página. Abre em PENDÊNCIAS —
// quem falta foto OU música, que é a fila de trabalho inteira de quem opera o telão.
// `mode` é exclusivo: ou vale o recorte de pendências (um OU entre as duas famílias, que os chips
// por família não conseguem expressar), ou vale a combinação foto×música. Nunca os dois.
const F = { mode: 'pending', photo: 'all', music: 'all', q: '', cohort: '', univ: '', region: '' };
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
function syncPlay() {
  document.querySelectorAll('button.playbtn').forEach((b) => {
    const on = b.dataset.src === PLAYING;
    b.textContent = on ? '⏸' : '♪';
    b.classList.toggle('on', on);
  });
}
function toggleAudio(src) {
  if (PLAYING === src) { AUDIO.pause(); PLAYING = ''; }
  else { AUDIO.src = src; AUDIO.play().catch(() => { PLAYING = ''; syncPlay(); }); PLAYING = src; }
  syncPlay();
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
  Object.assign(t, { has_photo: true, format: r.format || 'webp', bytes: r.bytes || 0, mtime: Math.floor(Date.now() / 1000) });
  if (PHOTOS) PHOTOS.with_photo = PHOTOS.teams.filter((x) => x.has_photo).length;
  renderPhotos();
  if (box) msg(box, T('Foto atualizada: ', 'Photo updated: ') + (t.name || t.login), 'small');
}

// mesma ideia do sendPhoto: manda o mp3 do time e atualiza SÓ o cartão
async function sendMusic(t, file, box) {
  const b64 = await fileToBase64(file);
  const r = await apiPost('/contest/animeitor/music?contest=' + enc(CONTEST), { login: t.login, file_b64: b64 }, G);
  Object.assign(t, { has_music: true, music_bytes: r.bytes || 0, music_mtime: Math.floor(Date.now() / 1000) });
  if (PHOTOS) PHOTOS.with_music = PHOTOS.teams.filter((x) => x.has_music).length;
  renderPhotos();
  if (box) msg(box, T('Música atualizada: ', 'Music updated: ') + (t.name || t.login), 'small');
}

// a linha ♪ do cartão: tocar (a do time ou a padrão), enviar/trocar e remover
function musicRow(t, box) {
  const inp = el('input', { type: 'file', accept: 'audio/mpeg,.mp3', style: 'display:none' });
  inp.addEventListener('change', async () => {
    const f = inp.files && inp.files[0];
    if (!f) return;
    if (f.size > MUSIC_MAX_MB * 1024 * 1024) {
      msg(box, T(`Música muito grande (máx ${MUSIC_MAX_MB}MB).`, `Music too large (max ${MUSIC_MAX_MB}MB).`), 'error-box'); return;
    }
    msg(box, T('Enviando música de ', 'Uploading music of ') + t.login + '…');
    try { await sendMusic(t, f, box); }
    catch (e) { msg(box, T('Falha: ', 'Failed: ') + (e.message || e), 'error-box'); }
  });
  // botões da música são ÍCONES (⬆ / ×): o cartão tem ~170 px e os rótulos por extenso jogavam
  // o "remover" para uma segunda linha, deixando a grade com cartões de alturas diferentes
  return el('div', { class: 'acts mus' }, inp,
    playBtn(t.has_music ? musicUrl(t) : phMusicUrl(),
      t.has_music ? T('tocar a música do time', 'play the team music')
                  : T('tocar a música padrão', 'play the default music')),
    el('span', { class: 'lg' }, t.has_music
      ? `${Math.round((t.music_bytes || 0) / 1024)} KB`
      : T('padrão', 'default')),
    el('button', { class: 'btn ghost', onclick: () => inp.click(),
      title: t.has_music ? T('trocar a música', 'replace the music')
                         : T('enviar a música', 'upload the music') }, '⬆'),
    t.has_music ? el('button', { class: 'btn ghost danger',
      title: T('remover a música', 'remove the music'), onclick: async () => {
      if (!confirm(T('Remover a música de ', 'Remove the music of ') + (t.name || t.login) + '?')) return;
      try {
        await apiPost('/contest/animeitor/music?contest=' + enc(CONTEST), { action: 'delete', login: t.login }, G);
        Object.assign(t, { has_music: false, music_bytes: 0, music_mtime: 0 });
        if (PHOTOS) PHOTOS.with_music = PHOTOS.teams.filter((x) => x.has_music).length;
        renderPhotos();
      } catch (e) { msg(box, T('Falha: ', 'Failed: ') + (e.message || e), 'error-box'); }
    } }, '×') : '');
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
    el('option', { value: '' }, T('todas', 'all')),
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
    chip('all', T('Todos', 'All'), pool.length, ids[2]));
}

function photosBar(box) {
  const base = teamsAll().filter((t) => matchSel(t) && matchQ(t));
  const nPend = base.filter(isPending).length;
  // em modo família cada fileira conta com a OUTRA aplicada; em pendências, sobre a base pura
  const poolPhoto = F.mode === 'family' ? base.filter(matchMusic) : base;
  const poolMusic = F.mode === 'family' ? base.filter(matchPhoto) : base;

  const q = el('input', { id: 'fQ', class: 'filter', type: 'search',
    placeholder: T('buscar time, login, universidade…', 'search team, login, university…') });
  q.value = F.q;
  // debounce: com 1000 times o re-render a cada tecla seria perceptível
  q.addEventListener('input', debounce(() => { F.q = norm(q.value.trim()); PAGE_I = 0; renderPhotos(); }, 150));

  return el('div', { class: 'fbar' },
    // a FILA DE TRABALHO inteira num clique: falta foto, falta música, ou faltam as duas
    el('button', { id: 'fPending', class: 'btn ' + (F.mode === 'pending' ? '' : 'ghost'),
      title: T('times sem foto, sem música ou sem os dois',
               'teams missing a photo, missing music, or missing both'),
      onclick: () => { F.mode = 'pending'; F.photo = 'all'; F.music = 'all'; PAGE_I = 0; renderPhotos(); },
    }, `⚠ ${T('Pendências', 'To do')} (${nPend})`),
    chipRow('photo', T('Foto:', 'Photo:'), poolPhoto,
      [T('Sem foto', 'Missing'), T('Com foto', 'With photo')],
      ['fPhotoNo', 'fPhotoYes', 'fPhotoAll']),
    chipRow('music', T('Música:', 'Music:'), poolMusic,
      [T('Sem música', 'Missing'), T('Com música', 'With music')],
      ['fMusicNo', 'fMusicYes', 'fMusicAll']),
    selOf('cohort', T('Coorte:', 'Cohort:'), 'fCohort'),
    selOf('univ', T('Universidade:', 'University:'), 'fUniv'),
    RO ? '' : selOf('region', T('Sede:', 'Site:'), 'fRegion'),   // uma sede só: o select seria ruído
    q,
    // limpar é limpar: mostra TODOS (não volta a ligar o recorte de pendências)
    el('button', { id: 'fClear', class: 'btn ghost', onclick: () => {
      F.mode = 'family'; F.photo = 'all'; F.music = 'all';
      F.q = ''; F.cohort = ''; F.univ = ''; F.region = '';
      PAGE_I = 0; renderPhotos();
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

// linha da MÚSICA PADRÃO (dentro do cartão do padrão): é a que toca para quem não mandou a sua
function placeholderMusicRow(box) {
  const ph = (PHOTOS && PHOTOS.placeholder) || {};
  const custom = !!ph.music_custom;
  const inp = el('input', { type: 'file', accept: 'audio/mpeg,.mp3', style: 'display:none' });
  inp.addEventListener('change', async () => {
    const f = inp.files && inp.files[0];
    if (!f) return;
    if (f.size > MUSIC_MAX_MB * 1024 * 1024) {
      msg(box, T(`Música muito grande (máx ${MUSIC_MAX_MB}MB).`, `Music too large (max ${MUSIC_MAX_MB}MB).`), 'error-box'); return;
    }
    msg(box, T('Enviando a música padrão…', 'Uploading the default music…'));
    try {
      const r = await apiPost('/contest/animeitor/placeholder?contest=' + enc(CONTEST),
        { kind: 'music', file_b64: await fileToBase64(f) }, G);
      if (PHOTOS) PHOTOS.placeholder = { ...PHOTOS.placeholder, music_custom: r.music.custom, music_mtime: r.music.mtime };
      renderPhotos();
      msg(document.getElementById('phMsg') || box, T('Música padrão trocada.', 'Default music replaced.'), 'small');
    } catch (e) { msg(box, T('Falha: ', 'Failed: ') + (e.message || e), 'error-box'); }
  });
  return el('div', { class: 'row', style: 'gap:.3rem; margin-top:.35rem; align-items:center; flex-wrap:wrap' }, inp,
    playBtn(phMusicUrl(), T('tocar a música padrão', 'play the default music')),
    el('span', { class: 'small muted' }, T('Música padrão', 'Default music'),
      custom ? T(' · sua faixa', ' · your track') : T(' · a do MOJ', ' · the MOJ one')),
    // o chefe de sede ouve, mas não troca: o padrão é do contest inteiro
    RO ? '' : el('button', { class: 'btn ghost', onclick: () => inp.click() }, T('trocar música', 'replace music')),
    (custom && !RO) ? el('button', { class: 'btn ghost', onclick: async () => {
      if (!confirm(T('Voltar à música padrão do MOJ?', 'Restore the MOJ default music?'))) return;
      const r = await apiPost('/contest/animeitor/placeholder?contest=' + enc(CONTEST),
        { kind: 'music', action: 'reset' }, G);
      if (PHOTOS) PHOTOS.placeholder = { ...PHOTOS.placeholder, music_custom: r.music.custom, music_mtime: r.music.mtime };
      renderPhotos();
    } }, T('voltar ao padrão do MOJ', 'restore MOJ default')) : '');
}

// cartão do PADRÃO: a foto (e a música) que vão para o telão de quem não mandou as suas
function placeholderCard(box) {
  const custom = !!(PHOTOS && PHOTOS.placeholder && PHOTOS.placeholder.custom);
  const inp = el('input', { type: 'file', accept: 'image/*', style: 'display:none' });
  inp.addEventListener('change', async () => {
    const f = inp.files && inp.files[0];
    if (!f) return;
    if (f.size > 8 * 1024 * 1024) { msg(box, T('Imagem muito grande (máx 8MB).', 'Image too large (max 8MB).'), 'error-box'); return; }
    msg(box, T('Enviando a foto padrão…', 'Uploading the default photo…'));
    try {
      const r = await apiPost('/contest/animeitor/placeholder?contest=' + enc(CONTEST),
        { file_b64: await fileToBase64(f) }, G);
      if (PHOTOS) PHOTOS.placeholder = { ...PHOTOS.placeholder, custom: r.custom, mtime: r.mtime };
      renderPhotos();
      msg(document.getElementById('phMsg') || box, T('Foto padrão trocada.', 'Default photo replaced.'), 'small');
    } catch (e) { msg(box, T('Falha: ', 'Failed: ') + (e.message || e), 'error-box'); }
  });
  return el('div', { class: 'phdef' },
    el('img', { src: phUrl(true), alt: T('foto padrão', 'default photo'), loading: 'lazy' }),
    el('div', {},
      el('div', { class: 'nm' }, T('Foto padrão', 'Default photo'),
        el('span', { class: 'small muted' }, custom ? T(' · sua imagem', ' · your image')
                                                    : T(' · a do MOJ', ' · the MOJ one'))),
      el('div', { class: 'small muted' },
        T('É o que a API responde — e o que vai no pacote — para quem ainda não mandou a sua.',
          'This is what the API answers — and what goes in the package — for teams without their own.')),
      el('div', { class: 'row', style: 'gap:.3rem; margin-top:.35rem; align-items:center; flex-wrap:wrap' }, inp,
        RO ? '' : el('button', { class: 'btn ghost', onclick: () => inp.click() }, T('trocar imagem', 'replace image')),
        (custom && !RO) ? el('button', { class: 'btn ghost', onclick: async () => {
          if (!confirm(T('Voltar à foto padrão do MOJ?', 'Restore the MOJ default photo?'))) return;
          const r = await apiPost('/contest/animeitor/placeholder?contest=' + enc(CONTEST), { action: 'reset' }, G);
          if (PHOTOS) PHOTOS.placeholder = { ...PHOTOS.placeholder, custom: r.custom, mtime: r.mtime };
          renderPhotos();
        } }, T('voltar ao padrão do MOJ', 'restore MOJ default')) : ''),
      placeholderMusicRow(box)));
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

  const nP = (PHOTOS && PHOTOS.with_photo) || 0;
  const nM = (PHOTOS && PHOTOS.with_music) || 0;
  const nT = (PHOTOS && PHOTOS.total) || 0;
  host.innerHTML = '';
  host.append(
    el('h2', {}, T('📷 Fotos e ♪ músicas dos times', '📷 Team photos and ♪ music')),
    el('p', { class: 'note' },
      T(`${nP} de ${nT} times já têm foto; ${nM} têm música própria (o resto toca a padrão).`,
        `${nP} of ${nT} teams already have a photo; ${nM} have their own music (the rest play the default).`),
      // o recorte é da API (staff-filters): dizer isso evita o susto de "sumiram times"
      (PHOTOS && PHOTOS.scoped)
        ? el('span', { class: 'small muted' },
            T(' Você vê e gere apenas os times da SUA SEDE.', ' You see and manage only YOUR SITE’s teams.'))
        : ''),
    placeholderCard(box),
    el('div', { class: 'row', style: 'gap:.5rem; margin-bottom:.4rem; flex-wrap:wrap' }, bulkInput(box),
      el('button', { class: 'btn', onclick: () => document.getElementById('phBulk').click() },
        T('⬆ Enviar em lote — fotos e músicas (nome do arquivo = login)',
          '⬆ Bulk upload — photos and music (file name = login)')),
      el('button', { class: 'btn ghost', onclick: () => downloadAuthed(CONTEST,
          '/contest/animeitor/photos-zip?contest=' + enc(CONTEST), 'fotos-' + CONTEST + '.zip') },
        T('⬇ Baixar pacote (.zip)', '⬇ Download package (.zip)'))),
    photosBar(box), box,
    rows.length ? el('div', { class: 'gal' }, ...slice.map((t) => photoCard(t, box)))
                : el('p', { class: 'muted' }, T('Nenhum time casa com o filtro.', 'No team matches the filter.')),
    pager(pages),
  );
  syncPlay();                                        // o cartão que estava tocando continua ⏸
  const c = document.getElementById('fCount');
  if (c) c.textContent = (rows.length === teamsAll().length)
    ? T(`${rows.length} times`, `${rows.length} teams`)
    : T(`Mostrando ${rows.length} de ${teamsAll().length} times`, `Showing ${rows.length} of ${teamsAll().length} teams`);
}

// o lote aceita FOTO e MÚSICA no mesmo arrastar: cada arquivo vai para a rota certa pelo tipo
// (o MP3 é reconhecido pelo mime ou pela extensão — o Firefox não sabe o mime de todo .mp3)
const isMusicFile = (f) => /^audio\//.test(f.type || '') || /\.mp3$/i.test(f.name || '');

function bulkInput(box) {
  const bulk = el('input', { id: 'phBulk', type: 'file', accept: 'image/*,audio/mpeg,.mp3',
    multiple: true, style: 'display:none' });
  bulk.addEventListener('change', async () => {
    const fs = [...(bulk.files || [])];
    if (!fs.length) return;
    let okP = 0; let okM = 0; const bad = [];
    for (let i = 0; i < fs.length; i++) {
      msg(box, T('Enviando ', 'Uploading ') + (i + 1) + '/' + fs.length + '…');
      // o LOGIN vem do nome do arquivo (fulano.jpg / fulano.mp3 -> fulano), como no painel de Times
      const mus = isMusicFile(fs[i]);
      try {
        await apiPost('/contest/animeitor/' + (mus ? 'music' : 'photo') + '?contest=' + enc(CONTEST),
          { login: fs[i].name, file_b64: await fileToBase64(fs[i]) }, G);
        if (mus) okM++; else okP++;
      } catch { bad.push(fs[i].name); }
    }
    await loadPhotos(); renderPhotos();
    const b = document.getElementById('phMsg');
    if (b) msg(b, T(`${okP} foto(s) e ${okM} música(s) enviada(s).`, `${okP} photo(s) and ${okM} music file(s) uploaded.`)
      + (bad.length ? T(' Falharam (time inexistente ou formato recusado): ',
                        ' Failed (no such team or format rejected): ') + bad.join(', ') : ''),
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
  // sem tocar nas chaves do streaming (que o chefe de sede nem vê)
  app.append(RO ? '' : streamSection(), el('div', { class: 'section', id: 'photosSec' }));
  renderPhotos();
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">' + T('Contest não informado.', 'No contest given.') + '</div>'; return; }
  const { st } = await initContestShell(CONTEST);
  if (!st || !st.logged_in) { location.replace('/contest/?c=' + enc(CONTEST)); return; }
  if (!(st.is_animeitor || st.is_admin || st.is_cstaff)) {
    app.innerHTML = '<div class="error-box">' + T('Esta área é da conta de placar (.animeitor).',
      'This area belongs to the scoreboard account (.animeitor).') + '</div>';
    return;
  }
  RO = !!st.is_cstaff && !st.is_admin && !st.is_animeitor;
  try {
    // o cstaff NÃO pede as chaves (403 na API): pedir aqui derrubaria a página inteira no catch
    [WC] = await Promise.all([
      RO ? Promise.resolve(null) : apiGet('/contest/animeitor/webcast?contest=' + enc(CONTEST), G),
      loadPhotos()]);
  } catch (e) {
    app.innerHTML = '<div class="error-box">' + (e.message || e) + '</div>'; return;
  }
  render();
}
boot();
