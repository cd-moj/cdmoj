// noticias/noticias.js — lista de notícias/posts e o detalhe (texto completo em
// markdown, renderizado pelo servidor). Notícia LOCAL (sem url) abre aqui mesmo
// (/noticias/?id=<key>); notícia com url externa aponta para fora.
import { apiGet } from '/shared/api.js';
import { T } from '/shared/i18n.js';
import { el, fmtDate } from '/shared/ui.js';

const app = document.getElementById('app');
const id = new URLSearchParams(location.search).get('id');

function b64ToText(b64) {
  try { return new TextDecoder().decode(Uint8Array.from(atob(b64 || ''), (c) => c.charCodeAt(0))); }
  catch { return ''; }
}

function newsCard(n) {
  const ext = !n.is_local && n.url;
  const href = ext ? n.url : ('/noticias/?id=' + encodeURIComponent(n.key));
  const attrs = { class: 'news-card', href };
  if (ext) { attrs.target = '_blank'; attrs.rel = 'noopener'; }
  return el('a', attrs,
    el('div', { class: 'small muted' }, fmtDate(n.date)),
    el('div', { class: 'news-card-title' }, n.title || T('(sem título)', '(untitled)')),
    el('div', { class: 'news-card-sum muted' }, n.summary || ''),
    el('div', { class: 'news-card-more' }, ext ? T('abrir ↗', 'open ↗') : T('ler mais →', 'read more →')));
}

async function renderList() {
  document.title = T('Notícias — MOJ', 'News — MOJ');
  document.getElementById('page-title').textContent = T('📰 Notícias', '📰 News');
  let j;
  try { j = await apiGet('/index/news', {}); }
  catch { app.innerHTML = T('<div class="error-box">Não foi possível carregar as notícias.</div>', '<div class="error-box">Could not load the news.</div>'); return; }
  const news = j.news || [];
  app.innerHTML = '';
  if (!news.length) { app.innerHTML = T('<div class="muted">Nenhuma notícia ainda.</div>', '<div class="muted">No news yet.</div>'); return; }
  const grid = el('div', { class: 'news-grid' });
  news.forEach((n) => grid.append(newsCard(n)));
  app.append(grid);
}

async function renderDetail(key) {
  let j;
  try { j = await apiGet('/index/news?id=' + encodeURIComponent(key), {}); }
  catch { app.innerHTML = T('<div class="error-box">Notícia não encontrada. <a href="/noticias/">← voltar</a></div>', '<div class="error-box">News item not found. <a href="/noticias/">← back</a></div>'); return; }
  const n = j.news || {};
  document.title = (n.title || T('Notícia', 'News')) + ' — MOJ';
  document.getElementById('page-title').textContent = n.title || T('Notícia', 'News');
  app.innerHTML = '';
  app.append(
    el('a', { class: 'small', href: '/noticias/', style: 'display:inline-block; margin-bottom:.5rem' }, T('← todas as notícias', '← all news')),
    el('div', { class: 'small muted', style: 'margin-bottom:1rem' }, fmtDate(n.date)));
  const html = b64ToText(n.body_html_b64);
  if (html.trim()) { const art = el('article', { class: 'news-body' }); art.innerHTML = html; app.append(art); }
  else app.append(el('p', { class: 'muted' }, n.summary || T('Sem conteúdo.', 'No content.')));
  if (n.url) app.append(el('p', { style: 'margin-top:1.2rem' },
    el('a', { href: n.url, target: '_blank', rel: 'noopener' }, T('Fonte original ↗', 'Original source ↗'))));
}

if (id) renderDetail(id); else renderList();
