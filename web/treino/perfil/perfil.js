// treino/perfil/perfil.js — gerenciar o próprio perfil do Treino Livre.
import { apiGet, apiPost } from '/shared/api.js';
import { status, fileToBase64 } from '/shared/auth.js';
import { el, renderAuthArea, fmtDate } from '/shared/ui.js';
import { EDITORS } from '/shared/editors.js';
import { T, uiLocale } from '/shared/i18n.js';

const CONTEST = 'treino';
const msgBox = () => el('div', { class: 'small', style: 'margin-top:.5rem' });
function ok(box, t) { box.className = 'small v-ok'; box.style.cssText = 'margin-top:.5rem;padding:.3rem .55rem;border-radius:7px'; box.textContent = t; }
function err(box, t) { box.className = 'small error-box'; box.style.cssText = 'margin-top:.5rem'; box.textContent = t; }
const refreshTop = () => renderAuthArea(document.getElementById('authArea'), CONTEST, load);

// avatar: foto (se houver) ou círculo de iniciais com cor estável pelo login
function colorFromName(s) {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return `hsl(${h % 360} 55% 42%)`;
}
function initialsOf(name, login) {
  const src = (name || login || '?').replace(/\[[^\]]*\]/g, '').trim() || login || '?';
  const parts = src.split(/\s+/).filter(Boolean);
  return ((parts[0] || '?')[0] + (parts.length > 1 ? parts[parts.length - 1][0] : '')).toUpperCase();
}
const AVA = 'width:84px;height:84px;border-radius:50%;flex:0 0 auto;object-fit:cover;box-shadow:0 2px 10px rgba(20,40,80,.18);border:3px solid #fff;background:#fff';
function avatarNode(p) {
  if (p.has_photo) {
    return el('img', { alt: T('sua foto', 'your photo', 'tu foto'), style: AVA,
      src: '/api/v1/treino/profile/photo?user=' + encodeURIComponent(p.login) + '&t=' + Date.now() });
  }
  return el('div', { style: AVA + ';display:grid;place-items:center;color:#fff;font-weight:800;font-size:2rem;background:' + colorFromName(p.login) },
    initialsOf(p.name, p.login));
}

