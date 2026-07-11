// contest/clarification/clarification.js — perguntas/respostas do contest + notícias.
// Todos perguntam; admin/judge/mon respondem. O juiz NÃO vê quem perguntou (tratamento
// isonômico). Responder exige RESERVA (dois juízes não pegam a mesma). Juiz-chefe/admin
// editam respostas já dadas e notícias já publicadas; juiz manda "aviso oficial" (Q+A).
import { apiGet, apiPost } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { fileToBase64 } from '/shared/auth.js';
import { initContestShell } from '/shared/contest-shell.js';
import { T } from '/shared/i18n.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const enc = encodeURIComponent;
const G = { contest: CONTEST, auth: true };
const fmtDate = (e) => new Date((+e || 0) * 1000).toLocaleString('pt-BR');
let canAnswer = false, isChief = false, myLogin = '', problems = [];

const listBox = el('div', { class: 'section' }, el('h2', {}, '💬 Clarifications'));
const listBody = el('div', {}, el('p', { class: 'muted small' }, T('carregando…', 'loading…')));

const post = (path, body) => apiPost('/contest/' + path + '?contest=' + enc(CONTEST), body, G);

function askForm() {
  const probSel = el('select', {}, el('option', { value: 'general' }, T('Geral', 'General')),
    ...problems.map((p) => el('option', { value: p.short_name }, p.short_name + (p.full_name ? ' · ' + p.full_name : ''))));
  const q = el('textarea', { rows: '3', placeholder: T('Sua pergunta…', 'Your question…'), style: 'width:100%' });
  const msg = el('div', { class: 'small' });
  const send = el('button', { class: 'btn' }, T('Enviar pergunta', 'Submit question'));
  send.addEventListener('click', async () => {
    if (!q.value.trim()) { q.focus(); return; }
    send.disabled = true; msg.className = 'small'; msg.textContent = T('Enviando…', 'Sending…');
    try { await post('clarification-ask', { problem: probSel.value, question: q.value.trim() }); q.value = ''; msg.textContent = T('✓ enviada', '✓ sent'); send.disabled = false; loadList(); }
    catch (e) { send.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
  });
  return el('div', { class: 'section' }, el('h2', {}, T('❓ Fazer uma pergunta', '❓ Ask a question')),
    el('div', { class: 'field' }, el('label', {}, T('Problema', 'Problem')), probSel),
    el('div', { class: 'field' }, el('label', {}, T('Pergunta', 'Question')), q),
    el('div', { class: 'row' }, send, msg));
}

// "Aviso oficial" (clarification especial): pergunta + resposta que a organização escreve,
// pública a todo o contest, autor oculto. Só quem responde (admin/judge/mon) vê este form.
function broadcastForm() {
  const probSel = el('select', {}, el('option', { value: 'general' }, T('Geral', 'General')),
    ...problems.map((p) => el('option', { value: p.short_name }, p.short_name)));
  const q = el('textarea', { rows: '2', placeholder: T('pergunta/assunto…', 'question/subject…'), style: 'width:100%' });
  const a = el('textarea', { rows: '2', placeholder: T('resposta oficial…', 'official answer…'), style: 'width:100%' });
  const msg = el('div', { class: 'small' });
  const send = el('button', { class: 'btn' }, T('Publicar aviso oficial', 'Publish official notice'));
  send.addEventListener('click', async () => {
    if (!q.value.trim() || !a.value.trim()) { msg.className = 'small error-box'; msg.textContent = T('Preencha pergunta e resposta.', 'Fill in question and answer.'); return; }
    send.disabled = true; msg.className = 'small'; msg.textContent = T('Publicando…', 'Publishing…');
    try { await post('clarification-broadcast', { problem: probSel.value, question: q.value.trim(), answer: a.value.trim() }); q.value = a.value = ''; msg.textContent = T('✓ publicado', '✓ published'); send.disabled = false; loadList(); }
    catch (e) { send.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
  });
  return el('div', { class: 'section' }, el('h2', {}, T('📣 Aviso oficial (pergunta + resposta)', '📣 Official notice (question + answer)')),
    el('p', { class: 'muted small' }, T('Publica um Q+A visível a todos; o autor não aparece (assina como "Organização").', 'Publishes a Q+A visible to everyone; the author is hidden (signed as "Organization").')),
    el('div', { class: 'field' }, el('label', {}, T('Problema', 'Problem')), probSel),
    el('div', { class: 'field' }, el('label', {}, T('Pergunta', 'Question')), q),
    el('div', { class: 'field' }, el('label', {}, T('Resposta', 'Answer')), a),
    el('div', { class: 'row' }, send, msg));
}

function answerEditor(c, isEdit) {
  const ans = el('textarea', { rows: '2', placeholder: T('Resposta…', 'Answer…'), style: 'width:100%' }); ans.value = c.answer || '';
  const pub = el('input', { type: 'checkbox' }); pub.checked = c.public !== false;
  const sb = el('button', { class: 'btn ghost' }, isEdit ? T('Salvar edição (chefe)', 'Save edit (chief)') : T('Responder', 'Answer'));
  const msg = el('span', { class: 'small' });
  sb.addEventListener('click', async () => {
    if (!ans.value.trim()) return; sb.disabled = true; msg.textContent = '';
    try { await post('clarification-answer', { id: c.id, answer: ans.value.trim(), public: pub.checked }); loadList(); }
    catch (e) { sb.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
  });
  return el('div', { style: 'margin-top:.4rem' }, ans,
    el('div', { class: 'row' }, el('label', { class: 'small' }, pub, T(' pública (todo o contest vê)', ' public (whole contest sees)')), sb, msg));
}

function answerControls(card, c) {
  if (!c.answer) {
    const claimBy = c.answer_claim && c.answer_claim.by;
    const takenByOther = claimBy && claimBy !== myLogin;
    if (takenByOther && !isChief) {
      card.append(el('div', { class: 'small muted', style: 'margin-top:.3rem' }, T('⏳ sendo respondida por ', '⏳ being answered by ') + claimBy)); return;
    }
    const bar = el('div', { class: 'row', style: 'margin-top:.3rem' });
    if (claimBy === myLogin) {
      bar.append(el('span', { class: 'small muted' }, T('✔ reservada por você ', '✔ claimed by you ')),
        el('a', { href: '#', class: 'small', onclick: async (e) => { e.preventDefault(); try { await post('clarification-claim', { id: c.id, action: 'release' }); loadList(); } catch (ex) { alert(ex.message || T('falha', 'failed')); } } }, T('liberar', 'release')));
    } else {
      bar.append(el('button', { class: 'btn ghost', onclick: async (b) => { try { await post('clarification-claim', { id: c.id, action: 'claim' }); loadList(); } catch (ex) { alert(ex.message || T('falha', 'failed')); } } }, T('Reservar p/ responder', 'Claim to answer')));
    }
    card.append(bar, answerEditor(c, false));
  } else if (isChief) {
    card.append(el('details', { style: 'margin-top:.3rem' }, el('summary', { class: 'small' }, T('✎ editar resposta (juiz-chefe)', '✎ edit answer (chief judge)')), answerEditor(c, true)));
  }
}

async function loadList() {
  listBody.innerHTML = ''; let r;
  try { r = await apiGet('/contest/clarifications?contest=' + enc(CONTEST), G); }
  catch { listBody.append(el('div', { class: 'error-box' }, T('Falha ao carregar.', 'Failed to load.'))); return; }
  canAnswer = !!r.can_answer; isChief = !!r.is_chief;
  const cs = r.clarifications || [];
  if (!cs.length) { listBody.append(el('div', { class: 'muted' }, T('Nenhuma clarification ainda.', 'No clarifications yet.'))); return; }
  cs.forEach((c) => {
    const card = el('div', { class: 'clar' + (c.answer ? ' answered' : '') });
    const tag = c.broadcast ? T(' · 📣 aviso oficial', ' · 📣 official notice') : (c.mine ? T(' · sua pergunta', ' · your question') : '');
    card.append(el('div', { class: 'small muted' },
      (c.problem === 'general' ? T('Geral', 'General') : T('Problema ', 'Problem ') + c.problem) + ' · ' + fmtDate(c.time) + tag +
      (c.answer ? (c.public ? T(' · pública', ' · public') : T(' · privada', ' · private')) : T(' · sem resposta', ' · no answer'))));
    if (!c.broadcast) card.append(el('div', {}, el('b', {}, T('P: ', 'Q: ')), c.question));
    if (c.answer) card.append(el('div', { class: 'ans' }, el('b', {}, c.broadcast ? '' : T('R: ', 'A: ')), c.answer,
      el('span', { class: 'small muted' }, ' — ' + (c.broadcast ? T('Organização', 'Organization') : (c.answered_by || '')))));
    if (canAnswer) answerControls(card, c);
    listBody.append(card);
  });
}

function newsSection() {
  const box = el('div', { class: 'section' }, el('h2', {}, T('📰 Notícias do contest', '📰 Contest news')));
  const list = el('div', {});
  const title = el('input', { placeholder: T('título', 'title') });
  const text = el('textarea', { rows: '2', placeholder: T('texto (opcional)', 'text (optional)'), style: 'width:100%' });
  const fileInput = el('input', { type: 'file', title: T('anexo opcional (aluno baixa)', 'optional attachment (student downloads)') });
  const add = el('button', { class: 'btn' }, T('Publicar notícia', 'Publish news'));
  add.addEventListener('click', async () => {
    if (!title.value.trim()) return; add.disabled = true;
    try {
      const body = { action: 'add', title: title.value.trim(), text: text.value };
      if (fileInput.files && fileInput.files[0]) { body.filename = fileInput.files[0].name; body.file_b64 = await fileToBase64(fileInput.files[0]); }
      await post('admin/news', body);
      title.value = text.value = ''; fileInput.value = ''; add.disabled = false; loadNews();
    } catch (e) { add.disabled = false; alert(e.message || T('falha', 'failed')); }
  });
  async function loadNews() {
    list.innerHTML = ''; let r;
    try { r = await apiGet('/contest/news?contest=' + enc(CONTEST), G); } catch { return; }
    const items = r.items || [];
    if (!items.length) list.append(el('div', { class: 'muted small' }, T('sem notícias', 'no news')));
    items.forEach((n) => {
      const rm = el('button', { class: 'btn danger', onclick: async () => { if (!confirm(T('Remover esta notícia?', 'Remove this news item?'))) return; await post('admin/news', { action: 'remove', id: n.id }); loadNews(); } }, '✕');
      // editar (já publicada): só juiz-chefe/admin
      const edit = isChief ? el('button', { class: 'btn ghost', onclick: () => openEdit(n) }, T('✎ editar', '✎ edit')) : '';
      list.append(el('div', { class: 'row', style: 'justify-content:space-between; border-top:1px solid #eef2f8; padding:.3rem 0' },
        el('div', {}, el('b', {}, n.title), ' ', el('span', { class: 'small muted' }, n.text || ''),
          n.file ? el('span', { class: 'small', style: 'margin-left:.4rem' }, '📎 ' + n.file.name) : ''),
        el('div', { class: 'row' }, edit, rm)));
    });
  }
  function openEdit(n) {
    const t = el('input', { value: n.title }); const x = el('textarea', { rows: '2', style: 'width:100%' }); x.value = n.text || '';
    const msg = el('span', { class: 'small' });
    const save = el('button', { class: 'btn' }, T('Salvar (chefe)', 'Save (chief)'));
    save.addEventListener('click', async () => {
      if (!t.value.trim()) return; save.disabled = true;
      try { await post('admin/news', { action: 'edit', id: n.id, title: t.value.trim(), text: x.value }); loadNews(); }
      catch (e) { save.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
    });
    list.prepend(el('div', { class: 'field', style: 'border:1px solid var(--line); padding:.5rem; border-radius:.5rem; margin-bottom:.4rem' },
      el('label', {}, T('✎ Editar notícia', '✎ Edit news')), t, x, el('div', { class: 'row' }, save, el('button', { class: 'btn ghost', onclick: () => loadNews() }, T('cancelar', 'cancel')), msg)));
  }
  loadNews();
  box.append(list, el('div', { class: 'field', style: 'margin-top:.6rem' }, el('label', {}, T('Nova notícia', 'New news')), title, text,
    el('div', { class: 'small muted', style: 'margin-top:.3rem' }, T('Anexo (opcional):', 'Attachment (optional):')), fileInput), el('div', {}, add));
  return box;
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">' + T('Contest não informado.', 'Contest not specified.') + '</div>'; return; }
  const { st } = await initContestShell(CONTEST);
  if (!st || !st.logged_in) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, T('🔒 Entre no contest', '🔒 Enter the contest')),
      el('a', { class: 'btn', href: '/contest/login/?c=' + enc(CONTEST) }, T('Login do contest', 'Contest login'))));
    return;
  }
  myLogin = st.login || '';
  try { const pr = await apiGet('/contest/problems?contest=' + enc(CONTEST), G); problems = pr.problems || []; } catch { /* sem problemas */ }
  app.innerHTML = '';
  const formSlot = el('div', {});
  app.append(formSlot, listBox); listBox.append(listBody);
  await loadList();
  if (canAnswer) { formSlot.append(broadcastForm()); app.append(newsSection()); }
  else { formSlot.append(askForm()); }
}
boot();
