// treino/perfil/perfil.js — gerenciar o próprio perfil do Treino Livre.
import { apiGet, apiPost } from '/shared/api.js';
import { status, fileToBase64 } from '/shared/auth.js';
import { el, renderAuthArea, fmtDate } from '/shared/ui.js';
import { EDITORS } from '/shared/editors.js';

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
    return el('img', { alt: 'sua foto', style: AVA,
      src: '/api/v1/treino/profile/photo?user=' + encodeURIComponent(p.login) + '&t=' + Date.now() });
  }
  return el('div', { style: AVA + ';display:grid;place-items:center;color:#fff;font-weight:800;font-size:2rem;background:' + colorFromName(p.login) },
    initialsOf(p.name, p.login));
}

function render(p) {
  const content = document.getElementById('content');
  content.innerHTML = '';

  // --- Dados: nome + universidade + editor favorito ---
  const nameI = el('input', { value: p.name || '', style: 'width:100%' });
  const univI = el('input', { value: p.university || '', placeholder: 'Ex.: Universidade de Brasília', style: 'width:100%' });
  const edSel = el('select', { style: 'width:100%' },
    el('option', { value: '' }, '— não informar —'),
    ...EDITORS.map((e) => el('option', { value: e.id }, e.label)));
  edSel.value = p.favorite_editor || '';
  const dm = msgBox();
  content.append(el('div', { class: 'section' },
    el('h2', {}, '👤 Dados'),
    el('div', { class: 'field' }, el('label', {}, 'Nome completo'), nameI),
    el('div', { class: 'field' }, el('label', {}, 'Universidade que representa / estuda'), univI),
    el('div', { class: 'field' }, el('label', {}, 'Editor / IDE favorito'), edSel,
      el('span', { class: 'small muted' }, 'Aparece no seu perfil público e entra no ranking de editores.')),
    el('button', { class: 'btn', onclick: async () => {
      dm.className = 'small'; dm.textContent = 'Salvando…';
      try {
        await apiPost('/treino/profile',
          { name: nameI.value.trim(), university: univI.value.trim(), favorite_editor: edSel.value },
          { contest: CONTEST, auth: true });
        ok(dm, '✓ Dados salvos'); refreshTop();
      } catch (e) { err(dm, e.message || 'falha ao salvar'); }
    } }, 'Salvar dados'), dm));

  // --- Senha ---
  const oldI = el('input', { type: 'password', autocomplete: 'current-password' });
  const n1 = el('input', { type: 'password', autocomplete: 'new-password' });
  const n2 = el('input', { type: 'password', autocomplete: 'new-password' });
  const pm = msgBox();
  content.append(el('div', { class: 'section' },
    el('h2', {}, '🔑 Senha'),
    el('div', { class: 'field' }, el('label', {}, 'Senha atual'), oldI),
    el('div', { class: 'field' }, el('label', {}, 'Nova senha'), n1),
    el('div', { class: 'field' }, el('label', {}, 'Confirmar nova senha'), n2),
    el('button', { class: 'btn', onclick: async () => {
      if (n1.value !== n2.value) { err(pm, 'As senhas não conferem'); return; }
      pm.className = 'small'; pm.textContent = 'Salvando…';
      try {
        await apiPost('/treino/profile/password', { old_password: oldI.value, new_password: n1.value }, { contest: CONTEST, auth: true });
        ok(pm, '✓ Senha alterada'); oldI.value = n1.value = n2.value = '';
      } catch (e) { err(pm, e.message || 'falha'); }
    } }, 'Trocar senha'), pm));

  // --- Privacidade: perfil público / privado ---
  const isPublic = p.profile_public !== false;
  const privM = msgBox();
  const privChk = el('input', { type: 'checkbox', id: 'privChk' });
  privChk.checked = isPublic;
  privChk.addEventListener('change', async () => {
    privChk.disabled = true; privM.className = 'small'; privM.textContent = 'Salvando…';
    try {
      await apiPost('/treino/profile', { profile_public: privChk.checked }, { contest: CONTEST, auth: true });
      ok(privM, privChk.checked ? '✓ Perfil público' : '✓ Perfil privado');
    } catch (e) { privChk.checked = !privChk.checked; err(privM, e.message || 'falha ao salvar'); }
    finally { privChk.disabled = false; }
  });
  content.append(el('div', { class: 'section' },
    el('h2', {}, '🔒 Privacidade'),
    el('label', { class: 'row', for: 'privChk', style: 'gap:.5rem; cursor:pointer; font-weight:600' },
      privChk, 'Perfil público'),
    el('p', { class: 'small muted', style: 'margin:.4rem 0 0' },
      'Se desmarcado, suas estatísticas e histórico ficam visíveis só para você.'),
    privM));

  // --- Foto de perfil ---
  const photoM = msgBox();
  const avatarBox = el('div', { style: 'flex:0 0 auto' }, avatarNode(p));
  const fileI = el('input', { type: 'file', accept: 'image/*' });
  fileI.addEventListener('change', async () => {
    const f = fileI.files && fileI.files[0];
    if (!f) return;
    photoM.className = 'small'; photoM.textContent = 'Enviando…';
    try {
      const image_b64 = await fileToBase64(f);
      await apiPost('/treino/profile/photo', { image_b64 }, { contest: CONTEST, auth: true });
      // recarrega o avatar com novo cachebust
      p.has_photo = true;
      avatarBox.innerHTML = ''; avatarBox.append(avatarNode(p));
      ok(photoM, '✓ Foto atualizada'); refreshTop();
    } catch (e) { err(photoM, e.message || 'falha ao enviar a foto'); }
    finally { fileI.value = ''; }
  });
  content.append(el('div', { class: 'section' },
    el('h2', {}, '🖼️ Foto de perfil'),
    el('div', { class: 'row', style: 'gap:1.2rem; align-items:center' },
      avatarBox,
      el('div', {},
        el('div', { class: 'field', style: 'margin:0' },
          el('label', {}, 'Enviar nova foto'), fileI),
        el('p', { class: 'small muted', style: 'margin:.4rem 0 0' },
          'A imagem será recortada/redimensionada para 100×100 pixels.'))),
    photoM));

  // --- Nome de usuário (handle) — limite explícito ---
  const used = p.username_changes_used || 0, limit = p.username_changes_limit || 2, rem = p.username_changes_remaining || 0;
  const canChange = rem > 0;
  const next = p.username_next_available ? fmtDate(p.username_next_available) : null;
  const uI = el('input', { placeholder: 'novo_nome_de_usuario', disabled: !canChange });
  const um = msgBox();
  const note = el('div', { class: canChange ? 'notice' : 'error-box', style: 'margin-bottom:.7rem' },
    canChange
      ? `⚠️ Você pode trocar o nome de usuário no máximo ${limit} vezes por ano. Você já usou ${used} de ${limit} — restam ${rem}. Escolha com cuidado.`
      : `🚫 Limite de ${limit} trocas por ano atingido (usou ${used}/${limit}).` + (next ? ` Próxima troca disponível em ${next}.` : ''));
  content.append(el('div', { class: 'section' },
    el('h2', {}, '🏷️ Nome de usuário (handle)'),
    el('p', { class: 'small muted' }, 'Seu login atual é ', el('b', {}, p.login),
      '. Trocar o handle atualiza todo o seu histórico do Treino Livre (submissões, estatísticas, etc.).'),
    note,
    el('div', { class: 'field' }, el('label', {}, 'Novo nome de usuário'), uI),
    el('button', { class: 'btn', disabled: !canChange, onclick: async () => {
      const nv = uI.value.trim();
      if (!nv) { err(um, 'Informe o novo nome de usuário'); return; }
      if (!confirm(`Trocar seu nome de usuário para "${nv}"?\nIsso conta como 1 das ${limit} trocas anuais e não dá para desfazer.`)) return;
      um.className = 'small'; um.textContent = 'Trocando…';
      try {
        const r = await apiPost('/treino/profile/username', { new_username: nv }, { contest: CONTEST, auth: true });
        ok(um, `✓ Agora você é "${r.new_username}". Restam ${r.username_changes_remaining} troca(s) neste ano.`);
        refreshTop(); setTimeout(load, 1000);
      } catch (e) { err(um, e.message || 'falha'); }
    } }, 'Trocar nome de usuário'), um));
}

async function load() {
  const content = document.getElementById('content');
  const st = await status(CONTEST);
  if (!st.logged_in) {
    content.innerHTML = '<div class="notice" style="margin-top:1rem">Entre (no topo da página) para ver e editar seu perfil.</div>';
    return;
  }
  try {
    const p = await apiGet('/treino/profile', { contest: CONTEST, auth: true });
    render(p);
  } catch (e) {
    content.innerHTML = '<div class="error-box" style="margin-top:1rem">Falha ao carregar o perfil: ' + (e.message || '') + '</div>';
  }
}

async function boot() {
  await renderAuthArea(document.getElementById('authArea'), CONTEST, load);
  load();
}
boot();
