// shared/create-contest-link.js — adiciona "➕ criar contest" no topbar quando o
// usuário do treino livre tem permissão (lista do admin OU threshold de resolvidos).
// É leve e defensivo: se não estiver logado ou não puder criar, não mostra nada.
import { apiGet } from '/shared/api.js';
import { el } from '/shared/ui.js';

export async function renderCreateContestLink(mount) {
  if (!mount) return;
  mount.querySelectorAll('.create-contest-link').forEach((n) => n.remove());
  let p;
  try { p = await apiGet('/treino/contest-create/permission', { contest: 'treino', auth: true }); }
  catch { return; }
  if (!p || !p.can_create) return;
  const link = el('a', {
    class: 'small create-contest-link', href: '/treino/criar/',
    title: 'Criar um novo contest', style: 'font-weight:700',
  }, '➕ criar contest');
  const logout = mount.querySelector('button');
  if (logout) mount.insertBefore(link, logout); else mount.append(link);
}
