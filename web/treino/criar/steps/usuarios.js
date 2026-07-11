// steps/usuarios.js — passo 3: usuários próprios (colar lista, tabela editável, gerar senhas,
// CSV) ou compartilhados do Treino Livre.
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';
import { parseUsers, downloadCsv } from '/shared/users-batch.js';

export function makeStepUsuarios(ctx) {
  const d = ctx.draft;
  const prev = el('div', {});

  function renderUsersTable() {
    prev.innerHTML = '';
    if (!d.users.length) { prev.append(el('p', { class: 'muted small' }, T('Cole a lista acima e clique “processar”.', 'Paste the list above and click "process".'))); return; }
    const tb = el('tbody');
    d.users.forEach((u, i) => {
      const mk = (key, ph) => { const inp = el('input', { value: u[key] || '', placeholder: ph, style: 'width:100%' }); inp.addEventListener('input', () => { u[key] = inp.value; }); return inp; };
      const rm = el('button', { class: 'btn danger', onclick: () => { d.users.splice(i, 1); renderUsersTable(); } }, '✕');
      tb.append(el('tr', {},
        el('td', {}, mk('login', T('login', 'login'))), el('td', {}, mk('password', T('(gerada)', '(generated)'))),
        el('td', {}, mk('fullname', T('nome', 'name'))), el('td', {}, mk('email', T('email (opcional)', 'email (optional)'))), el('td', {}, rm)));
    });
    prev.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, T('Login', 'Login')), el('th', {}, T('Senha', 'Password')), el('th', {}, T('Nome', 'Name')), el('th', {}, T('Email', 'Email')), el('th', {}, ''))), tb)),
      el('div', { class: 'small muted', style: 'margin-top:.3rem' }, d.users.length + T(' usuário(s). Senhas em branco são geradas no servidor.', ' user(s). Blank passwords are generated on the server.')));
  }

  const sharedRadio = el('input', { type: 'radio', name: 'umode', value: 'shared' });
  const ownRadio = el('input', { type: 'radio', name: 'umode', value: 'own' });
  (d.userMode === 'shared' ? sharedRadio : ownRadio).checked = true;
  const ownBox = el('div', {});
  const paste = el('textarea', { rows: '5', placeholder: T('Cole aqui. Formatos aceitos por linha:\n  login:senha:nome:email\n  login,nome,email\n  Nome Completo   (login e senha gerados)', 'Paste here. Accepted formats per line:\n  login:password:name:email\n  login,name,email\n  Full Name   (login and password generated)'), style: 'width:100%' });
  const procBtn = el('button', { class: 'btn ghost', onclick: () => { d.users = parseUsers(paste.value); renderUsersTable(); } }, T('Processar lista', 'Process list'));
  const addRow = el('button', { class: 'btn ghost', onclick: () => { d.users.push({ login: '', password: '', fullname: '', email: '' }); renderUsersTable(); } }, T('+ linha', '+ row'));
  const genPw = el('button', { class: 'btn ghost', onclick: async () => {
    const blanks = d.users.filter((u) => !u.password); if (!blanks.length) return;
    const pw = await ctx.genPasswords(blanks.length);
    blanks.forEach((u, i) => { u.password = pw[i] || u.password; }); renderUsersTable();
  } }, T('Gerar senhas faltantes', 'Generate missing passwords'));
  const dlBtn = el('button', { class: 'btn ghost', onclick: () => { if (d.users.length) downloadCsv('credenciais.csv', d.users); } }, T('⬇ baixar CSV', '⬇ download CSV'));
  ownBox.append(paste, el('div', { class: 'row', style: 'margin:.4rem 0' }, procBtn, addRow, genPw, dlBtn), prev);
  renderUsersTable();
  const updateUserMode = () => { d.userMode = ownRadio.checked ? 'own' : 'shared'; ownBox.style.display = d.userMode === 'own' ? '' : 'none'; };
  ownRadio.addEventListener('change', updateUserMode); sharedRadio.addEventListener('change', updateUserMode);
  updateUserMode();

  const root = el('div', { class: 'section' },
    el('h2', {}, T('3 · Usuários', '3 · Users')),
    el('div', { class: 'field' }, el('label', { style: 'font-weight:400' }, ownRadio, T(' Criar usuários próprios do contest', " Create the contest's own users"))),
    el('div', { class: 'field' }, el('label', { style: 'font-weight:400' }, sharedRadio, T(' Compartilhar usuários do Treino Livre (sem gerência; login com a conta do treino)', ' Share Free Training users (no management; login with the training account)'))),
    ownBox);
  return { el: root };
}
