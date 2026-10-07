// steps/usuarios.js — passo 3: usuários próprios (colar lista, tabela editável, gerar senhas,
// CSV) ou compartilhados do Treino Livre. Compartilhar tem consequências que ninguém adivinha (relato
// de 28/09/2026: "não dá para desfazer e nada avisa") — a caixa lista as 5 e o ☐ "Entendi" é exigido
// no envio (criar.js); desfazer = Pessoas › Contas › converter em contas próprias.
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';
import { parseUsers, downloadCsv } from '/shared/users-batch.js';

// a caixa das 5 consequências + o ☐ "Entendi" (`ack`) — a MESMA no passo 3 e na cópia fiel do passo 0 (que pede as
// contas do treino por conta própria: o duplicate nunca herda users_from)
export function sharedNotice(ack) {
  return el('div', { class: 'notice', style: 'margin:.4rem 0' },
    el('b', {}, T('Antes de compartilhar, saiba que:', 'Before sharing, be aware that:', 'Antes de compartir, ten en cuenta que:')),
    el('ol', { class: 'small', style: 'margin:.3rem 0; padding-left:1.3rem' },
      el('li', {}, T('Login e senha são os do Treino Livre: você não os vê nem redefine, e as etiquetas saem sem senha.',
        'Login and password are the Free Training ones: you cannot see or reset them, and the badges come out without a password.',
        'El usuario y la contraseña son los de Entrenamiento libre: no los ves ni los restableces, y las etiquetas salen sin contraseña.')),
      el('li', {}, T('Qualquer conta do Treino Livre consegue entrar — para limitar, ligue o módulo Inscrições (inscrição prévia).',
        'Any Free Training account can get in — to limit it, turn on the Registrations module (prior registration).',
        'Cualquier cuenta de Entrenamiento libre puede entrar — para limitarlo, activa el módulo Inscripciones (inscripción previa).')),
      el('li', {}, T('Só o seu .admin e os superadmins entram com papel; juízes, staff e outros organizadores precisam de contas próprias (Pessoas › Contas).',
        'Only your .admin and the superadmins get in with a role; judges, staff and other organizers need their own accounts (People › Accounts).',
        'Solo tu .admin y los superadmins entran con rol; jueces, staff y otros organizadores necesitan cuentas propias (Personas › Cuentas).')),
      el('li', {}, T('Não existe troca de senha geral de prova: quem conhece a senha do Treino de alguém entra como essa pessoa aqui também.',
        'There is no exam-wide password change: whoever knows someone\'s Free Training password gets in as that person here too.',
        'No existe cambio masivo de contraseña para el examen: quien conoce la contraseña de Entrenamiento libre de alguien entra como esa persona aquí también.')),
      el('li', {}, T('Dá para desfazer: Pessoas › Contas › converter em contas próprias (senhas novas; histórico e placar ficam; cada time vira uma conta). A conversão não tem volta.',
        'It can be undone: People › Accounts › convert into own accounts (new passwords; history and scoreboard stay; each team becomes one account). The conversion itself cannot be reverted.',
        'Se puede deshacer: Personas › Cuentas › convertir en cuentas propias (contraseñas nuevas; el historial y el marcador se mantienen; cada equipo pasa a ser una cuenta). La conversión no tiene vuelta atrás.'))),
    el('label', { class: 'small', style: 'font-weight:600' }, ack, T(' Entendi', ' I understand', ' Entendido')));
}

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
  const ack = el('input', { type: 'checkbox' });
  ack.checked = !!d.sharedAck;
  ack.addEventListener('change', () => { d.sharedAck = ack.checked; });
  const sharedBox = sharedNotice(ack);
  const paste = el('textarea', { rows: '5', placeholder: T('Cole aqui. Formatos aceitos por linha:\n  login:senha:nome:email\n  login,nome,email\n  Nome Completo   (login e senha gerados)', 'Paste here. Accepted formats per line:\n  login:password:name:email\n  login,name,email\n  Full Name   (login and password generated)', 'Pega aquí. Formatos aceptados por línea:\n  usuario:contraseña:nombre:email\n  usuario,nombre,email\n  Nombre Completo   (usuario y contraseña generados)'), style: 'width:100%' });
  const procBtn = el('button', { class: 'btn ghost', onclick: () => { d.users = parseUsers(paste.value); renderUsersTable(); } }, T('Processar lista', 'Process list', 'Procesar lista'));
  const addRow = el('button', { class: 'btn ghost', onclick: () => { d.users.push({ login: '', password: '', fullname: '', email: '' }); renderUsersTable(); } }, T('+ linha', '+ row', '+ fila'));
  const genPw = el('button', { class: 'btn ghost', onclick: async () => {
    const blanks = d.users.filter((u) => !u.password); if (!blanks.length) return;
    const pw = await ctx.genPasswords(blanks.length);
    blanks.forEach((u, i) => { u.password = pw[i] || u.password; }); renderUsersTable();
  } }, T('Gerar senhas faltantes', 'Generate missing passwords', 'Generar contraseñas faltantes'));
  const dlBtn = el('button', { class: 'btn ghost', onclick: () => { if (d.users.length) downloadCsv('credenciais.csv', d.users); } }, T('⬇ baixar CSV', '⬇ download CSV', '⬇ descargar CSV'));
  // o ':' de um nome é gravado como '∶' (lib/common.sh name_clean: o placar é TXT separado por ':'), e uma linha com
  // ':' é sempre login:senha:nome:email — a tabela abaixo mostra como cada linha foi lida (TCP 2026)
  const colonHint = el('p', { class: 'small muted', style: 'margin:.2rem 0' }, T('Linha com “:” é lida como login:senha:nome:email (confira a tabela). Um “:” no nome é gravado como “∶” (parece igual): o placar usa “:” como separador.',
    'A line with “:” is read as login:password:name:email (check the table). A “:” in a name is saved as “∶” (looks the same): the scoreboard uses “:” as a separator.',
    'Una línea con “:” se lee como usuario:contraseña:nombre:email (revisa la tabla). Un “:” en el nombre se guarda como “∶” (se ve igual): el marcador usa “:” como separador.'));
  ownBox.append(paste, colonHint, el('div', { class: 'row', style: 'margin:.4rem 0' }, procBtn, addRow, genPw, dlBtn), prev);
  renderUsersTable();
  const updateUserMode = () => {
    d.userMode = ownRadio.checked ? 'own' : 'shared';
    ownBox.style.display = d.userMode === 'own' ? '' : 'none';
    sharedBox.style.display = d.userMode === 'shared' ? '' : 'none';
  };
  ownRadio.addEventListener('change', updateUserMode); sharedRadio.addEventListener('change', updateUserMode);
  updateUserMode();

  const root = el('div', { class: 'section' },
    el('h2', {}, T('3 · Usuários', '3 · Users', '3 · Usuarios')),
    el('div', { class: 'field' }, el('label', { style: 'font-weight:400' }, ownRadio, T(' Criar usuários próprios do contest', " Create the contest's own users", " Crear los propios usuarios de la competencia"))),
    el('div', { class: 'field' }, el('label', { style: 'font-weight:400' }, sharedRadio, T(' Compartilhar usuários do Treino Livre (sem gerência; login com a conta do treino)', ' Share Free Training users (no management; login with the training account)', ' Compartir usuarios de Entrenamiento libre (sin gestión; inicia sesión con la cuenta del entrenamiento)'))),
    sharedBox, ownBox);
  return { el: root };
}
