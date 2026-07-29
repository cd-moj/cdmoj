// contest/docs/docs.js — página SÓ-LEITURA dos documentos da prova (chefe de sede .cstaff,
// staff e demais logins do contest). Lista o que a organização PUBLICOU e baixa/abre para
// imprimir na sede. Quem gera/publica é o admin ou o juiz-chefe (aba 📄 Documentos).
// O gate real é da API (`/contest/doc` devolve 404 para documento não publicado).
import { el } from '/shared/ui.js';
import { initContestShell } from '/shared/contest-shell.js';
import { makeDocsTab } from '/contest/admin/docs-tab.js';
import { T } from '/shared/i18n.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const enc = encodeURIComponent;

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">' + T('Contest não informado.', 'Contest not specified.') + '</div>'; return; }
  const { st } = await initContestShell(CONTEST);
  if (!st || !st.logged_in) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, T('🔒 Entre no contest', '🔒 Log in to the contest')),
      el('a', { class: 'btn', href: '/contest/login/?c=' + enc(CONTEST) }, T('Login do contest', 'Contest login'))));
    return;
  }
  app.innerHTML = '';
  const tab = makeDocsTab(CONTEST, { readOnly: true });
  app.append(tab.panel);
  await tab.load();
}
boot();
