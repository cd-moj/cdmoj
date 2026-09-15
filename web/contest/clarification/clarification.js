// contest/clarification/clarification.js — perguntas/respostas do contest + notícias.
// Todos perguntam; admin/judge/mon respondem. O juiz comum e o monitor NÃO veem quem perguntou
// (tratamento isonômico); o juiz-chefe e o admin veem login e nome (pedido do juiz-chefe,
// 2026-09-14). Responder exige RESERVA (dois juízes não pegam a mesma); ninguém reserva por
// cima de outro — o chefe/admin só LIBERA a reserva alheia com botão próprio + confirmação
// (force). Juiz-chefe/admin editam respostas já dadas e notícias; qualquer respondente publica
// o "aviso oficial" (assunto opcional + texto).
//
// Quem responde vê a lista em DUAS seções: ⏳ abertas (mais antiga primeiro — é fila de
// trabalho) e ✅ respondidas + avisos (mais nova primeiro). O competidor vê "suas perguntas" e
// "respostas públicas e avisos". A página repolá a cada 30 s e atualiza EM LUGAR (regra da
// casa): cada cartão tem a própria assinatura; um cartão com resposta sendo digitada não é
// refeito. Quebras de linha são preservadas (white-space:pre-wrap na pergunta e na resposta).
import { apiGet, apiPost } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { fileToBase64 } from '/shared/auth.js';
import { initContestShell } from '/shared/contest-shell.js';
import { fmtDate, sigOf, everyVisible } from '/shared/admin-ui.js';
import { T } from '/shared/i18n.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const enc = encodeURIComponent;
const G = { contest: CONTEST, auth: true };
const REFRESH_MS = 30000;
let canAnswer = false, canEdit = false, myLogin = '', problems = [];
let CLARS = [];                                 // último GET
let filterProb = '';                            // '' = todos

const post = (path, body) => apiPost('/contest/' + path + '?contest=' + enc(CONTEST), body, G);
const probLabel = (p) => (p === 'general' ? T('Geral', 'General') : T('Problema ', 'Problem ') + p);

