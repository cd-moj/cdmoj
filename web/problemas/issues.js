// problemas/issues.js — aba "🐞 Issues" do editor: a revisão interna da banca (pedido via Arthur Botelho,
// 22/09/2026). Issue aberta tira o problema de "pronto". A API está em
// server/api/v1/handlers/problems/issues.sh (GET lista, POST open|comment|close|reopen); quem vê a aba é
// quem edita o problema — o servidor corta o resto com 404.
//
// O módulo não conhece o editor: recebe tudo por `ctx` (testável no gjs com API falsa —
// server/test/smoke-issues-panel.gjs.sh). Regras:
//   · texto do usuário é TEXTO (textContent + pre-wrap), nunca HTML — título e corpo vêm de qualquer
//     membro da org;
//   · recarregar a lista preserva o que estava aberto (<details> por número) e o que estava sendo
//     digitado (o rascunho de cada caixa fica num mapa, por número);
//   · erro de rede não apaga a lista que já estava na tela.
import { el } from '/shared/dom.js';
import { T } from '/shared/i18n.js';

const ago = (t) => {
  const s = Math.max(0, Math.floor(Date.now() / 1000 - (t || 0)));
  if (s < 90) return T('agora', 'just now');
  if (s < 5400) return T(`há ${Math.round(s / 60)} min`, `${Math.round(s / 60)} min ago`);
  if (s < 129600) return T(`há ${Math.round(s / 3600)} h`, `${Math.round(s / 3600)} h ago`);
  return T(`há ${Math.round(s / 86400)} dias`, `${Math.round(s / 86400)} days ago`);
};
const errMsg = (e) => (e && e.message) ? e.message : T('Falha de rede', 'Network error');

