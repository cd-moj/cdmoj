// shared/ui.js — helpers de DOM, formatação e área de autenticação (compartilhados).
import { t, T } from './i18n.js';
import { status, login, logout, getToken } from './auth.js';
import { apiGet } from './api.js';

export function el(tag, attrs = {}, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    // booleano = atributo booleano HTML: false OMITE (setAttribute('disabled', false)
    // deixaria o atributo PRESENTE = desabilitado!), true põe o atributo vazio.
    if (v == null || v === false) continue;
    if (k === 'class') e.className = v;
    else if (k === 'html') e.innerHTML = v;
    else if (k.startsWith('on') && typeof v === 'function') e.addEventListener(k.slice(2), v);
    else e.setAttribute(k, v === true ? '' : v);
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
  if (s.startsWith('time limit') || s.startsWith('memory')) return 'v-warn';
  if (s.startsWith('compilation') || s.startsWith('language')) return 'v-err';
  if (isPending(v)) return 'v-pending';
  return '';
}
export function isPending(v) {
  const s = (v || '').toLowerCase();
  return s.includes('not answered') || s.includes('queue') || s.includes('running');
}
// veredicto SEM o sufixo de score (",100p" / " (...)" / ". Pontos...") -> rótulo limpo p/ exibir.
export function verdictShort(v) {
  return (v || '').replace(/,.*$/, '').replace(/\s*\(.*$/, '').trim();
}
// score embutido no veredicto (o "<N>p") -> número, ou null se não houver. Fallback p/ o resumo.
export function verdictScore(v) {
  const m = /(-?\d+)p(?:\b|\.|$)/.exec(v || '');
  return m ? parseInt(m[1], 10) : null;
}
// detalhe por grupo (subtarefas): "Grupo 1: 30/30 · Grupo 2: 0/20 · Grupo 3: —/40".
// earned null = grupo não executado; max null (results legados) = mostra só o ganho.
export function groupsText(groups) {
  if (!Array.isArray(groups) || !groups.length) return '';
  return groups.map((g, i) => {
    const e = g.earned == null ? '—' : String(g.earned);
    return `${T('Grupo', 'Group')} ${i + 1}: ${g.max != null ? e + '/' + g.max : e}`;
  }).join(' · ');
}
// "resumo" amigável do julgamento (do /submission/summary): heurístico, pontos+grupos ou
// testes — renderiza o que a API der (a redação por modo é do servidor). '' se sem dados.
export function resumoText(s) {
  if (!s) return '';
  if (s.heur_score != null) return `Score ${s.heur_score}` + (s.heur_adjusted != null ? ` · ${T('ajustado', 'adjusted')} ${s.heur_adjusted}` : '');
  if (s.score_kind === 'points' || (Array.isArray(s.groups) && s.groups.length)) {
    const pts = s.score != null ? `${s.score}${s.score_max != null ? '/' + s.score_max : ''} ${T('pontos', 'points')}` : '';
    const g = groupsText(s.groups);
    return pts && g ? `${pts} · ${g}` : (pts || g);
  }
  if (s.total != null && s.total > 0) return `${T('Passou em', 'Passed')} ${s.correct != null ? s.correct : 0}/${s.total} ${T('testes', 'tests')}` + (s.score != null ? ` (${s.score}%)` : '');
  if (s.score != null) return `${s.score}%`;
  return '';
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

// dropdown mínimo: liga um <button> gatilho a um painel — abre/fecha no clique, fecha em
// clique-fora e Esc. Não há componente de menu no projeto; este é o primeiro (reusável).
// Registra os listeners de documento só enquanto aberto (não empilha em re-render).
export function attachDropdown(trigger, panel, wrap) {
  const onDoc = (e) => { if (!wrap.contains(e.target)) close(); };
  const onKey = (e) => { if (e.key === 'Escape') { close(); trigger.focus(); } };
  function close() {
    if (!panel.classList.contains('open')) return;
    panel.classList.remove('open');
    trigger.setAttribute('aria-expanded', 'false');
    document.removeEventListener('click', onDoc);
    document.removeEventListener('keydown', onKey);
  }
  function open() {
    panel.classList.add('open');
    trigger.setAttribute('aria-expanded', 'true');
    document.addEventListener('click', onDoc);
    document.addEventListener('keydown', onKey);
  }
  trigger.addEventListener('click', (e) => { e.stopPropagation(); panel.classList.contains('open') ? close() : open(); });
  return { open, close };
}

// área de autenticação no topbar: menu do usuário (avatar ▾) com perfil/admin/gestão/criar/sair,
// ou o login inline. onChange() é chamado após login/logout p/ a página recarregar seu estado.
export async function renderAuthArea(mount, contest, onChange) {
  mount.innerHTML = '';
  const st = await status(contest);
  const doLogout = async () => { await logout(contest); onChange && onChange(); };
  if (st.logged_in) {
    // fora do site principal (contexto de contest genérico): só nome + sair, sem menu
    if (contest !== 'treino') {
      mount.append(el('span', { class: 'small' }, st.name || st.login),
        el('button', { class: 'btn ghost', onclick: doLogout }, t('logout')));
      return st;
    }
    // UMA chamada de permissão decide Gestão de Problemas E Criar contest
    let canCreate = false;
    try { const perm = await apiGet('/treino/contest-create/permission', { contest: 'treino', auth: true }); canCreate = !!(perm && perm.can_create); }
    catch { /* sem permissão de criação */ }

    const wrap = el('span', { class: 'user-menu' });
    const trigger = el('button', { class: 'user-menu-btn', 'aria-haspopup': 'true', 'aria-expanded': 'false', title: st.login || '' },
      avatarEl(st.login, st.name, 26), el('span', {}, st.name || st.login), el('span', { class: 'caret' }, '▾'));
    const panel = el('div', { class: 'menu-panel', role: 'menu' });
    wrap.append(trigger, panel);
    const dd = attachDropdown(trigger, panel, wrap);
    const item = (href, label) => el('a', { class: 'menu-item', role: 'menuitem', href }, label);
    if (st.login) panel.append(item('/treino/stat/?user=' + encodeURIComponent(st.login), '📊 ' + T('Minhas estatísticas', 'My statistics')));
    if (canCreate) panel.append(item('/problemas/', '🗂 ' + T('Gestão de Problemas', 'Problem Management')));
    panel.append(item('/treino/perfil/', '⚙ ' + T('Perfil', 'Profile')));
    if (st.is_admin) panel.append(item('/treino/admin/', '🛡 ' + T('Admin', 'Admin')));
    if (canCreate) panel.append(item('/treino/criar/', '➕ ' + T('Criar contest', 'Create contest')));
    panel.append(el('div', { class: 'menu-sep' }));
    panel.append(el('button', { class: 'menu-item', role: 'menuitem', onclick: () => { dd.close(); doLogout(); } }, t('logout')));
    mount.append(wrap);
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
  const kids = [u, p, el('button', { class: 'btn', onclick: go }, t('login')), msg];
  // cadastro self-service existe só no treino (backend em handlers/treino/signup/*)
  if (contest === 'treino') {
    kids.push(el('a', {
      class: 'small', href: '/treino/cadastro/',
      title: T('Criar uma conta no Treino Livre', 'Create a Free Training account'), style: 'font-weight:700',
    }, t('create_account')));
  }
  mount.append(...kids);
  return st;
}