function render(p, st) {
  const content = document.getElementById('content');
  content.innerHTML = '';

  // --- Dados: nome + universidade + editor favorito ---
  const nameI = el('input', { value: p.name || '', style: 'width:100%' });
  const univI = el('input', { value: p.university || '', placeholder: T('Ex.: Universidade de Brasília', 'e.g., University of Brasília', 'Ej.: Universidad de Brasília'), style: 'width:100%' });
  const edSel = el('select', { style: 'width:100%' },
    el('option', { value: '' }, T('— não informar —', '— not specified —', '— no especificar —')),
    ...EDITORS.map((e) => el('option', { value: e.id }, e.label)));
  edSel.value = p.favorite_editor || '';
  const dm = msgBox();
  content.append(el('div', { class: 'section' },
    el('h2', {}, T('👤 Dados', '👤 Details', '👤 Datos')),
    el('div', { class: 'field' }, el('label', {}, T('Nome completo', 'Full name', 'Nombre completo')), nameI),
    el('div', { class: 'field' }, el('label', {}, T('Universidade que representa / estuda', 'University you represent / study at', 'Universidad que representas / donde estudias')), univI),
    el('div', { class: 'field' }, el('label', {}, T('Editor / IDE favorito', 'Favorite editor / IDE', 'Editor / IDE favorito')), edSel,
      el('span', { class: 'small muted' }, T('Aparece no seu perfil público e entra no ranking de editores.', 'Shows on your public profile and counts in the editors ranking.', 'Aparece en tu perfil público y cuenta en el ranking de editores.'))),
    el('button', { class: 'btn', onclick: async () => {
      dm.className = 'small'; dm.textContent = T('Salvando…', 'Saving…', 'Guardando…');
      try {
        await apiPost('/treino/profile',
          { name: nameI.value.trim(), university: univI.value.trim(), favorite_editor: edSel.value },
          { contest: CONTEST, auth: true });
        ok(dm, T('✓ Dados salvos', '✓ Details saved', '✓ Datos guardados')); refreshTop();
      } catch (e) { err(dm, e.message || T('falha ao salvar', 'failed to save', 'no se pudo guardar')); }
    } }, T('Salvar dados', 'Save details', 'Guardar datos')), dm));

  // --- Senha ---
  const oldI = el('input', { type: 'password', autocomplete: 'current-password' });
  const n1 = el('input', { type: 'password', autocomplete: 'new-password' });
  const n2 = el('input', { type: 'password', autocomplete: 'new-password' });
  const pm = msgBox();
  content.append(el('div', { class: 'section' },
    el('h2', {}, T('🔑 Senha', '🔑 Password', '🔑 Contraseña')),
    el('div', { class: 'field' }, el('label', {}, T('Senha atual', 'Current password', 'Contraseña actual')), oldI),
    el('div', { class: 'field' }, el('label', {}, T('Nova senha', 'New password', 'Nueva contraseña')), n1),
    el('div', { class: 'field' }, el('label', {}, T('Confirmar nova senha', 'Confirm new password', 'Confirmar nueva contraseña')), n2),
    el('button', { class: 'btn', onclick: async () => {
      if (n1.value !== n2.value) { err(pm, T('As senhas não conferem', 'Passwords do not match', 'Las contraseñas no coinciden')); return; }
      pm.className = 'small'; pm.textContent = T('Salvando…', 'Saving…', 'Guardando…');
      try {
        await apiPost('/treino/profile/password', { old_password: oldI.value, new_password: n1.value }, { contest: CONTEST, auth: true });
        ok(pm, T('✓ Senha alterada', '✓ Password changed', '✓ Contraseña cambiada')); oldI.value = n1.value = n2.value = '';
      } catch (e) { err(pm, e.message || T('falha', 'failed', 'fallido')); }
    } }, T('Trocar senha', 'Change password', 'Cambiar contraseña')), pm));

  // --- Telegram: vínculo com o bot (senha por DM; .admin recebe alertas do sistema) ---
  const tg = p.telegram || { linked: false };
  const tgM = msgBox();
  const tgBody = el('div', {});
  const adminNote = (st && st.is_admin)
    ? el('p', { class: 'notice', style: 'margin:.4rem 0' },
        T('Contas .admin vinculadas recebem os ALERTAS do sistema (juízes offline, fila crescendo, daemon parado) por DM do bot.',
          '.admin accounts that are linked receive system ALERTS (judges offline, growing queue, stopped daemon) via bot DM.',
          'Las cuentas .admin vinculadas reciben las ALERTAS del sistema (jueces fuera de línea, cola creciendo, daemon detenido) por DM del bot.'))
    : null;
  if (tg.linked) {
    // cota de desvínculo: usuário comum tem TELEGRAM_CHANGE_LIMIT (1)/ano; .admin livre
    // (changes_limit null). O vínculo é a identidade da conta — anti conta-descartável.
    const free = tg.changes_limit == null;
    const canUnlink = free || (tg.changes_remaining || 0) > 0;
    const nextStr = tg.next_available ? fmtDate(tg.next_available) : '';
    tgBody.append(
      el('p', { style: 'margin:.2rem 0' }, '✅ ',
        T('Telegram vinculado', 'Telegram linked', 'Telegram vinculado'),
        tg.username ? el('b', {}, ' @' + tg.username) : '',
        tg.linked_at ? el('span', { class: 'small muted' }, ' · ' + T('desde ', 'since ', 'desde ') + fmtDate(tg.linked_at)) : ''),
      adminNote || '',
      free ? '' : el('p', { class: 'small muted', style: 'margin:.2rem 0' },
        T(`O Telegram vinculado é a identidade da sua conta: no máximo ${tg.changes_limit} troca por ano.`,
          `Your linked Telegram is your account identity: at most ${tg.changes_limit} change per year.`,
          `Tu Telegram vinculado es la identidad de tu cuenta: como máximo ${tg.changes_limit} cambio por año.`),
        !canUnlink && nextStr ? ' ' + T(`Próxima troca disponível em ${nextStr}.`, `Next change available on ${nextStr}.`, `Próximo cambio disponible el ${nextStr}.`) : ''),
      el('button', { class: 'btn ghost', disabled: !canUnlink, onclick: async () => {
        if (!confirm(T('Desvincular o Telegram desta conta? Você deixa de receber senha/alertas por DM' + (free ? '' : ' e esta é sua troca do ano') + '.',
                       'Unlink Telegram from this account? You will stop receiving passwords/alerts via DM' + (free ? '' : ' and this uses your yearly change') + '.',
                       '¿Desvincular Telegram de esta cuenta? Dejarás de recibir contraseñas/alertas por DM' + (free ? '' : ' y este es tu cambio del año') + '.'))) return;
        tgM.className = 'small'; tgM.textContent = T('Desvinculando…', 'Unlinking…', 'Desvinculando…');
        try { await apiPost('/treino/telegram/unlink', {}, { contest: CONTEST, auth: true }); ok(tgM, T('✓ Desvinculado', '✓ Unlinked', '✓ Desvinculado')); setTimeout(load, 800); }
        catch (e) { err(tgM, e.message || T('falha', 'failed', 'fallido')); }
      } }, T('Desvincular', 'Unlink', 'Desvincular')));
  } else if (p.managed && p.managed.minor) {
    // conta GERIDA de menor: o vínculo com o Telegram libera automaticamente aos 18
    tgBody.append(el('p', { class: 'small muted', style: 'margin:.2rem 0' },
      T('Esta é uma conta gerida por um responsável. O vínculo com o Telegram é liberado automaticamente quando você completa 18 anos. Esqueceu a senha? Fale com quem criou a sua conta.',
        'This account is managed by a guardian. Telegram linking unlocks automatically when you turn 18. Forgot your password? Ask the person who created your account.',
        'Esta es una cuenta gestionada por un responsable. La vinculación con Telegram se habilita automáticamente cuando cumples 18 años. ¿Olvidaste tu contraseña? Habla con quien creó tu cuenta.')));
  } else {
    const linkBtn = el('button', { class: 'btn' }, T('🔗 Vincular Telegram', '🔗 Link Telegram', '🔗 Vincular Telegram'));
    linkBtn.onclick = async () => {
      linkBtn.disabled = true; tgM.className = 'small'; tgM.textContent = T('Gerando link…', 'Generating link…', 'Generando enlace…');
      try {
        const r = await apiPost('/treino/telegram/link-start', {}, { contest: CONTEST, auth: true });
        tgM.textContent = '';
        const until = r.expires_at ? new Date(r.expires_at * 1000).toLocaleTimeString(uiLocale()) : '';
        tgBody.innerHTML = '';
        tgBody.append(
          el('p', { style: 'margin:.2rem 0' }, T('1. Abra o bot e toque em ', '1. Open the bot and tap ', '1. Abre el bot y toca '), el('b', {}, 'INICIAR / START'), ':'),
          el('a', { class: 'btn', href: r.deep_link, target: '_blank', rel: 'noopener' }, T('Abrir @', 'Open @', 'Abrir @') + (r.deep_link.match(/t\.me\/([^?]+)/) || [,'mojinho_bot'])[1] + T(' no Telegram', ' on Telegram', ' en Telegram')),
          el('p', { class: 'small muted', style: 'margin:.4rem 0' },
            T('O link confirma sozinho o vínculo desta conta', 'The link confirms this account\'s binding by itself', 'El enlace confirma por sí solo la vinculación de esta cuenta'),
            until ? T(' e vale até ', ' and is valid until ', ' y es válido hasta ') + until : '', '.'),
          el('button', { class: 'btn ghost', onclick: () => load() }, T('já confirmei no Telegram ↻', 'I confirmed on Telegram ↻', 'ya confirmé en Telegram ↻')));
      } catch (e) { linkBtn.disabled = false; err(tgM, e.message || T('falha', 'failed', 'fallido')); }
    };
    tgBody.append(
      el('p', { class: 'small muted', style: 'margin:.2rem 0' },
        T('Vincule seu Telegram para recuperar a senha por DM (e provar que a conta é sua).',
          'Link your Telegram to recover your password via DM (and prove the account is yours).',
          'Vincula tu Telegram para recuperar la contraseña por DM (y demostrar que la cuenta es tuya).')),
      adminNote || '',
      linkBtn);
  }
  content.append(el('div', { class: 'section' },
    el('h2', {}, T('📨 Telegram', '📨 Telegram', '📨 Telegram')),
    tgBody, tgM));

  // --- Privacidade: perfil público / privado ---
  const isPublic = p.profile_public !== false;
  const privM = msgBox();
  const privChk = el('input', { type: 'checkbox', id: 'privChk' });
  privChk.checked = isPublic;
  privChk.addEventListener('change', async () => {
    privChk.disabled = true; privM.className = 'small'; privM.textContent = T('Salvando…', 'Saving…', 'Guardando…');
    try {
      await apiPost('/treino/profile', { profile_public: privChk.checked }, { contest: CONTEST, auth: true });
      ok(privM, privChk.checked ? T('✓ Perfil público', '✓ Profile public', '✓ Perfil público') : T('✓ Perfil privado', '✓ Profile private', '✓ Perfil privado'));
    } catch (e) { privChk.checked = !privChk.checked; err(privM, e.message || T('falha ao salvar', 'failed to save', 'no se pudo guardar')); }
    finally { privChk.disabled = false; }
  });
  // conta gerida de menor: o perfil é SEMPRE privado (o servidor recusa tornar público)
  const managedMinor = !!(p.managed && p.managed.minor);
  if (managedMinor) { privChk.checked = false; privChk.disabled = true; }
  content.append(el('div', { class: 'section' },
    el('h2', {}, T('🔒 Privacidade', '🔒 Privacy', '🔒 Privacidad')),
    el('label', { class: 'row', for: 'privChk', style: 'gap:.5rem; cursor:pointer; font-weight:600' },
      privChk, T('Perfil público', 'Public profile', 'Perfil público')),
    el('p', { class: 'small muted', style: 'margin:.4rem 0 0' },
      managedMinor
        ? T('Conta gerida: o perfil fica privado até você completar 18 anos.',
            'Managed account: the profile stays private until you turn 18.',
            'Cuenta gestionada: el perfil permanece privado hasta que cumplas 18 años.')
        : T('Se desmarcado, suas estatísticas e histórico ficam visíveis só para você.', 'If unchecked, your statistics and history are visible only to you.', 'Si lo desmarcas, tus estadísticas e historial quedan visibles solo para ti.')),
    privM));

  // --- Foto de perfil ---
  const photoM = msgBox();
  const avatarBox = el('div', { style: 'flex:0 0 auto' }, avatarNode(p));
  const fileI = el('input', { type: 'file', accept: 'image/*' });
  fileI.addEventListener('change', async () => {
    const f = fileI.files && fileI.files[0];
    if (!f) return;
    photoM.className = 'small'; photoM.textContent = T('Enviando…', 'Uploading…', 'Subiendo…');
    try {
      const image_b64 = await fileToBase64(f);
      await apiPost('/treino/profile/photo', { image_b64 }, { contest: CONTEST, auth: true });
      // recarrega o avatar com novo cachebust
      p.has_photo = true;
      avatarBox.innerHTML = ''; avatarBox.append(avatarNode(p));
      ok(photoM, T('✓ Foto atualizada', '✓ Photo updated', '✓ Foto actualizada')); refreshTop();
    } catch (e) { err(photoM, e.message || T('falha ao enviar a foto', 'failed to upload the photo', 'no se pudo subir la foto')); }
    finally { fileI.value = ''; }
  });
  content.append(el('div', { class: 'section' },
    el('h2', {}, T('🖼️ Foto de perfil', '🖼️ Profile photo', '🖼️ Foto de perfil')),
    el('div', { class: 'row', style: 'gap:1.2rem; align-items:center' },
      avatarBox,
      el('div', {},
        el('div', { class: 'field', style: 'margin:0' },
          el('label', {}, T('Enviar nova foto', 'Upload new photo', 'Subir nueva foto')), fileI),
        el('p', { class: 'small muted', style: 'margin:.4rem 0 0' },
          T('A imagem será recortada/redimensionada para 100×100 pixels.', 'The image will be cropped/resized to 100×100 pixels.', 'La imagen se recortará/redimensionará a 100×100 píxeles.')))),
    photoM));

  // --- Nome de usuário (handle) — limite explícito ---
  const used = p.username_changes_used || 0, limit = p.username_changes_limit || 2, rem = p.username_changes_remaining || 0;
  const canChange = rem > 0;
  const next = p.username_next_available ? fmtDate(p.username_next_available) : null;
  const uI = el('input', { placeholder: T('novo_nome_de_usuario', 'new_username', 'nuevo_nombre_de_usuario'), disabled: !canChange });
  const um = msgBox();
  const note = el('div', { class: canChange ? 'notice' : 'error-box', style: 'margin-bottom:.7rem' },
    canChange
      ? T(`⚠️ Você pode trocar o nome de usuário no máximo ${limit} vezes por ano. Você já usou ${used} de ${limit} — restam ${rem}. Escolha com cuidado.`, `⚠️ You can change your username at most ${limit} times per year. You have used ${used} of ${limit} — ${rem} left. Choose carefully.`, `⚠️ Puedes cambiar tu nombre de usuario como máximo ${limit} veces por año. Ya usaste ${used} de ${limit} — quedan ${rem}. Elige con cuidado.`)
      : T(`🚫 Limite de ${limit} trocas por ano atingido (usou ${used}/${limit}).`, `🚫 Yearly limit of ${limit} changes reached (used ${used}/${limit}).`, `🚫 Límite anual de ${limit} cambios alcanzado (usaste ${used}/${limit}).`) + (next ? T(` Próxima troca disponível em ${next}.`, ` Next change available on ${next}.`, ` Próximo cambio disponible el ${next}.`) : ''));
  content.append(el('div', { class: 'section' },
    el('h2', {}, T('🏷️ Nome de usuário (handle)', '🏷️ Username (handle)', '🏷️ Nombre de usuario (handle)')),
    el('p', { class: 'small muted' }, T('Seu login atual é ', 'Your current login is ', 'Tu usuario actual es '), el('b', {}, p.login),
      T('. Trocar o handle atualiza todo o seu histórico do Treino Livre (submissões, estatísticas, etc.) e vale em todos os dispositivos onde você está conectado — inclusive na CLI: ninguém é deslogado.', '. Changing the handle updates all your Free Training history (submissions, statistics, etc.) and applies to every device you are logged in on — the CLI included: nobody gets logged out.', '. Cambiar el handle actualiza todo tu historial de Entrenamiento libre (envíos, estadísticas, etc.) y vale en todos los dispositivos donde tienes sesión iniciada — incluida la CLI: a nadie se le cierra la sesión.')),
    (() => {
      const m = /\.(admin|cjudge|judge|cstaff|staff|mon)$/.exec(p.login);
      return m ? el('p', { class: 'small notice', style: 'margin:.3rem 0' },
        T('Sua conta tem papel pelo sufixo ', 'Your account carries its role in the suffix ', 'Tu cuenta lleva su rol en el sufijo '), el('b', {}, '.' + m[1]),
        T(': a troca precisa MANTER o sufixo (ex.: novo_nome.', ': the change must KEEP the suffix (e.g., new_name.', ': el cambio debe MANTENER el sufijo (ej.: nuevo_nombre.'), m[1] + ').') : '';
    })(),
    note,
    el('div', { class: 'field' }, el('label', {}, T('Novo nome de usuário', 'New username', 'Nuevo nombre de usuario')), uI),
    el('button', { class: 'btn', disabled: !canChange, onclick: async () => {
      const nv = uI.value.trim();
      if (!nv) { err(um, T('Informe o novo nome de usuário', 'Enter the new username', 'Ingresa el nuevo nombre de usuario')); return; }
      if (!confirm(T(`Trocar seu nome de usuário para "${nv}"?\nIsso conta como 1 das ${limit} trocas anuais e não dá para desfazer.`, `Change your username to "${nv}"?\nThis counts as 1 of ${limit} yearly changes and cannot be undone.`, `¿Cambiar tu nombre de usuario a "${nv}"?\nEsto cuenta como 1 de los ${limit} cambios anuales y no se puede deshacer.`))) return;
      um.className = 'small'; um.textContent = T('Trocando…', 'Changing…', 'Cambiando…');
      try {
        const r = await apiPost('/treino/profile/username', { new_username: nv }, { contest: CONTEST, auth: true });
        ok(um, T(`✓ Agora você é "${r.new_username}". Restam ${r.username_changes_remaining} troca(s) neste ano.`, `✓ You are now "${r.new_username}". ${r.username_changes_remaining} change(s) left this year.`, `✓ Ahora eres "${r.new_username}". Quedan ${r.username_changes_remaining} cambio(s) este año.`));
        refreshTop(); setTimeout(load, 1000);
      } catch (e) { err(um, e.message || T('falha', 'failed', 'fallido')); }
    } }, T('Trocar nome de usuário', 'Change username', 'Cambiar nombre de usuario')), um));
}

async function load() {
  const content = document.getElementById('content');
  const st = await status(CONTEST);
  if (!st.logged_in) {
    content.innerHTML = '<div class="notice" style="margin-top:1rem">' + T('Entre (no topo da página) para ver e editar seu perfil.', 'Log in (at the top of the page) to view and edit your profile.', 'Inicia sesión (arriba de la página) para ver y editar tu perfil.') + '</div>';
    return;
  }
  try {
    const p = await apiGet('/treino/profile', { contest: CONTEST, auth: true });
    render(p, st);
  } catch (e) {
    content.innerHTML = '<div class="error-box" style="margin-top:1rem">' + T('Falha ao carregar o perfil: ', 'Failed to load the profile: ', 'Error al cargar el perfil: ') + (e.message || '') + '</div>';
  }
}

async function boot() {
  await renderAuthArea(document.getElementById('authArea'), CONTEST, load);
  load();
}
boot();
