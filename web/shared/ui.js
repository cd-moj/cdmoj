// shared/ui.js — helpers de DOM, formatação e área de autenticação (compartilhados).
import { t } from './i18n.js';
import { status, login, logout, getToken } from './auth.js';

export function el(tag, attrs = {}, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v == null) continue;
    if (k === 'class') e.className = v;
    else if (k === 'html') e.innerHTML = v;
    else if (k.startsWith('on') && typeof v === 'function') e.addEventListener(k.slice(2), v);
    else e.setAttribute(k, v);
  }
  for (const kid of kids.flat()) {
    if (kid == null) continue;
    e.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
  }
  return e;
}

// classe de cor pelo veredicto (regras do design log)
export function verdictClass(v) {
  const s = (v || '').toLowerCase();
  if (s.startsWith('accepted')) return 'v-ok';
  if (s.startsWith('wrong') || s.includes('runtime')) return 'v-err';
  if (s.startsWith('time limit')) return 'v-warn';
  if (s.startsWith('compilation') || s.startsWith('language')) return 'v-err';
  if (isPending(v)) return 'v-pending';
  return '';
}
export function isPending(v) {
  const s = (v || '').toLowerCase();
  return s.includes('not answered') || s.includes('queue') || s.includes('running');
}
export function fmtDate(epoch) {
  const d = new Date(Number(epoch) * 1000);
  return isNaN(d.getTime()) ? '-' : d.toLocaleString();
}

// --- avatar do treino: foto de perfil ou círculo de iniciais (cor estável) ---
export function colorFromName(s) {
  s = String(s || ''); let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return `hsl(${h % 360} 55% 42%)`;
}
export function initialsOf(name, login) {
  const src = String(name || login || '?').replace(/\[[^\]]*\]/g, '').trim() || String(login || '?');
  const parts = src.split(/\s+/).filter(Boolean);
  return ((parts[0] || '?')[0] + (parts.length > 1 ? parts[parts.length - 1][0] : '')).toUpperCase();
}
// <span> com a foto (com fallback automático p/ iniciais; sem chamada extra de API)
// hasPhoto: se false, evita a requisição de imagem (renderiza iniciais direto);
// se omitido, tenta a foto e cai para iniciais no erro (404).
export function avatarEl(login, name, size = 26, hasPhoto) {
  const span = el('span', { class: 'avatar-mini', style: `width:${size}px;height:${size}px;font-size:${Math.round(size * 0.42)}px` });
  const showInitials = () => {
    span.innerHTML = ''; span.classList.add('ini');
    span.style.background = colorFromName(login || name);
    span.textContent = initialsOf(name, login);
  };
  if (!login || hasPhoto === false) { showInitials(); return span; }
  const img = el('img', { alt: '', src: '/api/v1/treino/profile/photo?user=' + encodeURIComponent(login) });
  img.addEventListener('error', showInitials);
  span.append(img);
  return span;
}

// área de autenticação no topbar: mostra usuário+logout, ou um botão que abre login.
// onChange() é chamado após login/logout para a página recarregar seu estado.
export async function renderAuthArea(mount, contest, onChange) {
  mount.innerHTML = '';
  const st = await status(contest);
  if (st.logged_in) {
    // no treino, o handle leva à página de estatísticas do próprio usuário
    const who = (contest === 'treino' && st.login)
      ? el('a', { class: 'user-chip', href: '/treino/stat/?user=' + encodeURIComponent(st.login), title: 'Minhas estatísticas' },
           avatarEl(st.login, st.name, 26), el('span', {}, st.name || st.login))
      : el('span', { class: 'small' }, st.name || st.login);
    const items = [who];
    if (contest === 'treino') items.push(el('a', { class: 'small', href: '/treino/perfil/', title: 'Editar perfil' }, '⚙ perfil'));
    if (contest === 'treino' && st.is_admin) items.push(el('a', { class: 'small', href: '/treino/admin/', title: 'Painel administrativo' }, '🛡 admin'));
    items.push(el('button', { class: 'btn ghost', onclick: async () => { await logout(contest); onChange && onChange(); } }, t('logout')));
    mount.append(...items);
    return st;
  }
  const u = el('input', { placeholder: t('user'), autocomplete: 'username' });
  const p = el('input', { type: 'password', placeholder: t('password'), autocomplete: 'current-password' });
  const msg = el('span', { class: 'small' });
  const go = async () => {
    msg.textContent = '';
    try { await login(contest, u.value.trim(), p.value); onChange && onChange(); }
    catch (e) { msg.textContent = ' ' + (e.message || t('wrong_login')); msg.className = 'small error-box'; }
  };
  p.addEventListener('keydown', (e) => { if (e.key === 'Enter') go(); });
  mount.append(u, p, el('button', { class: 'btn', onclick: go }, t('login')), msg);
  return st;
}
