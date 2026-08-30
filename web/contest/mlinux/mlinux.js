// contest/mlinux/mlinux.js — página AVULSA do panorama mlinux (nutellaboot).
//
// É a MESMA UI do painel do admin (makeMlinuxTab): o servidor decide o que cada papel
// recebe — admin/chefe tudo; .cstaff/.staff só as sedes do próprio escopo (e comandos só
// nelas); competidor leva 403. Página avulsa se linka do painel e da fila do staff
// (doutrina do animeitor: sem botão de nav).
import { apiGet } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { mountChrome } from '/lib/contest-chrome.js';
import { makeMlinuxTab } from '/contest/admin/mlinux-tab.js';
import { T } from '/shared/i18n.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');

async function boot() {
  if (!CONTEST) {
    app.innerHTML = '<div class="error-box">' + T('Contest não informado.', 'Contest not specified.') + '</div>';
    return;
  }
  let basic = null;
  try { basic = await apiGet('/contest/basic?contest=' + encodeURIComponent(CONTEST), {}); } catch { /* segue */ }
  try { await mountChrome(CONTEST, basic); } catch { /* nav opcional */ }
  app.innerHTML = '';
  try {
    const tab = makeMlinuxTab(CONTEST);
    app.append(tab.panel);
    await tab.load();
  } catch (e) {
    app.append(el('div', { class: 'section' }, el('h2', {}, T('🔒 Restrito', '🔒 Restricted')),
      el('p', { class: 'muted' },
        T('Visível à organização e ao staff do contest. (', 'Visible to the contest organization and staff. (')
        + (e.message || T('erro', 'error')) + ')')));
  }
}
boot();
