// contest/rounds/rounds.js — rodadas do contest e VISUALIZADOR do relatório arquivado.
//
// O relatório de uma rodada arquivada é um SITE (index/runs/statements/clarifications/…) que o
// report-gen gera autocontido, e a rota que o serve (/contest/round) é autenticada por Bearer.
// Então um <a href> cru daria 401 e os links internos apontariam para fora da API. Este
// visualizador busca cada página COM o token, joga num iframe srcdoc (o CSS do relatório fica
// isolado do app) e intercepta os links de dentro para navegar pela mesma rota — o gate continua
// inteiro no servidor e o token nunca vai para a URL.
import { apiGet, getToken } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { initContestShell } from '/shared/contest-shell.js';
import { T } from '/shared/i18n.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const enc = encodeURIComponent;
const fmt = (e) => (+e ? new Date(+e * 1000).toLocaleString() : '—');
// função, não const de módulo: T() no topo congela o idioma ANTES do setLang(LOCALE)
const KIND = (k) => ({ warmup: T('aquecimento', 'warm-up'), official: T('prova oficial', 'official contest'), extra: T('extra', 'extra') }[k] || '');
let ROUNDS = [];

const authHdr = () => ({ Authorization: 'Bearer ' + (getToken(CONTEST) || '') });
const fileUrl = (round, file) =>
  '/api/v1/contest/round?contest=' + enc(CONTEST) + '&round=' + enc(round) + '&file=' + enc(file);

// resolve "../index.html" relativo a "statements/A.html" -> "index.html"
function resolveRel(base, href) {
  const parts = base.split('/'); parts.pop();
  href.split('/').forEach((p) => {
    if (p === '.' || p === '') return;
    if (p === '..') parts.pop(); else parts.push(p);
  });
  return parts.join('/');
}

async function openViewer(round, file) {
  const box = el('div', { class: 'section' });
  const crumb = el('span', { class: 'small muted' });
  const frame = el('iframe', { id: 'viewer', srcdoc: '' });
  const bar = el('div', { class: 'vbar' },
    el('button', { class: 'btn ghost', onclick: () => { location.hash = ''; render(); } }, T('← rodadas', '← rounds')),
    el('button', { class: 'btn ghost', onclick: () => show('index.html') }, T('placar', 'scoreboard')),
    el('button', { class: 'btn ghost', onclick: () => show('runs.html') }, T('submissões', 'submissions')),
    el('button', { class: 'btn ghost', onclick: () => show('statistics.html') }, T('estatísticas', 'statistics')),
    el('button', { class: 'btn ghost', onclick: () => show('clarifications.html') }, 'clarifications'),
    crumb);
  const err = el('div', { class: 'small' });
  box.append(el('h2', {}, (ROUNDS.find((r) => r.slug === round) || {}).name || round), bar, err, frame);
  app.innerHTML = ''; app.append(box);

  async function show(f) {
    err.className = 'small'; err.textContent = '';
    crumb.textContent = f;
    location.hash = enc(round) + '/' + f;
    let resp;
    try { resp = await fetch(fileUrl(round, f), { headers: authHdr() }); }
    catch { err.className = 'small error-box'; err.textContent = T('falha de rede', 'network error'); return; }
    if (!resp.ok) {
      err.className = 'small error-box';
      err.textContent = resp.status === 404
        ? T('esta página não existe no relatório desta rodada (ou a rodada não está publicada).',
            'this page does not exist in this round report (or the round is not published).')
        : T('falha ao abrir (HTTP ', 'failed to open (HTTP ') + resp.status + ')';
      return;
    }
    if (!/\.html?$/.test(f)) {   // PDF/imagem: abre em aba nova pelo blob (sem token na URL)
      const u = URL.createObjectURL(await resp.blob()); window.open(u, '_blank'); return;
    }
    frame.srcdoc = await resp.text();
    frame.onload = () => {
      const d = frame.contentDocument; if (!d) return;
      d.querySelectorAll('a[href]').forEach((a) => {
        const href = a.getAttribute('href') || '';
        if (/^(https?:|mailto:|#)/.test(href)) { a.target = '_blank'; return; }
        a.addEventListener('click', (ev) => { ev.preventDefault(); show(resolveRel(f, href)); });
      });
    };
  }
  await show(file || 'index.html');
}

function render() {
  const h = decodeURIComponent((location.hash || '').replace(/^#/, ''));
  if (h.includes('/')) { const i = h.indexOf('/'); openViewer(h.slice(0, i), h.slice(i + 1)); return; }

  app.innerHTML = '';
  const arch = ROUNDS.filter((r) => r.state === 'archived');
  const live = ROUNDS.find((r) => r.state === 'active');
  const box = el('div', { class: 'section' });
  if (live) box.append(el('div', { class: 'subcard', style: 'margin:.3rem 0' },
    el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap' },
      el('b', {}, live.name || live.slug), el('span', { class: 'pill ok' }, T('no ar', 'live')),
      el('span', { class: 'small muted' }, KIND(live.kind)),
      el('span', { class: 'small muted' }, fmt(live.start) + ' → ' + fmt(live.end)))));
  if (!arch.length) {
    box.append(el('p', { class: 'small muted', style: 'margin-top:.6rem' },
      T('Nenhuma rodada encerrada ainda.', 'No finished round yet.')));
  } else {
    box.append(el('h3', { style: 'margin:.8rem 0 .3rem' }, T('Rodadas encerradas', 'Finished rounds')));
    arch.forEach((r) => {
      const row = el('div', { class: 'subcard', style: 'margin:.3rem 0' },
        el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap' },
          el('b', {}, r.name || r.slug),
          el('span', { class: 'small muted' }, KIND(r.kind)),
          el('span', { class: 'small muted' }, fmt(r.start) + ' → ' + fmt(r.end)),
          r.stats ? el('span', { class: 'small muted' },
            T(`${r.stats.submissions} submissões · ${r.stats.users} contas`,
              `${r.stats.submissions} submissions · ${r.stats.users} accounts`)) : null,
          r.published ? el('span', { class: 'pill ok' }, T('pública', 'public')) : null));
      if (r.has_report) {
        row.append(el('div', { class: 'row', style: 'gap:.5rem;margin-top:.3rem' },
          el('button', { class: 'btn', onclick: () => openViewer(r.slug, 'index.html') }, T('📊 abrir placar', '📊 open scoreboard')),
          el('button', { class: 'btn ghost', onclick: () => openViewer(r.slug, 'runs.html') }, T('submissões', 'submissions'))));
      } else {
        row.append(el('div', { class: 'small muted' }, T('sem relatório gerado', 'no report generated')));
      }
      box.append(row);
    });
  }
  app.append(box);
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">' + T('Contest não informado.', 'Contest not specified.') + '</div>'; return; }
  const { st } = await initContestShell(CONTEST);
  if (!st || !st.logged_in) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, T('🔒 Entre no contest', '🔒 Log in to the contest')),
      el('a', { class: 'btn', href: '/contest/login/?c=' + enc(CONTEST) }, T('Login do contest', 'Contest login'))));
    return;
  }
  try {
    const j = await apiGet('/contest/rounds?contest=' + enc(CONTEST), { contest: CONTEST, auth: true });
    ROUNDS = j.rounds || [];
  } catch (e) {
    app.innerHTML = ''; app.append(el('div', { class: 'error-box' }, e.message || T('falha ao carregar', 'failed to load')));
    return;
  }
  window.addEventListener('hashchange', render);
  render();
}
boot();