export function makeIssues(ctx) {
  let DATA = null;              // última resposta boa do GET
  let SHOW_CLOSED = false;
  const OPEN = new Set();       // números com o <details> aberto
  const DRAFT = new Map();      // número -> texto sendo digitado na caixa de comentário
  const panel = el('div', { class: 'section', id: 'issuesPanel' });
  const msg = el('div', { class: 'small', style: 'min-height:1.2rem' });
  const listBox = el('div', {});
  const filt = el('div', { class: 'row', style: 'gap:.4rem;margin:.4rem 0' });

  // ---- formulário de issue nova
  const fTitle = el('input', { type: 'text', maxlength: '200', placeholder: T('Título (ex.: teste 7 fora do limite do enunciado)', 'Title (e.g. test 7 outside the statement bounds)') });
  const fBody = el('textarea', { rows: '4', placeholder: T('O que está errado, onde, e como reproduzir (opcional).', 'What is wrong, where, and how to reproduce (optional).') });
  const fBtn = el('button', { class: 'btn', type: 'button' }, T('Abrir issue', 'Open issue'));
  fBtn.onclick = async () => {
    const title = fTitle.value.trim();
    if (!title) { setMsg(T('Escreva um título.', 'Write a title.'), 'error'); fTitle.focus(); return; }
    fBtn.disabled = true;
    try {
      const j = await ctx.apiPost('/problems/issues', { id: ctx.id(), action: 'open', title, body: fBody.value });
      fTitle.value = ''; fBody.value = '';
      if (j.issue) OPEN.add(j.issue.n);
      setMsg(T(`Issue #${j.issue ? j.issue.n : ''} aberta.`, `Issue #${j.issue ? j.issue.n : ''} opened.`), 'ok');
      await load();
    } catch (e) { setMsg(errMsg(e), 'error'); }
    finally { fBtn.disabled = false; }
  };
  const form = el('details', { class: 'issue-new' },
    el('summary', {}, T('+ Nova issue', '+ New issue')),
    el('div', { class: 'field' }, fTitle), el('div', { class: 'field' }, fBody), fBtn);

  panel.append(
    el('h3', {}, T('Issues do problema', 'Problem issues')),
    el('p', { class: 'small muted' }, T(
      'Anote aqui o que precisa ser revisto antes da prova: um teste suspeito, uma solução que diverge, uma frase ambígua do enunciado. Todos os membros da org veem, comentam e fecham. Enquanto houver issue aberta, o problema não está pronto.',
      'Write here what must be reviewed before the contest: a suspicious test, a diverging solution, an ambiguous sentence in the statement. Every member of the org sees, comments and closes them. While there is an open issue, the problem is not ready.')),
    form, msg, filt, listBox);

  function setMsg(t, kind) { msg.textContent = t || ''; msg.className = 'small ' + (kind === 'error' ? 'err' : kind === 'ok' ? 'v-ok' : ''); }

  async function act(n, action, body) {
    try {
      await ctx.apiPost('/problems/issues', { id: ctx.id(), action, n, body: body || '' });
      DRAFT.delete(n);
      if (action === 'close') OPEN.delete(n);
      setMsg('');
      await load();
    } catch (e) { setMsg(errMsg(e), 'error'); }
  }

  function card(it) {
    const open = it.state === 'open';
    const nComm = (it.comments || []).length;
    const d = el('details', { class: 'issue ' + (open ? 'open' : 'closed') });
    d.open = OPEN.has(it.n);
    d.addEventListener('toggle', () => { if (d.open) OPEN.add(it.n); else OPEN.delete(it.n); });
    d.append(el('summary', {},
      el('span', { class: 'pill ' + (open ? 'no' : 'ok') }, open ? T('aberta', 'open') : T('fechada', 'closed')),
      ' ', el('b', {}, `#${it.n} `), el('span', {}, it.title || ''),
      el('span', { class: 'small muted' }, ` · ${it.by || '?'} · ${ago(it.at)}` + (nComm ? ` · ${nComm} ${T('coment.', 'comm.')}` : ''))));
    if (it.body) d.append(el('div', { class: 'issue-text' }, it.body));
    (it.comments || []).forEach(c => d.append(el('div', { class: 'issue-comment' },
      el('div', { class: 'small muted' }, `${c.by || '?'} · ${ago(c.at)}`),
      el('div', { class: 'issue-text' }, c.body || ''))));
    if (!open && it.closed_by) d.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' },
      T(`fechada por ${it.closed_by} ${ago(it.closed_at)}`, `closed by ${it.closed_by} ${ago(it.closed_at)}`)));
    const ta = el('textarea', { rows: '3', placeholder: T('Comentário…', 'Comment…') });
    ta.value = DRAFT.get(it.n) || '';
    ta.addEventListener('input', () => DRAFT.set(it.n, ta.value));
    const bComm = el('button', { class: 'btn ghost', type: 'button' }, T('Comentar', 'Comment'));
    bComm.onclick = () => { if (!ta.value.trim()) { ta.focus(); return; } act(it.n, 'comment', ta.value); };
    const bState = el('button', { class: 'btn ' + (open ? '' : 'ghost'), type: 'button' },
      open ? T('Fechar (resolvida)', 'Close (resolved)') : T('Reabrir', 'Reopen'));
    bState.title = T('O texto da caixa, se houver, entra como comentário.', 'The text in the box, if any, goes in as a comment.');
    bState.onclick = () => act(it.n, open ? 'close' : 'reopen', ta.value);
    d.append(el('div', { class: 'issue-reply' }, ta, el('div', { class: 'row', style: 'gap:.4rem' }, bComm, bState)));
    return d;
  }

  function render() {
    const all = (DATA && DATA.issues) || [];
    const nOpen = all.filter(i => i.state === 'open').length, nClosed = all.length - nOpen;
    filt.innerHTML = '';
    if (nClosed) {
      const b = el('button', { class: 'filttog' + (SHOW_CLOSED ? ' on' : ''), type: 'button' },
        T(`mostrar fechadas (${nClosed})`, `show closed (${nClosed})`));
      b.onclick = () => { SHOW_CLOSED = !SHOW_CLOSED; render(); };
      filt.append(b);
    }
    listBox.innerHTML = '';
    const shown = all.filter(i => SHOW_CLOSED || i.state === 'open');
    if (!shown.length) listBox.append(el('p', { class: 'small muted' },
      nOpen || nClosed ? T('Nenhuma issue aberta.', 'No open issues.') : T('Nenhuma issue ainda.', 'No issues yet.')));
    shown.forEach(it => listBox.append(card(it)));
    if (ctx.onCount) ctx.onCount(nOpen);
  }

  async function load() {
    if (!ctx.id()) {
      DATA = null; listBox.innerHTML = '';
      listBox.append(el('p', { class: 'small muted' }, T('Salve o problema para abrir issues.', 'Save the problem to open issues.')));
      fBtn.disabled = true; return;
    }
    fBtn.disabled = false;
    try {
      DATA = await ctx.apiGet('/problems/issues?id=' + encodeURIComponent(ctx.id()));
      render();
    } catch (e) { setMsg(errMsg(e), 'error'); }   // a lista anterior fica na tela
  }

  return { panel, load, render };
}
