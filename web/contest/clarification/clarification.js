// contest/clarification/clarification.js — perguntas/respostas do contest + notícias.
// Todos perguntam; admin/judge/mon respondem (pública = todo o contest vê; privada = só o time)
// e publicam notícias do contest.
import { apiGet, apiPost } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { initContestShell } from '/shared/contest-shell.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const enc = encodeURIComponent;
const G = { contest: CONTEST, auth: true };
const fmtDate = (e) => new Date((+e || 0) * 1000).toLocaleString('pt-BR');
let canAnswer = false, problems = [];

const listBox = el('div', { class: 'section' }, el('h2', {}, '💬 Clarifications'));
const listBody = el('div', {}, el('p', { class: 'muted small' }, 'carregando…'));

function askForm() {
  const probSel = el('select', {}, el('option', { value: 'general' }, 'Geral'),
    ...problems.map((p) => el('option', { value: p.short_name }, p.short_name + (p.full_name ? ' · ' + p.full_name : ''))));
  const q = el('textarea', { rows: '3', placeholder: 'Sua pergunta…', style: 'width:100%' });
  const msg = el('div', { class: 'small' });
  const send = el('button', { class: 'btn' }, 'Enviar pergunta');
  send.addEventListener('click', async () => {
    if (!q.value.trim()) { q.focus(); return; }
    send.disabled = true; msg.className = 'small'; msg.textContent = 'Enviando…';
    try { await apiPost('/contest/clarification-ask?contest=' + enc(CONTEST), { problem: probSel.value, question: q.value.trim() }, G); q.value = ''; msg.textContent = '✓ enviada'; send.disabled = false; loadList(); }
    catch (e) { send.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || 'falha'; }
  });
  return el('div', { class: 'section' }, el('h2', {}, '❓ Fazer uma pergunta'),
    el('div', { class: 'field' }, el('label', {}, 'Problema'), probSel),
    el('div', { class: 'field' }, el('label', {}, 'Pergunta'), q),
    el('div', { class: 'row' }, send, msg));
}

async function loadList() {
  listBody.innerHTML = ''; let r;
  try { r = await apiGet('/contest/clarifications?contest=' + enc(CONTEST), G); }
  catch { listBody.append(el('div', { class: 'error-box' }, 'Falha ao carregar.')); return; }
  canAnswer = !!r.can_answer;
  const cs = r.clarifications || [];
  if (!cs.length) { listBody.append(el('div', { class: 'muted' }, 'Nenhuma clarification ainda.')); return; }
  cs.forEach((c) => {
    const card = el('div', { class: 'clar' + (c.answer ? ' answered' : '') });
    card.append(el('div', { class: 'small muted' },
      (c.problem === 'general' ? 'Geral' : 'Problema ' + c.problem) + ' · ' + fmtDate(c.time) +
      (canAnswer ? ' · por ' + c.login : '') + (c.answer ? (c.public ? ' · pública' : ' · privada') : ' · sem resposta')));
    card.append(el('div', {}, el('b', {}, 'P: '), c.question));
    if (c.answer) card.append(el('div', { class: 'ans' }, el('b', {}, 'R: '), c.answer,
      c.answered_by ? el('span', { class: 'small muted' }, ' — ' + c.answered_by) : ''));
    if (canAnswer) {
      const ans = el('textarea', { rows: '2', placeholder: 'Resposta…', style: 'width:100%' }); ans.value = c.answer || '';
      const pub = el('input', { type: 'checkbox' }); pub.checked = !!c.public;
      const sb = el('button', { class: 'btn ghost' }, c.answer ? 'Atualizar resposta' : 'Responder');
      sb.addEventListener('click', async () => {
        if (!ans.value.trim()) return; sb.disabled = true;
        try { await apiPost('/contest/clarification-answer?contest=' + enc(CONTEST), { id: c.id, answer: ans.value.trim(), public: pub.checked }, G); loadList(); }
        catch (e) { sb.disabled = false; alert(e.message || 'falha'); }
      });
      card.append(el('div', { style: 'margin-top:.4rem' }, ans,
        el('div', { class: 'row' }, el('label', { class: 'small' }, pub, ' pública (todo o contest vê)'), sb)));
    }
    listBody.append(card);
  });
}

function newsSection() {
  const box = el('div', { class: 'section' }, el('h2', {}, '📰 Notícias do contest'));
  const list = el('div', {});
  const title = el('input', { placeholder: 'título' });
  const text = el('textarea', { rows: '2', placeholder: 'texto (opcional)', style: 'width:100%' });
  const add = el('button', { class: 'btn' }, 'Publicar notícia');
  add.addEventListener('click', async () => {
    if (!title.value.trim()) return; add.disabled = true;
    try { await apiPost('/contest/admin/news?contest=' + enc(CONTEST), { action: 'add', title: title.value.trim(), text: text.value }, G); title.value = text.value = ''; add.disabled = false; loadNews(); }
    catch (e) { add.disabled = false; alert(e.message || 'falha'); }
  });
  async function loadNews() {
    list.innerHTML = ''; let r;
    try { r = await apiGet('/contest/news?contest=' + enc(CONTEST), G); } catch { return; }
    const items = r.items || [];
    if (!items.length) list.append(el('div', { class: 'muted small' }, 'sem notícias'));
    items.forEach((n) => {
      const rm = el('button', { class: 'btn danger', onclick: async () => { if (!confirm('Remover esta notícia?')) return; await apiPost('/contest/admin/news?contest=' + enc(CONTEST), { action: 'remove', id: n.id }, G); loadNews(); } }, '✕');
      list.append(el('div', { class: 'row', style: 'justify-content:space-between; border-top:1px solid #eef2f8; padding:.3rem 0' },
        el('div', {}, el('b', {}, n.title), ' ', el('span', { class: 'small muted' }, n.text || '')), rm));
    });
  }
  loadNews();
  box.append(list, el('div', { class: 'field', style: 'margin-top:.6rem' }, el('label', {}, 'Nova notícia'), title, text), el('div', {}, add));
  return box;
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">Contest não informado.</div>'; return; }
  const { st } = await initContestShell(CONTEST);
  if (!st || !st.logged_in) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, '🔒 Entre no contest'),
      el('a', { class: 'btn', href: '/contest/login/?c=' + enc(CONTEST) }, 'Login do contest')));
    return;
  }
  try { const pr = await apiGet('/contest/problems?contest=' + enc(CONTEST), G); problems = pr.problems || []; } catch { /* sem problemas */ }
  app.innerHTML = '';
  app.append(askForm(), listBox); listBox.append(listBody);
  await loadList();
  if (canAnswer) app.append(newsSection());
}
boot();
