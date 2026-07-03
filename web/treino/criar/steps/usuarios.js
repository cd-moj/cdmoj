// steps/usuarios.js — passo 3: usuários próprios (colar lista, tabela editável, gerar senhas,
// CSV) ou compartilhados do Treino Livre.
import { el } from '/shared/ui.js';
import { downloadCsv } from '../criar.js';

const slug = (s) => (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, '').slice(0, 24);

function parseUsers(text) {
  const out = [];
  text.split(/\r?\n/).forEach((raw) => {
    const line = raw.trim(); if (!line) return;
    if (line.includes(':')) { const p = line.split(':'); out.push({ login: (p[0] || '').trim(), password: (p[1] || '').trim(), fullname: (p[2] || '').trim(), email: (p[3] || '').trim() }); }
    else if (line.includes('\t') || line.includes(',')) { const p = line.split(/[\t,]/).map((s) => s.trim()); out.push({ login: p[0] || '', password: '', fullname: p[1] || '', email: p[2] || '' }); }
    else out.push({ login: '', password: '', fullname: line, email: '' });
  });
  const seen = new Set(out.map((u) => u.login).filter(Boolean));
  out.forEach((u) => {
    if (u.login) return;
    let base = slug(u.fullname) || 'user', cand = base, k = 1;
    while (seen.has(cand)) cand = base + (++k);
    seen.add(cand); u.login = cand;
  });
  return out;
}

export function makeStepUsuarios(ctx) {
  const d = ctx.draft;
  const prev = el('div', {});

  function renderUsersTable() {
    prev.innerHTML = '';
    if (!d.users.length) { prev.append(el('p', { class: 'muted small' }, 'Cole a lista acima e clique “processar”.')); return; }
    const tb = el('tbody');
    d.users.forEach((u, i) => {
      const mk = (key, ph) => { const inp = el('input', { value: u[key] || '', placeholder: ph, style: 'width:100%' }); inp.addEventListener('input', () => { u[key] = inp.value; }); return inp; };
      const rm = el('button', { class: 'btn danger', onclick: () => { d.users.splice(i, 1); renderUsersTable(); } }, '✕');
      tb.append(el('tr', {},
        el('td', {}, mk('login', 'login')), el('td', {}, mk('password', '(gerada)')),
        el('td', {}, mk('fullname', 'nome')), el('td', {}, mk('email', 'email (opcional)')), el('td', {}, rm)));
    });
    prev.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, 'Login'), el('th', {}, 'Senha'), el('th', {}, 'Nome'), el('th', {}, 'Email'), el('th', {}, ''))), tb)),
      el('div', { class: 'small muted', style: 'margin-top:.3rem' }, d.users.length + ' usuário(s). Senhas em branco são geradas no servidor.'));
  }

  const sharedRadio = el('input', { type: 'radio', name: 'umode', value: 'shared' });
  const ownRadio = el('input', { type: 'radio', name: 'umode', value: 'own' });
  (d.userMode === 'shared' ? sharedRadio : ownRadio).checked = true;
  const ownBox = el('div', {});
  const paste = el('textarea', { rows: '5', placeholder: 'Cole aqui. Formatos aceitos por linha:\n  login:senha:nome:email\n  login,nome,email\n  Nome Completo   (login e senha gerados)', style: 'width:100%' });
  const procBtn = el('button', { class: 'btn ghost', onclick: () => { d.users = parseUsers(paste.value); renderUsersTable(); } }, 'Processar lista');
  const addRow = el('button', { class: 'btn ghost', onclick: () => { d.users.push({ login: '', password: '', fullname: '', email: '' }); renderUsersTable(); } }, '+ linha');
  const genPw = el('button', { class: 'btn ghost', onclick: async () => {
    const blanks = d.users.filter((u) => !u.password); if (!blanks.length) return;
    const pw = await ctx.genPasswords(blanks.length);
    blanks.forEach((u, i) => { u.password = pw[i] || u.password; }); renderUsersTable();
  } }, 'Gerar senhas faltantes');
  const dlBtn = el('button', { class: 'btn ghost', onclick: () => { if (d.users.length) downloadCsv('credenciais.csv', d.users); } }, '⬇ baixar CSV');
  ownBox.append(paste, el('div', { class: 'row', style: 'margin:.4rem 0' }, procBtn, addRow, genPw, dlBtn), prev);
  renderUsersTable();
  const updateUserMode = () => { d.userMode = ownRadio.checked ? 'own' : 'shared'; ownBox.style.display = d.userMode === 'own' ? '' : 'none'; };
  ownRadio.addEventListener('change', updateUserMode); sharedRadio.addEventListener('change', updateUserMode);
  updateUserMode();

  const root = el('div', { class: 'section' },
    el('h2', {}, '3 · Usuários'),
    el('div', { class: 'field' }, el('label', { style: 'font-weight:400' }, ownRadio, ' Criar usuários próprios do contest')),
    el('div', { class: 'field' }, el('label', { style: 'font-weight:400' }, sharedRadio, ' Compartilhar usuários do Treino Livre (sem gerência; login com a conta do treino)')),
    ownBox);
  return { el: root };
}
