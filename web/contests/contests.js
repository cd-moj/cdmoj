// contests/contests.js — arquivo completo dos contests ENCERRADOS (a home só traz os
// 20 mais recentes). Busca todos via /index/contests?all=1 e pagina/filtra no cliente.
import { apiGet } from '/shared/api.js';
import { el, renderAuthArea } from '/shared/ui.js';
import { contestCard } from '/shared/contest-card.js';
import { renderCreateContestLink } from '/shared/create-contest-link.js';

const norm = (s) => (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
let all = [], page = 0; const PER = 24;

function render() {
  const f = norm(document.getElementById('filter').value);
  const items = f ? all.filter((c) => norm((c.title || c.name || c.id || '') + ' ' + (c.id || '')).includes(f)) : all;
  document.getElementById('count').textContent = f ? `${items.length} de ${all.length}` : String(all.length);
  const pages = Math.max(1, Math.ceil(items.length / PER));
  if (page >= pages) page = 0;
  const box = document.getElementById('list'); box.innerHTML = '';
  if (!items.length) { box.innerHTML = '<div class="muted">nenhum contest encerrado encontrado.</div>'; document.getElementById('pager').innerHTML = ''; return; }
  items.slice(page * PER, page * PER + PER).forEach((c) => box.append(contestCard(c, 'closed')));
  const pg = document.getElementById('pager'); pg.innerHTML = '';
  if (pages > 1) {
    pg.append(
      el('button', { class: 'btn ghost', onclick: () => { if (page > 0) { page--; render(); window.scrollTo(0, 0); } } }, '‹ anterior'),
      el('span', { class: 'small muted' }, ` página ${page + 1} de ${pages} `),
      el('button', { class: 'btn ghost', onclick: () => { if (page < pages - 1) { page++; render(); window.scrollTo(0, 0); } } }, 'próxima ›'));
  }
}

async function boot() {
  // topbar consistente com a home (avatar/perfil/🛡 admin + criar contest)
  const am = document.getElementById('authArea');
  const refresh = () => renderAuthArea(am, 'treino', refresh).then(() => renderCreateContestLink(am));
  refresh();

  let j;
  try { j = await apiGet('/index/contests?all=1', {}); }
  catch { document.getElementById('list').innerHTML = '<div class="error-box">Não foi possível carregar os contests.</div>'; document.getElementById('count').textContent = '!'; return; }
  all = (j.closed && j.closed.items) || (Array.isArray(j.closed) ? j.closed : []);
  document.getElementById('filter').addEventListener('input', () => { page = 0; render(); });
  render();
}
boot();
