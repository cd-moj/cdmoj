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
    if (!d.users.length) { prev.append(el('p', { class: 'muted small' }, T('Cole a lista acima e clique “processar”.', 'Paste the list above and click "process".', 'Pega la lista de arriba y haz clic en "procesar".'))); return; }
    const tb = el('tbody');
    d.users.forEach((u, i) => {
      const mk = (key, ph) => { const inp = el('input', { value: u[key] || '', placeholder: ph, style: 'width:100%' }); inp.addEventListener('input', () => { u[key] = inp.value; }); return inp; };
      const rm = el('button', { class: 'btn danger', onclick: () => { d.users.splice(i, 1); renderUsersTable(); } }, '✕');
      tb.append(el('tr', {},
        el('td', {}, mk('login', T('login', 'login', 'login'))), el('td', {}, mk('password', T('(gerada)', '(generated)', '(generada)'))),
        el('td', {}, mk('fullname', T('nome', 'name', 'nombre'))), el('td', {}, mk('email', T('email (opcional)', 'email (optional)', 'email (opcional)'))), el('td', {}, rm)));
    });
    prev.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, T('Login', 'Login', 'Usuario')), el('th', {}, T('Senha', 'Password', 'Contraseña')), el('th', {}, T('Nome', 'Name', 'Nombre')), el('th', {}, T('Email', 'Email', 'Correo')), el('th', {}, ''))), tb)),
      el('div', { class: 'small muted', style: 'margin-top:.3rem' }, d.users.length + T(' usuário(s). Senhas em branco são geradas no servidor.', ' user(s). Blank passwords are generated on the server.', ' usuario(s). Las contraseñas en blanco se generan en el servidor.')));
  }

  const sharedRadio = el('input', { type: 'radio', name: 'umode', value: 'shared' });
  const ownRadio = el('input', { type: 'radio', name: 'umode', value: 'own' });
  (d.userMode === 'shared' ? sharedRadio : ownRadio).checked = true;
  const ownBox = el('div', {});
  const paste = el('textarea', { rows: '5', placeholder: T('Cole aqui. Formatos aceitos por linha:\n  login:senha:nome:email\n  login,nome,email\n  Nome Completo   (login e senha gerados)', 'Paste here. Accepted formats per line:\n  login:password:name:email\n  login,name,email\n  Full Name   (login and password generated)', 'Pega aquí. Formatos aceptados por línea:\n  usuario:contraseña:nombre:email\n  usuario,nombre,email\n  Nombre Completo   (usuario y contraseña generados)'), style: 'width:100%' });
  const procBtn = el('button', { class: 'btn ghost', onclick: () => { d.users = parseUsers(paste.value); renderUsersTable(); } }, T('Processar lista', 'Process list', 'Procesar lista'));
  const addRow = el('button', { class: 'btn ghost', onclick: () => { d.users.push({ login: '', password: '', fullname: '', email: '' }); renderUsersTable(); } }, T('+ linha', '+ row', '+ fila'));
  const genPw = el('button', { class: 'btn ghost', onclick: async () => {
    const blanks = d.users.filter((u) => !u.password); if (!blanks.length) return;
    const pw = await ctx.genPasswords(blanks.length);
    blanks.forEach((u, i) => { u.password = pw[i] || u.password; }); renderUsersTable();
  } }, T('Gerar senhas faltantes', 'Generate missing passwords', 'Generar contraseñas faltantes'));
  const dlBtn = el('button', { class: 'btn ghost', onclick: () => { if (d.users.length) downloadCsv('credenciais.csv', d.users); } }, T('⬇ baixar CSV', '⬇ download CSV', '⬇ descargar CSV'));
  ownBox.append(paste, el('div', { class: 'row', style: 'margin:.4rem 0' }, procBtn, addRow, genPw, dlBtn), prev);
  renderUsersTable();
  const updateUserMode = () => { d.userMode = ownRadio.checked ? 'own' : 'shared'; ownBox.style.display = d.userMode === 'own' ? '' : 'none'; };
  ownRadio.addEventListener('change', updateUserMode); sharedRadio.addEventListener('change', updateUserMode);
  updateUserMode();

  const root = el('div', { class: 'section' },
    el('h2', {}, T('3 · Usuários', '3 · Users', '3 · Usuarios')),
    el('div', { class: 'field' }, el('label', { style: 'font-weight:400' }, ownRadio, T(' Criar usuários próprios do contest', " Create the contest's own users", " Crear los propios usuarios de la competencia"))),
    el('div', { class: 'field' }, el('label', { style: 'font-weight:400' }, sharedRadio, T(' Compartilhar usuários do Treino Livre (sem gerência; login com a conta do treino)', ' Share Free Training users (no management; login with the training account)', ' Compartir usuarios de Entrenamiento Libre (sin gestión; inicia sesión con la cuenta del entrenamiento)'))),
    ownBox);
  return { el: root };
}
