// contest/backup/backup.js — página de BACKUP de arquivos do usuário (não-privilegiado).
// Guardar versões de solução, listar, baixar e remover. Só o próprio usuário vê os seus.
import { apiGet, apiPost, getToken } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { fileToBase64 } from '/shared/auth.js';
import { initContestShell } from '/shared/contest-shell.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const G = { contest: CONTEST, auth: true };
const fmtDate = (e) => new Date((+e || 0) * 1000).toLocaleString('pt-BR');

async function downloadAuthed(path, filename) {
  const r = await fetch('/api/v1' + path, { headers: { 'Authorization': 'Bearer ' + (getToken(CONTEST) || '') } });
  if (!r.ok) { alert('Falha no download (HTTP ' + r.status + ')'); return; }
  const blob = await r.blob(); const url = URL.createObjectURL(blob);
  const a = el('a', { href: url, download: filename }); document.body.append(a); a.click();
  setTimeout(() => { a.remove(); URL.revokeObjectURL(url); }, 0);
}

const listBox = el('div', {});
async function loadList() {
  let r;
  try { r = await apiGet('/contest/backup?contest=' + encodeURIComponent(CONTEST), G); }
  catch (e) { listBox.innerHTML = ''; listBox.append(el('div', { class: 'error-box' }, 'Falha ao listar: ' + (e.message || 'erro'))); return; }
  const items = r.backups || [];
  listBox.innerHTML = '';
  if (!items.length) { listBox.append(el('p', { class: 'muted' }, 'Nenhum arquivo guardado ainda.')); return; }
  listBox.append(el('div', { class: 'small muted', style: 'margin:.2rem 0' }, items.length + ' arquivo(s).'));
  items.forEach((b) => {
    const kb = b.size ? Math.max(1, Math.round(b.size / 1024)) + ' KB' : '';
    listBox.append(el('div', { class: 'bk-row' },
      el('span', {}, el('b', {}, b.name), ' ', el('span', { class: 'small muted' }, (kb ? '· ' + kb + ' ' : '') + '· ' + fmtDate(b.time))),
      el('span', {},
        el('a', { href: '#', onclick: (e) => { e.preventDefault(); downloadAuthed('/contest/backup-file?contest=' + encodeURIComponent(CONTEST) + '&id=' + encodeURIComponent(b.id), b.name); } }, '⬇ baixar'),
        ' · ',
        el('a', { href: '#', class: 'small', onclick: async (e) => { e.preventDefault(); if (!confirm('Remover "' + b.name + '"?')) return; try { await apiPost('/contest/backup?contest=' + encodeURIComponent(CONTEST), { action: 'delete', id: b.id }, G); loadList(); } catch (ex) { alert(ex.message || 'falha'); } } }, '✕'))));
  });
}

function render() {
  app.innerHTML = '';
  const fileInput = el('input', { type: 'file' });
  const msg = el('span', { class: 'submit-steps' });
  const btn = el('button', { class: 'btn', type: 'button' }, 'Guardar arquivo');
  btn.addEventListener('click', async () => {
    const f = fileInput.files && fileInput.files[0];
    if (!f) { msg.innerHTML = '<span class="error-box small">Escolha um arquivo.</span>'; return; }
    btn.disabled = true; msg.textContent = 'Enviando…';
    try {
      await apiPost('/contest/backup?contest=' + encodeURIComponent(CONTEST), { filename: f.name, file_b64: await fileToBase64(f) }, G);
      msg.textContent = '✓ guardado'; fileInput.value = ''; loadList();
    } catch (ex) { msg.innerHTML = '<span class="error-box small">' + (ex.message || 'falha') + '</span>'; }
    finally { btn.disabled = false; }
  });
  app.append(
    el('div', { class: 'section' },
      el('h2', {}, 'Enviar arquivo'),
      el('div', { class: 'bk-up' }, fileInput, btn, msg),
      el('p', { class: 'small muted' }, 'Limite de 10 MB por arquivo.')),
    el('div', { class: 'section' }, el('h2', {}, 'Meus arquivos'), listBox));
  loadList();
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">Contest não informado.</div>'; return; }
  const { st } = await initContestShell(CONTEST);
  if (!st || !st.logged_in) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, '🔒 Entre no contest'),
      el('a', { class: 'btn', href: '/contest/?c=' + encodeURIComponent(CONTEST) }, 'Ir para o contest')));
    return;
  }
  render();
}
boot();
