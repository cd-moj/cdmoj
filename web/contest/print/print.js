// contest/print/print.js — página do ALUNO: pedir impressão de um arquivo e acompanhar
// o status (pendente → processada → entregue). Só o próprio usuário vê os seus pedidos.
import { apiGet, apiPost, getToken } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { fileToBase64 } from '/shared/auth.js';
import { initContestShell } from '/shared/contest-shell.js';
import { T } from '/shared/i18n.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const G = { contest: CONTEST, auth: true };
const enc = encodeURIComponent;
const fmtDate = (e) => new Date((+e || 0) * 1000).toLocaleString('pt-BR');

const STATUS = {
  pending:   { t: T('🕓 pendente', '🕓 pending'),     c: '' },
  printed:   { t: T('🖨️ processada', '🖨️ processed'), c: 'color:#0a7' },
  delivered: { t: T('✅ entregue', '✅ delivered'),    c: 'color:#0a7; font-weight:600' },
};

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
  try { r = await apiGet('/contest/print?contest=' + enc(CONTEST), G); }
  catch (e) { listBox.innerHTML = ''; listBox.append(el('div', { class: 'error-box' }, T('Falha ao listar: ', 'Failed to list: ') + (e.message || T('erro', 'error')))); return; }
  const items = r.requests || [];
  listBox.innerHTML = '';
  if (!items.length) { listBox.append(el('p', { class: 'muted' }, T('Nenhum pedido de impressão ainda.', 'No printing requests yet.'))); return; }
  listBox.append(el('div', { class: 'small muted', style: 'margin:.2rem 0' }, items.length + T(' pedido(s).', ' request(s).')));
  items.forEach((b) => {
    const st = STATUS[b.status] || STATUS.pending;
    const pg = (b.pages > 0 && b.status !== 'pending') ? ' · ' + b.pages + T(' pág.', ' pg.') : '';
    listBox.append(el('div', { class: 'bk-row' },
      el('span', {},
        el('b', {}, '#' + b.seq + ' '), b.filename, ' ',
        el('span', { class: 'small muted' }, '· ' + fmtDate(b.time) + pg)),
      el('span', {},
        el('span', { class: 'pr-badge', style: st.c }, st.t), ' ',
        el('a', { href: '#', class: 'small', onclick: (e) => { e.preventDefault(); downloadAuthed('/contest/print-file?contest=' + enc(CONTEST) + '&id=' + enc(b.id), b.filename); } }, T('⬇ meu arquivo', '⬇ my file')))));
  });
}

function render() {
  app.innerHTML = '';
  const fileInput = el('input', { type: 'file', accept: '.pdf,.txt,.c,.cpp,.cc,.py,.java,.js,.png,.jpg,.jpeg,.gif,image/*,text/*,application/pdf' });
  const msg = el('span', { class: 'submit-steps' });
  const btn = el('button', { class: 'btn', type: 'button' }, T('Pedir impressão', 'Request printing'));
  btn.addEventListener('click', async () => {
    const f = fileInput.files && fileInput.files[0];
    if (!f) { msg.innerHTML = '<span class="error-box small">' + T('Escolha um arquivo.', 'Choose a file.') + '</span>'; return; }
    btn.disabled = true; msg.textContent = T('Enviando…', 'Sending…');
    try {
      const r = await apiPost('/contest/print?contest=' + enc(CONTEST), { filename: f.name, file_b64: await fileToBase64(f) }, G);
      msg.textContent = T('✓ pedido #', '✓ request #') + r.seq + T(' enviado', ' sent'); fileInput.value = ''; loadList();
    } catch (ex) { msg.innerHTML = '<span class="error-box small">' + (ex.message || T('falha', 'failed')) + '</span>'; }
    finally { btn.disabled = false; }
  });
  app.append(
    el('div', { class: 'section' },
      el('h2', {}, T('Novo pedido', 'New request')),
      el('div', { class: 'bk-up' }, fileInput, btn, msg),
      el('p', { class: 'small muted' }, T('PDF, imagem, texto ou código-fonte. Limite de 10 MB. O arquivo é impresso com uma folha de rosto com o nome do seu time e um número de conferência.', 'PDF, image, text or source code. 10 MB limit. The file is printed with a cover sheet showing your team name and a reference number.'))),
    el('div', { class: 'section' }, el('h2', {}, T('Meus pedidos', 'My requests')), listBox));
  loadList();
}

function unavailable(title, txt) {
  app.innerHTML = '';
  app.append(el('div', { class: 'section' }, el('h2', {}, title), el('p', { class: 'muted' }, txt)));
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">' + T('Contest não informado.', 'Contest not specified.') + '</div>'; return; }
  const { st } = await initContestShell(CONTEST);
  if (!st || !st.logged_in) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, T('🔒 Entre no contest', '🔒 Enter the contest')),
      el('a', { class: 'btn', href: '/contest/?c=' + enc(CONTEST) }, T('Ir para o contest', 'Go to the contest'))));
    return;
  }
  // sonda: impressão indisponível (sem staff) ou desabilitada pelo admin
  let r;
  try { r = await apiGet('/contest/print?contest=' + enc(CONTEST), G); }
  catch (e) {
    if (e && e.code === 'print_disabled') return unavailable(T('🖨️ Impressão desabilitada', '🖨️ Printing disabled'), T('O administrador do contest desabilitou os pedidos de impressão.', 'The contest administrator disabled printing requests.'));
    if (e && e.code === 'print_unavailable') return unavailable(T('🖨️ Impressão indisponível', '🖨️ Printing unavailable'), T('Não há equipe de impressão neste contest.', 'There is no printing staff in this contest.'));
    return unavailable(T('🖨️ Impressão', '🖨️ Printing'), T('Não foi possível carregar (', 'Could not load (') + (e.message || T('erro', 'error')) + ').');
  }
  if (r && r.allow_print === false) return unavailable(T('🖨️ Impressão desabilitada', '🖨️ Printing disabled'), T('O administrador do contest desabilitou os pedidos de impressão.', 'The contest administrator disabled printing requests.'));
  if (r && r.staff_exists === false) return unavailable(T('🖨️ Impressão indisponível', '🖨️ Printing unavailable'), T('Não há equipe de impressão neste contest.', 'There is no printing staff in this contest.'));
  render();
}
boot();
