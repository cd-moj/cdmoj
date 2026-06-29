// contest/clarification/clarification.js — perguntas/respostas do contest + notícias.
// Todos perguntam; admin/judge/mon respondem. O juiz NÃO vê quem perguntou (tratamento
// isonômico). Responder exige RESERVA (dois juízes não pegam a mesma). Juiz-chefe/admin
// editam respostas já dadas e notícias já publicadas; juiz manda "aviso oficial" (Q+A).
import { apiGet, apiPost } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { fileToBase64 } from '/shared/auth.js';
import { initContestShell } from '/shared/contest-shell.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const enc = encodeURIComponent;
const G = { contest: CONTEST, auth: true };
const fmtDate = (e) => new Date((+e || 0) * 1000).toLocaleString('pt-BR');
let canAnswer = false, isChief = false, myLogin = '', problems = [];

const listBox = el('div', { class: 'section' }, el('h2', {}, '💬 Clarifications'));
const listBody = el('div', {}, el('p', { class: 'muted small' }, 'carregando…'));

const post = (path, body) => apiPost('/contest/' + path + '?contest=' + enc(CONTEST), body, G);

function askForm() {
  const probSel = el('select', {}, el('option', { value: 'general' }, 'Geral'),
    ...problems.map((p) => el('option', { value: p.short_name }, p.short_name + (p.full_name ? ' · ' + p.full_name : ''))));
  const q = el('textarea', { rows: '3', placeholder: 'Sua pergunta…', style: 'width:100%' });
  const msg = el('div', { class: 'small' });
  const send = el('button', { class: 'btn' }, 'Enviar pergunta');
  send.addEventListener('click', async () => {
    if (!q.value.trim()) { q.focus(); return; }
    send.disabled = true; msg.className = 'small'; msg.textContent = 'Enviando…';
    try { await post('clarification-ask', { problem: probSel.value, question: q.value.trim() }); q.value = ''; msg.textContent = '✓ enviada'; send.disabled = false; loadList(); }
    catch (e) { send.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || 'falha'; }
  });
  return el('div', { class: 'section' }, el('h2', {}, '❓ Fazer uma pergunta'),
    el('div', { class: 'field' }, el('label', {}, 'Problema'), probSel),
    el('div', { class: 'field' }, el('label', {}, 'Pergunta'), q),
    el('div', { class: 'row' }, send, msg));
}

// "Aviso oficial" (clarification especial): pergunta + resposta que a organização escreve,
// pública a todo o contest, autor oculto. Só quem responde (admin/judge/mon) vê este form.
function broadcastForm() {
  const probSel = el('select', {}, el('option', { value: 'general' }, 'Geral'),
    ...problems.map((p) => el('option', { value: p.short_name }, p.short_name)));
  const q = el('textarea', { rows: '2', placeholder: 'pergunta/assunto…', style: 'width:100%' });
  const a = el('textarea', { rows: '2', placeholder: 'resposta oficial…', style: 'width:100%' });
  const msg = el('div', { class: 'small' });
  const send = el('button', { class: 'btn' }, 'Publicar aviso oficial');
  send.addEventListener('click', async () => {
    if (!q.value.trim() || !a.value.trim()) { msg.className = 'small error-box'; msg.textContent = 'Preencha pergunta e resposta.'; return; }
    send.disabled = true; msg.className = 'small'; msg.textContent = 'Publicando…';
    try { await post('clarification-broadcast', { problem: probSel.value, question: q.value.trim(), answer: a.value.trim() }); q.value = a.value = ''; msg.textContent = '✓ publicado'; send.disabled = false; loadList(); }
    catch (e) { send.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || 'falha'; }
  });
  return el('div', { class: 'section' }, el('h2', {}, '📣 Aviso oficial (pergunta + resposta)'),
    el('p', { class: 'muted small' }, 'Publica um Q+A visível a todos; o autor não aparece (assina como "Organização").'),
    el('div', { class: 'field' }, el('label', {}, 'Problema'), probSel),
    el('div', { class: 'field' }, el('label', {}, 'Pergunta'), q),
    el('div', { class: 'field' }, el('label', {}, 'Resposta'), a),
    el('div', { class: 'row' }, send, msg));
}

function answerEditor(c, isEdit) {
  const ans = el('textarea', { rows: '2', placeholder: 'Resposta…', style: 'width:100%' }); ans.value = c.answer || '';
  const pub = el('input', { type: 'checkbox' }); pub.checked = c.public !== false;
  const sb = el('button', { class: 'btn ghost' }, isEdit ? 'Salvar edição (chefe)' : 'Responder');
  const msg = el('span', { class: 'small' });
  sb.addEventListener('click', async () => {
    if (!ans.value.trim()) return; sb.disabled = true; msg.textContent = '';
    try { await post('clarification-answer', { id: c.id, answer: ans.value.trim(), public: pub.checked }); loadList(); }
    catch (e) { sb.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || 'falha'; }
  });
  return el('div', { style: 'margin-top:.4rem' }, ans,
    el('div', { class: 'row' }, el('label', { class: 'small' }, pub, ' pública (todo o contest vê)'), sb, msg));
}

