// treino/perfil/perfil.js — gerenciar o próprio perfil do Treino Livre.
import { apiGet, apiPost } from '/shared/api.js';
import { status, fileToBase64 } from '/shared/auth.js';
import { el, renderAuthArea, fmtDate } from '/shared/ui.js';
import { EDITORS } from '/shared/editors.js';
import { T } from '/shared/i18n.js';

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
    return el('img', { alt: T('sua foto', 'your photo'), style: AVA,
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
  const univI = el('input', { value: p.university || '', placeholder: T('Ex.: Universidade de Brasília', 'e.g., University of Brasília'), style: 'width:100%' });
  const edSel = el('select', { style: 'width:100%' },
    el('option', { value: '' }, T('— não informar —', '— not specified —')),
    ...EDITORS.map((e) => el('option', { value: e.id }, e.label)));
  edSel.value = p.favorite_editor || '';
  const dm = msgBox();
  content.append(el('div', { class: 'section' },
    el('h2', {}, T('👤 Dados', '👤 Details')),
    el('div', { class: 'field' }, el('label', {}, T('Nome completo', 'Full name')), nameI),
    el('div', { class: 'field' }, el('label', {}, T('Universidade que representa / estuda', 'University you represent / study at')), univI),
    el('div', { class: 'field' }, el('label', {}, T('Editor / IDE favorito', 'Favorite editor / IDE')), edSel,
      el('span', { class: 'small muted' }, T('Aparece no seu perfil público e entra no ranking de editores.', 'Shows on your public profile and counts in the editors ranking.'))),
    el('button', { class: 'btn', onclick: async () => {
      dm.className = 'small'; dm.textContent = T('Salvando…', 'Saving…');
      try {
        await apiPost('/treino/profile',
          { name: nameI.value.trim(), university: univI.value.trim(), favorite_editor: edSel.value },
          { contest: CONTEST, auth: true });
        ok(dm, T('✓ Dados salvos', '✓ Details saved')); refreshTop();
      } catch (e) { err(dm, e.message || T('falha ao salvar', 'failed to save')); }
    } }, T('Salvar dados', 'Save details')), dm));

  // --- Senha ---
  const oldI = el('input', { type: 'password', autocomplete: 'current-password' });
  const n1 = el('input', { type: 'password', autocomplete: 'new-password' });
  const n2 = el('input', { type: 'password', autocomplete: 'new-password' });
  const pm = msgBox();
  content.append(el('div', { class: 'section' },
    el('h2', {}, T('🔑 Senha', '🔑 Password')),
    el('div', { class: 'field' }, el('label', {}, T('Senha atual', 'Current password')), oldI),
    el('div', { class: 'field' }, el('label', {}, T('Nova senha', 'New password')), n1),
    el('div', { class: 'field' }, el('label', {}, T('Confirmar nova senha', 'Confirm new password')), n2),
    el('button', { class: 'btn', onclick: async () => {
      if (n1.value !== n2.value) { err(pm, T('As senhas não conferem', 'Passwords do not match')); return; }
      pm.className = 'small'; pm.textContent = T('Salvando…', 'Saving…');
      try {
        await apiPost('/treino/profile/password', { old_password: oldI.value, new_password: n1.value }, { contest: CONTEST, auth: true });
        ok(pm, T('✓ Senha alterada', '✓ Password changed')); oldI.value = n1.value = n2.value = '';
      } catch (e) { err(pm, e.message || T('falha', 'failed')); }
    } }, T('Trocar senha', 'Change password')), pm));

  // --- Telegram: vínculo com o bot (senha por DM; .admin recebe alertas do sistema) ---
  const tg = p.telegram || { linked: false };
  const tgM = msgBox();
  const tgBody = el('div', {});
  const adminNote = (st && st.is_admin)
    ? el('p', { class: 'notice', style: 'margin:.4rem 0' },
        T('Contas .admin vinculadas recebem os ALERTAS do sistema (juízes offline, fila crescendo, daemon parado) por DM do bot.',
          '.admin accounts that are linked receive system ALERTS (judges offline, growing queue, stopped daemon) via bot DM.'))
    : null;
  if (tg.linked) {
    tgBody.append(
      el('p', { style: 'margin:.2rem 0' }, '✅ ',
        T('Telegram vinculado', 'Telegram linked'),
        tg.username ? el('b', {}, ' @' + tg.username) : '',
        tg.linked_at ? el('span', { class: 'small muted' }, ' · ' + T('desde ', 'since ') + fmtDate(tg.linked_at)) : ''),
      adminNote || '',
      el('button', { class: 'btn ghost', onclick: async () => {
        if (!confirm(T('Desvincular o Telegram desta conta? Você deixa de receber senha/alertas por DM.',
                       'Unlink Telegram from this account? You will stop receiving passwords/alerts via DM.'))) return;
        tgM.className = 'small'; tgM.textContent = T('Desvinculando…', 'Unlinking…');
        try { await apiPost('/treino/telegram/unlink', {}, { contest: CONTEST, auth: true }); ok(tgM, T('✓ Desvinculado', '✓ Unlinked')); setTimeout(load, 800); }
        catch (e) { err(tgM, e.message || T('falha', 'failed')); }
      } }, T('Desvincular', 'Unlink')));
  } else {
    const linkBtn = el('button', { class: 'btn' }, T('🔗 Vincular Telegram', '🔗 Link Telegram'));
    linkBtn.onclick = async () => {
      linkBtn.disabled = true; tgM.className = 'small'; tgM.textContent = T('Gerando link…', 'Generating link…');
      try {
        const r = await apiPost('/treino/telegram/link-start', {}, { contest: CONTEST, auth: true });
        tgM.textContent = '';
        const until = r.expires_at ? new Date(r.expires_at * 1000).toLocaleTimeString() : '';
        tgBody.innerHTML = '';
        tgBody.append(
          el('p', { style: 'margin:.2rem 0' }, T('1. Abra o bot e toque em ', '1. Open the bot and tap '), el('b', {}, 'INICIAR / START'), ':'),
          el('a', { class: 'btn', href: r.deep_link, target: '_blank', rel: 'noopener' }, T('Abrir @', 'Open @') + (r.deep_link.match(/t\.me\/([^?]+)/) || [,'mojinho_bot'])[1] + T(' no Telegram', ' on Telegram')),
          el('p', { class: 'small muted', style: 'margin:.4rem 0' },
            T('O link confirma sozinho o vínculo desta conta', 'The link confirms this account\'s binding by itself'),
            until ? T(' e vale até ', ' and is valid until ') + until : '', '.'),
          el('button', { class: 'btn ghost', onclick: () => load() }, T('já confirmei no Telegram ↻', 'I confirmed on Telegram ↻')));
      } catch (e) { linkBtn.disabled = false; err(tgM, e.message || T('falha', 'failed')); }
    };
    tgBody.append(
      el('p', { class: 'small muted', style: 'margin:.2rem 0' },
        T('Vincule seu Telegram para recuperar a senha por DM (e provar que a conta é sua).',
          'Link your Telegram to recover your password via DM (and prove the account is yours).')),
      adminNote || '',
      linkBtn);
  }
  content.append(el('div', { class: 'section' },
    el('h2', {}, T('📨 Telegram', '📨 Telegram')),
    tgBody, tgM));

  // --- Privacidade: perfil público / privado ---
  const isPublic = p.profile_public !== false;
  const privM = msgBox();
  const privChk = el('input', { type: 'checkbox', id: 'privChk' });
  privChk.checked = isPublic;
  privChk.addEventListener('change', async () => {
    privChk.disabled = true; privM.className = 'small'; privM.textContent = T('Salvando…', 'Saving…');
    try {
      await apiPost('/treino/profile', { profile_public: privChk.checked }, { contest: CONTEST, auth: true });
      ok(privM, privChk.checked ? T('✓ Perfil público', '✓ Profile public') : T('✓ Perfil privado', '✓ Profile private'));
    } catch (e) { privChk.checked = !privChk.checked; err(privM, e.message || T('falha ao salvar', 'failed to save')); }
    finally { privChk.disabled = false; }
  });
  content.append(el('div', { class: 'section' },
    el('h2', {}, T('🔒 Privacidade', '🔒 Privacy')),
    el('label', { class: 'row', for: 'privChk', style: 'gap:.5rem; cursor:pointer; font-weight:600' },
      privChk, T('Perfil público', 'Public profile')),
    el('p', { class: 'small muted', style: 'margin:.4rem 0 0' },
      T('Se desmarcado, suas estatísticas e histórico ficam visíveis só para você.', 'If unchecked, your statistics and history are visible only to you.')),
    privM));

  // --- Foto de perfil ---
  const photoM = msgBox();
  const avatarBox = el('div', { style: 'flex:0 0 auto' }, avatarNode(p));
  const fileI = el('input', { type: 'file', accept: 'image/*' });
  fileI.addEventListener('change', async () => {
    const f = fileI.files && fileI.files[0];
    if (!f) return;
    photoM.className = 'small'; photoM.textContent = T('Enviando…', 'Uploading…');
    try {
      const image_b64 = await fileToBase64(f);
      await apiPost('/treino/profile/photo', { image_b64 }, { contest: CONTEST, auth: true });
      // recarrega o avatar com novo cachebust
      p.has_photo = true;
      avatarBox.innerHTML = ''; avatarBox.append(avatarNode(p));
      ok(photoM, T('✓ Foto atualizada', '✓ Photo updated')); refreshTop();
    } catch (e) { err(photoM, e.message || T('falha ao enviar a foto', 'failed to upload the photo')); }
    finally { fileI.value = ''; }
  });
  content.append(el('div', { class: 'section' },
    el('h2', {}, T('🖼️ Foto de perfil', '🖼️ Profile photo')),
    el('div', { class: 'row', style: 'gap:1.2rem; align-items:center' },
      avatarBox,
      el('div', {},
        el('div', { class: 'field', style: 'margin:0' },
          el('label', {}, T('Enviar nova foto', 'Upload new photo')), fileI),
        el('p', { class: 'small muted', style: 'margin:.4rem 0 0' },
          T('A imagem será recortada/redimensionada para 100×100 pixels.', 'The image will be cropped/resized to 100×100 pixels.')))),
    photoM));

  // --- Nome de usuário (handle) — limite explícito ---
  const used = p.username_changes_used || 0, limit = p.username_changes_limit || 2, rem = p.username_changes_remaining || 0;
  const canChange = rem > 0;
  const next = p.username_next_available ? fmtDate(p.username_next_available) : null;
  const uI = el('input', { placeholder: T('novo_nome_de_usuario', 'new_username'), disabled: !canChange });
  const um = msgBox();
  const note = el('div', { class: canChange ? 'notice' : 'error-box', style: 'margin-bottom:.7rem' },
    canChange
      ? T(`⚠️ Você pode trocar o nome de usuário no máximo ${limit} vezes por ano. Você já usou ${used} de ${limit} — restam ${rem}. Escolha com cuidado.`, `⚠️ You can change your username at most ${limit} times per year. You have used ${used} of ${limit} — ${rem} left. Choose carefully.`)
      : T(`🚫 Limite de ${limit} trocas por ano atingido (usou ${used}/${limit}).`, `🚫 Yearly limit of ${limit} changes reached (used ${used}/${limit}).`) + (next ? T(` Próxima troca disponível em ${next}.`, ` Next change available on ${next}.`) : ''));
  content.append(el('div', { class: 'section' },
    el('h2', {}, T('🏷️ Nome de usuário (handle)', '🏷️ Username (handle)')),
    el('p', { class: 'small muted' }, T('Seu login atual é ', 'Your current login is '), el('b', {}, p.login),
      T('. Trocar o handle atualiza todo o seu histórico do Treino Livre (submissões, estatísticas, etc.).', '. Changing the handle updates all your Free Training history (submissions, statistics, etc.).')),
    (() => {
      const m = /\.(admin|cjudge|judge|cstaff|staff|mon)$/.exec(p.login);
      return m ? el('p', { class: 'small notice', style: 'margin:.3rem 0' },
        T('Sua conta tem papel pelo sufixo ', 'Your account carries its role in the suffix '), el('b', {}, '.' + m[1]),
        T(': a troca precisa MANTER o sufixo (ex.: novo_nome.', ': the change must KEEP the suffix (e.g., new_name.'), m[1] + ').') : '';
    })(),
    note,
    el('div', { class: 'field' }, el('label', {}, T('Novo nome de usuário', 'New username')), uI),
    el('button', { class: 'btn', disabled: !canChange, onclick: async () => {
      const nv = uI.value.trim();
      if (!nv) { err(um, T('Informe o novo nome de usuário', 'Enter the new username')); return; }
      if (!confirm(T(`Trocar seu nome de usuário para "${nv}"?\nIsso conta como 1 das ${limit} trocas anuais e não dá para desfazer.`, `Change your username to "${nv}"?\nThis counts as 1 of ${limit} yearly changes and cannot be undone.`))) return;
      um.className = 'small'; um.textContent = T('Trocando…', 'Changing…');
      try {
        const r = await apiPost('/treino/profile/username', { new_username: nv }, { contest: CONTEST, auth: true });
        ok(um, T(`✓ Agora você é "${r.new_username}". Restam ${r.username_changes_remaining} troca(s) neste ano.`, `✓ You are now "${r.new_username}". ${r.username_changes_remaining} change(s) left this year.`));
        refreshTop(); setTimeout(load, 1000);
      } catch (e) { err(um, e.message || T('falha', 'failed')); }
    } }, T('Trocar nome de usuário', 'Change username')), um));
}

async function load() {
  const content = document.getElementById('content');
  const st = await status(CONTEST);
  if (!st.logged_in) {
    content.innerHTML = '<div class="notice" style="margin-top:1rem">' + T('Entre (no topo da página) para ver e editar seu perfil.', 'Log in (at the top of the page) to view and edit your profile.') + '</div>';
    return;
  }
  try {
    const p = await apiGet('/treino/profile', { contest: CONTEST, auth: true });
    render(p, st);
  } catch (e) {
    content.innerHTML = '<div class="error-box" style="margin-top:1rem">' + T('Falha ao carregar o perfil: ', 'Failed to load the profile: ') + (e.message || '') + '</div>';
  }
}

async function boot() {
  await renderAuthArea(document.getElementById('authArea'), CONTEST, load);
  load();
}
boot();
