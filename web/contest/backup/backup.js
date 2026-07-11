// contest/backup/backup.js — página de BACKUP de arquivos do usuário (não-privilegiado).
// Guardar versões de solução, listar, baixar e remover. Só o próprio usuário vê os seus.
import { apiGet, apiPost, getToken } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { fileToBase64 } from '/shared/auth.js';
import { initContestShell } from '/shared/contest-shell.js';
import { T } from '/shared/i18n.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const G = { contest: CONTEST, auth: true };
const fmtDate = (e) => new Date((+e || 0) * 1000).toLocaleString('pt-BR');

async function downloadAuthed(path, filename) {
  const r = await fetch('/api/v1' + path, { headers: { 'Authorization': 'Bearer ' + (getToken(CONTEST) || '') } });
  if (!r.ok) { alert(T('Falha no download (HTTP ', 'Download failed (HTTP ') + r.status + ')'); return; }
  const blob = await r.blob(); const url = URL.createObjectURL(blob);
  const a = el('a', { href: url, download: filename }); document.body.append(a); a.click();
  setTimeout(() => { a.remove(); URL.revokeObjectURL(url); }, 0);
}

const listBox = el('div', {});
async function loadList() {
  let r;
  try { r = await apiGet('/contest/backup?contest=' + encodeURIComponent(CONTEST), G); }
  catch (e) { listBox.innerHTML = ''; listBox.append(el('div', { class: 'error-box' }, T('Falha ao listar: ', 'Failed to list: ') + (e.message || T('erro', 'error')))); return; }
  const items = r.backups || [];
  listBox.innerHTML = '';
  if (!items.length) { listBox.append(el('p', { class: 'muted' }, T('Nenhum arquivo guardado ainda.', 'No files stored yet.'))); return; }
  listBox.append(el('div', { class: 'small muted', style: 'margin:.2rem 0' }, items.length + T(' arquivo(s).', ' file(s).')));
  items.forEach((b) => {
    const kb = b.size ? Math.max(1, Math.round(b.size / 1024)) + ' KB' : '';
    listBox.append(el('div', { class: 'bk-row' },
      el('span', {}, el('b', {}, b.name), ' ', el('span', { class: 'small muted' }, (kb ? '· ' + kb + ' ' : '') + '· ' + fmtDate(b.time))),
      el('span', {},
        el('a', { href: '#', onclick: (e) => { e.preventDefault(); downloadAuthed('/contest/backup-file?contest=' + encodeURIComponent(CONTEST) + '&id=' + encodeURIComponent(b.id), b.name); } }, T('⬇ baixar', '⬇ download')),
        ' · ',
        el('a', { href: '#', class: 'small', onclick: async (e) => { e.preventDefault(); if (!confirm(T('Remover "', 'Remove "') + b.name + '"?')) return; try { await apiPost('/contest/backup?contest=' + encodeURIComponent(CONTEST), { action: 'delete', id: b.id }, G); loadList(); } catch (ex) { alert(ex.message || T('falha', 'failed')); } } }, '✕'))));
  });
}

function render() {
  app.innerHTML = '';
  const fileInput = el('input', { type: 'file' });
  const msg = el('span', { class: 'submit-steps' });
  const btn = el('button', { class: 'btn', type: 'button' }, T('Guardar arquivo', 'Store file'));
  btn.addEventListener('click', async () => {
    const f = fileInput.files && fileInput.files[0];
    if (!f) { msg.innerHTML = '<span class="error-box small">' + T('Escolha um arquivo.', 'Choose a file.') + '</span>'; return; }
    btn.disabled = true; msg.textContent = T('Enviando…', 'Sending…');
    try {
      await apiPost('/contest/backup?contest=' + encodeURIComponent(CONTEST), { filename: f.name, file_b64: await fileToBase64(f) }, G);
      msg.textContent = T('✓ guardado', '✓ stored'); fileInput.value = ''; loadList();
    } catch (ex) { msg.innerHTML = '<span class="error-box small">' + (ex.message || T('falha', 'failed')) + '</span>'; }
    finally { btn.disabled = false; }
  });
  app.append(
    el('div', { class: 'section' },
      el('h2', {}, T('Enviar arquivo', 'Upload file')),
      el('div', { class: 'bk-up' }, fileInput, btn, msg),
      el('p', { class: 'small muted' }, T('Limite de 10 MB por arquivo.', '10 MB limit per file.'))),
    el('div', { class: 'section' }, el('h2', {}, T('Meus arquivos', 'My files')), listBox));
  loadList();
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">' + T('Contest não informado.', 'Contest not specified.') + '</div>'; return; }
  const { st } = await initContestShell(CONTEST);
  if (!st || !st.logged_in) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, T('🔒 Entre no contest', '🔒 Enter the contest')),
      el('a', { class: 'btn', href: '/contest/?c=' + encodeURIComponent(CONTEST) }, T('Ir para o contest', 'Go to the contest'))));
    return;
  }
  // sonda: se o admin desabilitou o backup, a API rejeita -> mostra aviso (sem formulário)
  try { await apiGet('/contest/backup?contest=' + encodeURIComponent(CONTEST), G); }
  catch (e) {
    if (e && e.code === 'backup_disabled') {
      app.innerHTML = '';
      app.append(el('div', { class: 'section' }, el('h2', {}, T('💾 Backup desabilitado', '💾 Backup disabled')),
        el('p', { class: 'muted' }, T('O administrador do contest desabilitou o backup de arquivos.', 'The contest administrator disabled file backup.'))));
      return;
    }
  }
  render();
}
boot();