function answerControls(card, c) {
  if (!c.answer) {
    const claimBy = c.answer_claim && c.answer_claim.by;
    const takenByOther = claimBy && claimBy !== myLogin;
    if (takenByOther && !isChief) {
      card.append(el('div', { class: 'small muted', style: 'margin-top:.3rem' }, '⏳ sendo respondida por ' + claimBy)); return;
    }
    const bar = el('div', { class: 'row', style: 'margin-top:.3rem' });
    if (claimBy === myLogin) {
      bar.append(el('span', { class: 'small muted' }, '✔ reservada por você '),
        el('a', { href: '#', class: 'small', onclick: async (e) => { e.preventDefault(); try { await post('clarification-claim', { id: c.id, action: 'release' }); loadList(); } catch (ex) { alert(ex.message || 'falha'); } } }, 'liberar'));
    } else {
      bar.append(el('button', { class: 'btn ghost', onclick: async (b) => { try { await post('clarification-claim', { id: c.id, action: 'claim' }); loadList(); } catch (ex) { alert(ex.message || 'falha'); } } }, 'Reservar p/ responder'));
    }
    card.append(bar, answerEditor(c, false));
  } else if (isChief) {
    card.append(el('details', { style: 'margin-top:.3rem' }, el('summary', { class: 'small' }, '✎ editar resposta (juiz-chefe)'), answerEditor(c, true)));
  }
}

async function loadList() {
  listBody.innerHTML = ''; let r;
  try { r = await apiGet('/contest/clarifications?contest=' + enc(CONTEST), G); }
  catch { listBody.append(el('div', { class: 'error-box' }, 'Falha ao carregar.')); return; }
  canAnswer = !!r.can_answer; isChief = !!r.is_chief;
  const cs = r.clarifications || [];
  if (!cs.length) { listBody.append(el('div', { class: 'muted' }, 'Nenhuma clarification ainda.')); return; }
  cs.forEach((c) => {
    const card = el('div', { class: 'clar' + (c.answer ? ' answered' : '') });
    const tag = c.broadcast ? ' · 📣 aviso oficial' : (c.mine ? ' · sua pergunta' : '');
    card.append(el('div', { class: 'small muted' },
      (c.problem === 'general' ? 'Geral' : 'Problema ' + c.problem) + ' · ' + fmtDate(c.time) + tag +
      (c.answer ? (c.public ? ' · pública' : ' · privada') : ' · sem resposta')));
    if (!c.broadcast) card.append(el('div', {}, el('b', {}, 'P: '), c.question));
    if (c.answer) card.append(el('div', { class: 'ans' }, el('b', {}, c.broadcast ? '' : 'R: '), c.answer,
      el('span', { class: 'small muted' }, ' — ' + (c.broadcast ? 'Organização' : (c.answered_by || '')))));
    if (canAnswer) answerControls(card, c);
    listBody.append(card);
  });
}

function newsSection() {
  const box = el('div', { class: 'section' }, el('h2', {}, '📰 Notícias do contest'));
  const list = el('div', {});
  const title = el('input', { placeholder: 'título' });
  const text = el('textarea', { rows: '2', placeholder: 'texto (opcional)', style: 'width:100%' });
  const fileInput = el('input', { type: 'file', title: 'anexo opcional (aluno baixa)' });
  const add = el('button', { class: 'btn' }, 'Publicar notícia');
  add.addEventListener('click', async () => {
    if (!title.value.trim()) return; add.disabled = true;
    try {
      const body = { action: 'add', title: title.value.trim(), text: text.value };
      if (fileInput.files && fileInput.files[0]) { body.filename = fileInput.files[0].name; body.file_b64 = await fileToBase64(fileInput.files[0]); }
      await post('admin/news', body);
      title.value = text.value = ''; fileInput.value = ''; add.disabled = false; loadNews();
    } catch (e) { add.disabled = false; alert(e.message || 'falha'); }
  });
  async function loadNews() {
    list.innerHTML = ''; let r;
    try { r = await apiGet('/contest/news?contest=' + enc(CONTEST), G); } catch { return; }
    const items = r.items || [];
    if (!items.length) list.append(el('div', { class: 'muted small' }, 'sem notícias'));
    items.forEach((n) => {
      const rm = el('button', { class: 'btn danger', onclick: async () => { if (!confirm('Remover esta notícia?')) return; await post('admin/news', { action: 'remove', id: n.id }); loadNews(); } }, '✕');
      // editar (já publicada): só juiz-chefe/admin
      const edit = isChief ? el('button', { class: 'btn ghost', onclick: () => openEdit(n) }, '✎ editar') : '';
      list.append(el('div', { class: 'row', style: 'justify-content:space-between; border-top:1px solid #eef2f8; padding:.3rem 0' },
        el('div', {}, el('b', {}, n.title), ' ', el('span', { class: 'small muted' }, n.text || ''),
          n.file ? el('span', { class: 'small', style: 'margin-left:.4rem' }, '📎 ' + n.file.name) : ''),
        el('div', { class: 'row' }, edit, rm)));
    });
  }
  function openEdit(n) {
    const t = el('input', { value: n.title }); const x = el('textarea', { rows: '2', style: 'width:100%' }); x.value = n.text || '';
    const msg = el('span', { class: 'small' });
    const save = el('button', { class: 'btn' }, 'Salvar (chefe)');
    save.addEventListener('click', async () => {
      if (!t.value.trim()) return; save.disabled = true;
      try { await post('admin/news', { action: 'edit', id: n.id, title: t.value.trim(), text: x.value }); loadNews(); }
      catch (e) { save.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || 'falha'; }
    });
    list.prepend(el('div', { class: 'field', style: 'border:1px solid var(--line); padding:.5rem; border-radius:.5rem; margin-bottom:.4rem' },
      el('label', {}, '✎ Editar notícia'), t, x, el('div', { class: 'row' }, save, el('button', { class: 'btn ghost', onclick: () => loadNews() }, 'cancelar'), msg)));
  }
  loadNews();
  box.append(list, el('div', { class: 'field', style: 'margin-top:.6rem' }, el('label', {}, 'Nova notícia'), title, text,
    el('div', { class: 'small muted', style: 'margin-top:.3rem' }, 'Anexo (opcional):'), fileInput), el('div', {}, add));
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
