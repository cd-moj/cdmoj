// contest/admin/teams-tab.js — aba "👥 Times": gerência POR-USUÁRIO da identidade do time.
// O NOME é campo ÚNICO (`fullname` — usuário de contest É o time); aqui também vivem país
// (bandeira), sede/região, universidade (`.team` do account.json, que placar/badges/
// impressão leem), BRASÃO (logo.png) e FOTO (photo.png, com link clicável no placar).
// Carga única via CSV com cabeçalho (parseRichCsv), fotos/brasões em LOTE (arquivos
// <login>.<ext>, enviados 1-a-1 com progresso), e o botão "Materializar matches" que
// aplica as regras regex (teams-meta/regions) aos campos vazios de uma vez.
// Contest com usuários compartilhados (users_from): a aba desabilita (sem overlay local).
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { fileToBase64 } from '/shared/auth.js';
import { flagEl, flagManifest } from '/shared/flags.js';
import { parseRichCsv } from '/shared/users-batch.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;
const PRIV_RE = /\.(admin|judge|cjudge|staff|mon)$/;
const FIELDS = ['fullname', 'country', 'region', 'univ_short', 'univ_full'];

export function makeTeamsTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div', { class: 'section' });
  let ROWS = [];      // [{login, fullname, vals:{...FIELDS}, orig:{...}, has_logo, has_photo, els:{}}]
  let REGIONS = [];   // nomes de regiões p/ o datalist
  let FLAGS = null;   // manifesto de bandeiras (code -> nome)

  const assetUrl = (kind, login) =>
    `/api/v1/contest/team-${kind}?contest=${enc(CONTEST)}&user=${enc(login)}&t=${Date.now()}`;

  async function postAsset(body) {
    return apiPost('/contest/admin/team-assets?contest=' + enc(CONTEST), body, G);
  }

  // envia arquivos 1-a-1 (evita o teto de body do nginx) com progresso no msgEl
  async function sendFiles(files, kind, msgEl, after) {
    const errs = [];
    for (let i = 0; i < files.length; i++) {
      msgEl.className = 'small'; msgEl.textContent = T('Enviando ', 'Sending ') + kind + ' ' + (i + 1) + '/' + files.length + ' (' + files[i].name + ')…';
      try { await postAsset({ kind, filename: files[i].name, file_b64: await fileToBase64(files[i]) }); }
      catch (e) { errs.push(files[i].name + ': ' + (e.message || T('falha', 'failed'))); }
    }
    msgEl.className = errs.length ? 'small error-box' : 'small';
    msgEl.textContent = '✓ ' + (files.length - errs.length) + '/' + files.length + ' ' + kind + T('(s) salvas.', '(s) saved.') +
      (errs.length ? T(' Falhas: ', ' Failures: ') + errs.join(' · ') : '');
    if (after) after();
  }

  function dirtyRows() {
    return ROWS.filter((r) => FIELDS.some((f) => (r.vals[f] || '') !== (r.orig[f] || '')));
  }

  function rowEl(r) {
    const mk = (f, ph, style) => {
      const inp = el('input', { value: r.vals[f] || '', placeholder: ph, style: style || 'width:7.5rem' });
      inp.addEventListener('input', () => { r.vals[f] = inp.value.trim(); });
      r.els[f] = inp; return inp;
    };
    const country = mk('country', 'BR', 'width:4.5rem;text-transform:uppercase');
    country.setAttribute('list', 'teams-flags-dl');
    const flagBox = el('span', {});
    const syncFlag = () => { flagBox.innerHTML = ''; const fi = flagEl(r.vals.country, { height: 14 }); if (fi) flagBox.append(fi); };
    country.addEventListener('change', syncFlag); syncFlag();
    const region = mk('region', T('sede', 'site'), 'width:7rem'); region.setAttribute('list', 'teams-regions-dl');

    // brasão: preview + enviar/remover
    const logoBox = el('span', {});
    const syncLogo = () => {
      logoBox.innerHTML = '';
      if (r.has_logo) logoBox.append(el('img', { src: assetUrl('logo', r.login), style: 'height:18px;vertical-align:middle;border-radius:2px' }));
    };
    syncLogo();
    const logoInp = el('input', { type: 'file', accept: 'image/*', style: 'display:none' });
    logoInp.addEventListener('change', async () => {
      const f = logoInp.files[0]; logoInp.value = ''; if (!f) return;
      try { await postAsset({ kind: 'logo', filename: r.login + '.png', file_b64: await fileToBase64(f) }); r.has_logo = true; syncLogo(); }
      catch (e) { alert(e.message || T('falha', 'failed')); }
    });
    const logoDel = () => postAsset({ action: 'delete', kind: 'logo', login: r.login }).then(() => { r.has_logo = false; syncLogo(); }).catch(() => {});
    // foto: status + enviar/ver/remover
    const photoBox = el('span', {});
    const syncPhoto = () => {
      photoBox.innerHTML = '';
      if (r.has_photo) photoBox.append(el('a', { href: assetUrl('photo', r.login), target: '_blank', title: T('ver foto', 'view photo') }, '📷'));
      else photoBox.append(el('span', { class: 'muted' }, '—'));
    };
    syncPhoto();
    const photoInp = el('input', { type: 'file', accept: 'image/*', style: 'display:none' });
    photoInp.addEventListener('change', async () => {
      const f = photoInp.files[0]; photoInp.value = ''; if (!f) return;
      try { await postAsset({ kind: 'photo', filename: r.login + '.png', file_b64: await fileToBase64(f) }); r.has_photo = true; syncPhoto(); }
      catch (e) { alert(e.message || T('falha', 'failed')); }
    });
    const photoDel = () => postAsset({ action: 'delete', kind: 'photo', login: r.login }).then(() => { r.has_photo = false; syncPhoto(); }).catch(() => {});

    return el('tr', {},
      el('td', { class: 'small', style: 'font-family:var(--mono)' }, r.login),
      el('td', {}, mk('fullname', T('nome do time', 'team name'), 'width:11rem')),
      el('td', {}, country, ' ', flagBox),
      el('td', {}, region),
      el('td', {}, mk('univ_short', 'UnB', 'width:5rem')),
      el('td', {}, mk('univ_full', T('Universidade…', 'University…'), 'width:12rem')),
      el('td', {}, logoBox, ' ',
        el('button', { class: 'btn ghost small', title: T('enviar brasão', 'upload logo'), onclick: () => logoInp.click() }, '⬆'), logoInp,
        el('button', { class: 'btn ghost small', title: T('remover brasão', 'remove logo'), onclick: logoDel }, '✕')),
      el('td', {}, photoBox, ' ',
        el('button', { class: 'btn ghost small', title: T('enviar foto', 'upload photo'), onclick: () => photoInp.click() }, '⬆'), photoInp,
        el('button', { class: 'btn ghost small', title: T('remover foto', 'remove photo'), onclick: photoDel }, '✕')));
  }

  async function load() {
    panel.innerHTML = ''; panel.append(el('h2', {}, T('👥 Times', '👥 Teams')));
    let usersR, teamsR, regionsR;
    try {
      [usersR, teamsR, regionsR] = await Promise.all([
        apiGet('/contest/admin/users?contest=' + enc(CONTEST), G),
        apiGet('/contest/teams?contest=' + enc(CONTEST), G),
        apiGet('/contest/regions?contest=' + enc(CONTEST), G).catch(() => ({ regions: [] })),
      ]);
      if (!FLAGS) FLAGS = await flagManifest().catch(() => null);
    } catch (e) { panel.append(el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ') + (e.message || T('erro', 'error')))); return; }

    if (usersR.shared) {
      panel.append(el('div', { class: 'error-box' },
        T('Este contest usa usuários COMPARTILHADOS (users_from) — a gerência de times por-usuário não se aplica. ', 'This contest uses SHARED users (users_from) — per-user team management does not apply. '),
        T('Use as regras por regex em Aparência (teams-meta/regiões).', 'Use the regex rules in Appearance (teams-meta/regions).')));
      return;
    }

    const teams = (teamsR && teamsR.teams) || {};
    const rg = (regionsR && (regionsR.regions || regionsR)) || [];
    REGIONS = (Array.isArray(rg) ? rg : []).map((x) => x && x.name).filter(Boolean);
    ROWS = (usersR.users || [])
      .filter((u) => !u.admin && !PRIV_RE.test(u.login))
      .map((u) => {
        const t = teams[u.login] || {};
        const vals = { fullname: u.fullname || '', country: t.flag || '', region: t.region || '',
                       univ_short: t.univ_short || '', univ_full: t.univ_full || '' };
        return { login: u.login, vals, orig: { ...vals },
                 has_logo: !!t.has_logo, has_photo: !!t.has_photo, els: {} };
      });

    // datalists compartilhados (leves — um só p/ a tabela inteira)
    const flagsDl = el('datalist', { id: 'teams-flags-dl' });
    if (FLAGS) Object.keys(FLAGS).sort().forEach((code) => flagsDl.append(el('option', { value: code.toUpperCase() }, FLAGS[code])));
    const regionsDl = el('datalist', { id: 'teams-regions-dl' });
    REGIONS.forEach((n) => regionsDl.append(el('option', { value: n })));

    const msg = el('div', { class: 'small' });
    const tb = el('tbody');
    ROWS.forEach((r) => tb.append(rowEl(r)));
    const table = el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, 'Login'), el('th', {}, T('Nome (time)', 'Name (team)')), el('th', {}, T('País', 'Country')),
        el('th', {}, T('Sede', 'Site')), el('th', {}, 'Univ'), el('th', {}, T('Universidade', 'University')),
        el('th', {}, T('Brasão', 'Logo')), el('th', {}, T('Foto', 'Photo')))), tb));

    const save = el('button', { class: 'btn' }, T('Salvar times', 'Save teams'));
    save.addEventListener('click', async () => {
      const dirty = dirtyRows();
      if (!dirty.length) { msg.className = 'small'; msg.textContent = T('Nada mudou.', 'Nothing changed.'); return; }
      const set = {};
      dirty.forEach((r) => { set[r.login] = { ...r.vals }; });   // "" apaga o campo (semântica do set)
      save.disabled = true; msg.className = 'small'; msg.textContent = T('Salvando ', 'Saving ') + dirty.length + '…';
      try {
        const res = await apiPost('/contest/admin/teams?contest=' + enc(CONTEST), { set }, G);
        dirty.forEach((r) => { r.orig = { ...r.vals }; });
        msg.textContent = '✓ ' + (res.saved || 0) + T(' salvo(s)', ' saved') +
          ((res.skipped || []).length ? T(' · pulados: ', ' · skipped: ') + res.skipped.join(', ') : '');
      } catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
      save.disabled = false;
    });

    // materializar matches (regex teams-meta/regions -> campos vazios, de uma vez)
    const mat = el('button', { class: 'btn ghost' }, T('🪄 Materializar matches', '🪄 Materialize matches'));
    mat.addEventListener('click', async () => {
      if (!confirm(T('Aplicar as regras por regex (Aparência: teams-meta + regiões) aos campos VAZIOS de cada time? Campos já preenchidos não mudam.', 'Apply the regex rules (Appearance: teams-meta + regions) to the EMPTY fields of each team? Already-filled fields do not change.'))) return;
      mat.disabled = true; msg.className = 'small'; msg.textContent = T('Materializando…', 'Materializing…');
      try {
        const r = await apiPost('/contest/admin/teams?contest=' + enc(CONTEST), { action: 'materialize' }, G);
        msg.textContent = T('✓ preencheu ', '✓ filled ') + (r.materialized || 0) + T(' time(s).', ' team(s).');
        await load();
      } catch (e) { mat.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
    });

    // import/export CSV (cabeçalho, ordem livre) — casa por login
    const csvInp = el('input', { type: 'file', accept: '.csv,.txt,text/csv,text/plain', style: 'display:none' });
    csvInp.addEventListener('change', () => {
      const f = csvInp.files[0]; csvInp.value = ''; if (!f) return;
      const rd = new FileReader();
      rd.onload = () => {
        const rich = parseRichCsv(String(rd.result || ''));
        if (!rich) { msg.className = 'small error-box'; msg.textContent = T('CSV sem cabeçalho reconhecido (precisa da coluna login + time/pais/sede/univ…).', 'CSV without a recognized header (needs the login column + team/country/site/univ…).'); return; }
        const byLogin = {}; ROWS.forEach((r) => { byLogin[r.login.toLowerCase()] = r; });
        let hit = 0; const missed = [];
        rich.forEach((u) => {
          const r = byLogin[(u.login || '').toLowerCase()];
          if (!r) { missed.push(u.login); return; }
          hit++;
          FIELDS.forEach((k) => { if (u[k] !== undefined) { r.vals[k] = u[k]; if (r.els[k]) r.els[k].value = u[k]; } });
        });
        msg.className = missed.length ? 'small error-box' : 'small';
        msg.textContent = hit + T(' linha(s) aplicadas na tabela (confira e clique Salvar).', ' line(s) applied to the table (review and click Save).') +
          (missed.length ? T(' Sem usuário: ', ' No user: ') + missed.join(', ') : '');
      };
      rd.readAsText(f);
    });
    const csvExp = el('button', { class: 'btn ghost', onclick: () => {
      const head = 'login,nome,pais,sede,univ,univ_nome';
      const esc = (x) => '"' + String(x == null ? '' : x).replace(/"/g, '""') + '"';
      const rows = ROWS.map((r) => [r.login, r.vals.fullname, r.vals.country, r.vals.region, r.vals.univ_short, r.vals.univ_full].map(esc).join(','));
      const blob = new Blob([head + '\n' + rows.join('\n')], { type: 'text/csv' });
      const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = CONTEST + '-times.csv'; a.click(); URL.revokeObjectURL(a.href);
    } }, T('⬇ Exportar CSV', '⬇ Export CSV'));

    // fotos/brasões em LOTE: nome do arquivo = login
    const phInp = el('input', { type: 'file', accept: 'image/*', multiple: true, style: 'display:none' });
    phInp.addEventListener('change', () => { const fs = [...phInp.files]; phInp.value = ''; if (fs.length) sendFiles(fs, 'photo', msg, load); });
    const lgInp = el('input', { type: 'file', accept: 'image/*', multiple: true, style: 'display:none' });
    lgInp.addEventListener('change', () => { const fs = [...lgInp.files]; lgInp.value = ''; if (fs.length) sendFiles(fs, 'logo', msg, load); });

    panel.append(
      el('p', { class: 'muted small' },
        T('O NOME é um só: é o nome do time (ou do aluno — usuário de contest É o time). ', 'The NAME is a single one: it is the team name (or the student — a contest user IS the team). '),
        T('Cada linha é a identidade no account.json (placar, crachás e impressão leem daqui; ', 'Each row is the identity in account.json (scoreboard, badges and printing read from here; '),
        T('o que faltar continua sendo completado pelas regras regex da aba Aparência). ', 'whatever is missing keeps being completed by the regex rules in the Appearance tab). '),
        T('Fotos/brasões em lote: cada arquivo se chama <login>.<ext>.', 'Photos/logos in bulk: each file is named <login>.<ext>.')),
      el('div', { class: 'row', style: 'gap:.5rem;flex-wrap:wrap;margin-bottom:.5rem' },
        save, mat,
        el('button', { class: 'btn ghost', onclick: () => csvInp.click() }, T('📥 Importar CSV', '📥 Import CSV')), csvInp, csvExp,
        el('button', { class: 'btn ghost', onclick: () => phInp.click() }, T('📷 Fotos em lote', '📷 Photos in bulk')), phInp,
        el('button', { class: 'btn ghost', onclick: () => lgInp.click() }, T('🛡️ Brasões em lote', '🛡️ Logos in bulk')), lgInp,
        msg),
      flagsDl, regionsDl, table);
    if (!ROWS.length) panel.append(el('div', { class: 'muted', style: 'margin-top:.5rem' }, T('Nenhum competidor ainda — crie as contas na aba Usuários & sessões.', 'No competitor yet — create the accounts in the Users & sessions tab.')));
  }

  return { panel, load };
}