// ---------- formulários -----------------------------------------------------------------
function askForm() {
  const probSel = el('select', {}, el('option', { value: 'general' }, T('Geral', 'General')),
    ...problems.map((p) => el('option', { value: p.short_name }, p.short_name + (p.full_name ? ' · ' + p.full_name : ''))));
  const q = el('textarea', { rows: '3', placeholder: T('Sua pergunta…', 'Your question…'), style: 'width:100%' });
  const msg = el('div', { class: 'small' });
  const send = el('button', { class: 'btn' }, T('Enviar pergunta', 'Submit question'));
  send.addEventListener('click', async () => {
    if (!q.value.trim()) { q.focus(); return; }
    send.disabled = true; msg.className = 'small'; msg.textContent = T('Enviando…', 'Sending…');
    try { await post('clarification-ask', { problem: probSel.value, question: q.value.trim() }); q.value = ''; msg.textContent = T('✓ enviada', '✓ sent'); send.disabled = false; refresh(); }
    catch (e) { send.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
  });
  return el('div', { class: 'section' }, el('h2', {}, T('❓ Fazer uma pergunta', '❓ Ask a question')),
    el('div', { class: 'field' }, el('label', {}, T('Problema', 'Problem')), probSel),
    el('div', { class: 'field' }, el('label', {}, T('Pergunta', 'Question')), q),
    el('div', { class: 'row' }, send, msg));
}

// "Aviso oficial": texto da organização, público a todo o contest, com ASSUNTO opcional (vira o
// título do cartão). Autor oculto ("Organização"). Só quem responde (admin/judge/mon) vê o form.
function broadcastForm() {
  const probSel = el('select', {}, el('option', { value: 'general' }, T('Geral', 'General')),
    ...problems.map((p) => el('option', { value: p.short_name }, p.short_name)));
  const subj = el('input', { placeholder: T('assunto (opcional) — vira o título do aviso', 'subject (optional) — becomes the notice title'), style: 'width:100%' });
  const a = el('textarea', { rows: '3', placeholder: T('texto do aviso…', 'notice text…'), style: 'width:100%' });
  const msg = el('div', { class: 'small' });
  const send = el('button', { class: 'btn' }, T('Publicar aviso oficial', 'Publish official notice'));
  send.addEventListener('click', async () => {
    if (!a.value.trim()) { msg.className = 'small error-box'; msg.textContent = T('Escreva o texto do aviso.', 'Write the notice text.'); a.focus(); return; }
    send.disabled = true; msg.className = 'small'; msg.textContent = T('Publicando…', 'Publishing…');
    try { await post('clarification-broadcast', { problem: probSel.value, question: subj.value.trim(), answer: a.value.trim() }); subj.value = a.value = ''; msg.textContent = T('✓ publicado', '✓ published'); send.disabled = false; refresh(); }
    catch (e) { send.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
  });
  return el('div', { class: 'section' }, el('h2', {}, T('📣 Aviso oficial', '📣 Official notice')),
    el('p', { class: 'muted small' }, T('Publica um aviso visível a todo o contest, assinado "Organização". O assunto é opcional e aparece como título.', 'Publishes a notice visible to the whole contest, signed "Organization". The subject is optional and appears as the title.')),
    el('div', { class: 'field' }, el('label', {}, T('Problema', 'Problem')), probSel),
    el('div', { class: 'field' }, el('label', {}, T('Assunto (opcional)', 'Subject (optional)')), subj),
    el('div', { class: 'field' }, el('label', {}, T('Texto do aviso', 'Notice text')), a),
    el('div', { class: 'row' }, send, msg));
}

function answerEditor(c, isEdit) {
  const ans = el('textarea', { rows: '3', placeholder: T('Resposta…', 'Answer…'), style: 'width:100%' }); ans.value = c.answer || ''; ans.dataset.orig = c.answer || '';
  const pub = el('input', { type: 'checkbox' }); pub.checked = c.public !== false;
  const sb = el('button', { class: 'btn ghost' }, isEdit ? T('Salvar edição (juiz-chefe/admin)', 'Save edit (chief judge/admin)') : T('Responder', 'Answer'));
  const msg = el('span', { class: 'small' });
  sb.addEventListener('click', async () => {
    if (!ans.value.trim()) return; sb.disabled = true; msg.textContent = '';
    try { await post('clarification-answer', { id: c.id, answer: ans.value.trim(), public: pub.checked }); refresh(); }
    catch (e) { sb.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
  });
  return el('div', { class: 'editor', style: 'margin-top:.4rem' }, ans,
    el('div', { class: 'row' }, el('label', { class: 'small' }, pub, T(' pública (todo o contest vê)', ' public (whole contest sees)')), sb, msg));
}

async function claimAction(body, confirmMsg) {
  if (confirmMsg && !confirm(confirmMsg)) return;
  try { await post('clarification-claim', body); refresh(); } catch (ex) { alert(ex.message || T('falha', 'failed')); }
}

function answerControls(card, c) {
  if (!c.answer) {
    const claimBy = c.answer_claim && c.answer_claim.by;
    if (claimBy && claimBy !== myLogin) {
      // reservada por OUTRO: ninguém pega por cima (a API responde 409). O juiz-chefe/admin
      // tem um botão próprio, com confirmação, que manda force:true — nunca "sem querer".
      const bar = el('div', { class: 'row', style: 'margin-top:.3rem;gap:.6rem;align-items:center' },
        el('span', { class: 'small muted' }, T('⏳ sendo respondida por ', '⏳ being answered by ') + claimBy));
      if (canEdit) bar.append(el('button', { class: 'btn ghost danger small', onclick: () => claimAction({ id: c.id, action: 'release', force: true },
        T(`Liberar a reserva de ${claimBy}? Ele perde a pergunta e ela volta a ficar livre. Use só se ele saiu.`, `Release ${claimBy}'s reservation? They lose the question and it becomes free again. Use only if they left.`)) },
      T('⚠ Liberar reserva de ', '⚠ Release reservation of ') + claimBy));
      card.append(bar); return;
    }
    const bar = el('div', { class: 'row', style: 'margin-top:.3rem' });
    if (claimBy === myLogin) {
      bar.append(el('span', { class: 'small muted' }, T('✔ reservada por você ', '✔ claimed by you ')),
        el('a', { href: '#', class: 'small', onclick: (e) => { e.preventDefault(); claimAction({ id: c.id, action: 'release' }); } }, T('liberar', 'release')));
      card.append(bar, answerEditor(c, false));
    } else {
      bar.append(el('button', { class: 'btn', onclick: () => claimAction({ id: c.id, action: 'claim' }) }, T('Reservar p/ responder', 'Claim to answer')),
        el('span', { class: 'small muted' }, T('reserve antes de responder: dois juízes não pegam a mesma', 'claim before answering: two judges never take the same one')));
      card.append(bar);
    }
  } else if (canEdit) {
    card.append(el('details', { style: 'margin-top:.3rem' }, el('summary', { class: 'small' }, T('✎ editar resposta (juiz-chefe/admin)', '✎ edit answer (chief judge/admin)')), answerEditor(c, true)));
  }
}

// ---------- cartão -----------------------------------------------------------------------
function card(c) {
  const box = el('div', { class: 'clar' + (c.answer ? ' answered' : '') + (c.broadcast ? ' notice' : '') });
  const tag = c.broadcast ? T(' · 📣 aviso oficial', ' · 📣 official notice') : (c.mine ? T(' · sua pergunta', ' · your question') : '');
  const meta = el('div', { class: 'small muted' },
    probLabel(c.problem) + ' · ' + fmtDate(c.time) + tag +
    (c.answer ? (c.broadcast ? '' : (c.public ? T(' · pública', ' · public') : T(' · privada', ' · private'))) : T(' · sem resposta', ' · no answer')));
  // quem perguntou: só vem p/ juiz-chefe/admin (o servidor corta p/ juiz/monitor/competidor)
  if (c.login) meta.append(el('span', { class: 'asker' }, ' · 👤 ' + c.login + (c.asker_name && c.asker_name !== c.login ? ' · ' + c.asker_name : '')));
  box.append(meta);
  if (c.broadcast) {
    if (c.question) box.append(el('div', { class: 'q' }, el('b', {}, c.question)));
    box.append(el('div', { class: 'ans' }, c.answer, el('span', { class: 'small muted' }, ' — ' + T('Organização', 'Organization'))));
  } else {
    box.append(el('div', { class: 'q' }, el('b', {}, T('P: ', 'Q: ')), c.question));
    if (c.answer) box.append(el('div', { class: 'ans' }, el('b', {}, T('R: ', 'A: ')), c.answer,
      el('span', { class: 'small muted' }, ' — ' + (c.answered_by || ''))));
  }
  if (canAnswer) answerControls(box, c);
  return box;
}
// assinatura do que o cartão mostra (sem relógio): muda ⇒ o cartão é refeito
const cardSig = (c) => sigOf(c.id, c.question, c.answer, c.public, c.broadcast, c.answered_by,
  c.answer_claim && c.answer_claim.by, c.login, c.asker_name, c.mine, canAnswer, canEdit, myLogin);
// cartão "sujo": resposta sendo digitada (textarea com foco ou com texto diferente do que ele
// tinha ao nascer — comparar com o answer NOVO faria a edição de outro juiz nunca chegar)
function cardDirty(box) {
  const tas = box.querySelectorAll('textarea');
  for (const ta of tas) { if (ta === document.activeElement) return true; if (ta.value !== (ta.dataset.orig || '')) return true; }
  return false;
}

// ---------- seções em lugar --------------------------------------------------------------
// renderList(box, items): reaproveita o nó de cada cartão por id (mantém <details> abertos e
// textarea); reordena só quando a lista de ids muda; refaz um cartão só quando a sua assinatura
// muda e ele não está sendo editado.
const cardBoxes = new Map();
function renderList(box, items) {
  const ids = items.map((c) => c.id).join(',');
  if (box.dataset.ids !== ids) {
    box.dataset.ids = ids;
    box.innerHTML = '';
    items.forEach((c) => { let cb = cardBoxes.get(c.id); if (!cb) { cb = el('div', {}); cardBoxes.set(c.id, cb); } box.append(cb); });
  }
  if (!items.length) { box.innerHTML = ''; box.append(el('div', { class: 'muted small' }, T('nada aqui', 'nothing here'))); box.dataset.ids = ''; return; }
  items.forEach((c) => {
    const cb = cardBoxes.get(c.id); const sg = cardSig(c);
    if (cb.dataset.sig === sg) return;
    if (cb.dataset.sig && cardDirty(cb)) return;   // adia: o juiz está digitando
    cb.dataset.sig = sg; cb.innerHTML = ''; cb.append(card(c));
  });
}

const SK = {};
const filterSel = el('select', { onchange: () => { filterProb = filterSel.value; render(); } });
function fillFilter() {
  const keep = filterSel.value;
  filterSel.innerHTML = '';
  filterSel.append(el('option', { value: '' }, T('todos os problemas', 'all problems')), el('option', { value: 'general' }, T('Geral', 'General')));
  problems.forEach((p) => filterSel.append(el('option', { value: p.short_name }, p.short_name)));
  filterSel.value = keep;
}
// <details> lembra aberto/fechado por seção (localStorage; sem storage = default)
function section(key, defaultOpen) {
  const d = el('details', { class: 'clar-sec' }, el('summary', {}, el('b', {}, '')));
  let open = defaultOpen;
  try { const v = localStorage.getItem('moj_clar_' + key); if (v === '1' || v === '0') open = v === '1'; } catch { /* sem storage */ }
  d.open = open;
  d.addEventListener('toggle', () => { try { localStorage.setItem('moj_clar_' + key, d.open ? '1' : '0'); } catch { /* idem */ } });
  d.body = el('div', {}); d.append(d.body);
  return d;
}
function setTitle(d, text) { const b = d.querySelector('summary b'); if (b.textContent !== text) b.textContent = text; }

function skeleton() {
  SK.err = el('div', {});
  SK.bar = el('div', { class: 'row', style: 'gap:.5rem;align-items:center;margin:.3rem 0' },
    el('span', { class: 'small muted' }, T('Filtrar:', 'Filter:')), filterSel,
    el('button', { class: 'btn ghost small', onclick: () => refresh(), title: T('atualizar agora (a página atualiza sozinha a cada 30 s)', 'refresh now (the page refreshes by itself every 30 s)') }, '↻'));
  SK.a = section(canAnswer ? 'open' : 'mine', true);
  SK.b = section(canAnswer ? 'done' : 'public', true);
  listBody.innerHTML = '';
  listBody.append(SK.err, SK.bar, SK.a, SK.b);
}
function render() {
  const cs = CLARS.filter((c) => !filterProb || c.problem === filterProb);
  const byOld = (a, b) => (a.time || 0) - (b.time || 0), byNew = (a, b) => (b.time || 0) - (a.time || 0);
  let A, B, tA, tB;
  if (canAnswer) {
    A = cs.filter((c) => !c.answer).sort(byOld);                 // fila: mais antiga primeiro
    B = cs.filter((c) => !!c.answer).sort(byNew);
    tA = T(`⏳ Abertas (${A.length})`, `⏳ Open (${A.length})`);
    tB = T(`✅ Respondidas e avisos (${B.length})`, `✅ Answered and notices (${B.length})`);
  } else {
    A = cs.filter((c) => c.mine).sort((a, b) => (a.answer ? 1 : 0) - (b.answer ? 1 : 0) || byNew(a, b));
    B = cs.filter((c) => !c.mine).sort(byNew);
    tA = T(`❓ Suas perguntas (${A.length})`, `❓ Your questions (${A.length})`);
    tB = T(`📣 Respostas públicas e avisos (${B.length})`, `📣 Public answers and notices (${B.length})`);
  }
  setTitle(SK.a, tA); setTitle(SK.b, tB);
  renderList(SK.a.body, A); renderList(SK.b.body, B);
}

const listBox = el('div', { class: 'section' }, el('h2', {}, '💬 Clarifications'));
const listBody = el('div', {});
let stopTimer = null;

async function fetchAll() {
  const r = await apiGet('/contest/clarifications?contest=' + enc(CONTEST), G);
  canAnswer = !!r.can_answer; canEdit = !!(r.can_edit || r.is_chief); if (r.me) myLogin = r.me;
  CLARS = r.clarifications || [];
}
async function refresh() {
  try { await fetchAll(); if (SK.err) SK.err.innerHTML = ''; }
  catch { if (SK.err) { SK.err.innerHTML = ''; SK.err.append(el('div', { class: 'error-box' }, T('Falha ao carregar.', 'Failed to load.'))); } return; }
  if (!SK.a) { skeleton(); fillFilter(); }
  render();
}

// ---------- notícias (quem responde) -----------------------------------------------------
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
      const rm = el('button', { class: 'btn ghost danger', title: T('remover', 'remove'), onclick: async () => { if (!confirm(T('Remover esta notícia?', 'Remove this news item?'))) return; await post('admin/news', { action: 'remove', id: n.id }); loadNews(); } }, '✕');
      // editar (já publicada): só juiz-chefe/admin
      const edit = canEdit ? el('button', { class: 'btn ghost', onclick: () => openEdit(n) }, T('✎ editar', '✎ edit')) : '';
      list.append(el('div', { class: 'row', style: 'justify-content:space-between; border-top:1px solid #eef2f8; padding:.3rem 0' },
        el('div', {}, el('b', {}, n.title), ' ', el('span', { class: 'small muted', style: 'white-space:pre-wrap' }, n.text || ''),
          n.file ? el('span', { class: 'small', style: 'margin-left:.4rem' }, '📎 ' + n.file.name) : ''),
        el('div', { class: 'row' }, edit, rm)));
    });
  }
  function openEdit(n) {
    const t = el('input', { value: n.title }); const x = el('textarea', { rows: '2', style: 'width:100%' }); x.value = n.text || '';
    const msg = el('span', { class: 'small' });
    const save = el('button', { class: 'btn' }, T('Salvar (juiz-chefe/admin)', 'Save (chief judge/admin)'));
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
      el('a', { class: 'btn', href: '/contest/login/?c=' + enc(CONTEST) }, T('Entrar no contest', 'Contest login'))));
    return;
  }
  myLogin = st.login || '';
  try { const pr = await apiGet('/contest/problems?contest=' + enc(CONTEST), G); problems = pr.problems || []; } catch { /* sem problemas */ }
  app.innerHTML = '';
  const formSlot = el('div', {});
  listBody.append(el('p', { class: 'muted small' }, T('carregando…', 'loading…')));
  app.append(formSlot, listBox); listBox.append(listBody);
  await refresh();
  if (canAnswer) { formSlot.append(broadcastForm()); app.append(newsSection()); }
  else { formSlot.append(askForm()); }
  if (stopTimer) stopTimer();
  stopTimer = everyVisible(app, REFRESH_MS, refresh);
}
boot();
