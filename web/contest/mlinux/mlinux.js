// contest/mlinux/mlinux.js — página AVULSA do panorama mlinux (nutellaboot).
//
// É a MESMA UI do painel do admin (makeMlinuxTab): o servidor decide o que cada papel
// recebe — admin/chefe tudo; .cstaff/.staff só as sedes do próprio escopo (e comandos só
// nelas); competidor leva 403. Página avulsa se linka do painel e da fila do staff
// (doutrina do animeitor: sem botão de nav).
import { apiGet, apiPost } from '/shared/api.js';
import { status } from '/shared/auth.js';
import { el } from '/shared/ui.js';
import { mountChrome } from '/lib/contest-chrome.js';
import { makeMlinuxTab } from '/contest/admin/mlinux-tab.js';
import { T } from '/shared/i18n.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const G = { contest: CONTEST, auth: true };

// TRAVA DE SEDE POR IP do .sistemas (09/11/2026): os IPs presos DA SEDE dele (a API recorta pelos logins do escopo)
// e o "soltar" — o admin tem a versão completa em Operação › Máquinas. 2 cliques (sem confirm(): diálogo trava quiosque).
function siteLockCard() {
  const box = el('div', { class: 'section' });
  async function load() {
    let sl;
    try { sl = await apiGet('/contest/admin/site-lock?contest=' + encodeURIComponent(CONTEST), G); } catch { box.innerHTML = ''; return; }
    const claims = sl.claims || [];
    box.innerHTML = '';
    box.append(el('h2', {}, T('🔒 Trava de sede por IP — a sua sede', '🔒 Per-site IP lock — your site', '🔒 Bloqueo de sede por IP — tu sede')),
      el('p', { class: 'small muted' }, sl.enabled
        ? T('Cada login de competidor prende o IP da máquina a este contest. Solte um IP quando a máquina precisar sair da prova (troca de máquina, por exemplo).',
          'Each competitor login pins the machine IP to this contest. Release an IP when the machine must leave the contest (a machine swap, for example).',
          'Cada login de competidor fija el IP de la máquina a esta competencia. Suelta un IP cuando la máquina deba salir de la competencia (un cambio de máquina, por ejemplo).')
        : T('A trava está desligada neste contest.', 'The lock is off in this contest.', 'El bloqueo está apagado en esta competencia.')));
    if (!claims.length) { box.append(el('p', { class: 'muted' }, T('Nenhum IP preso na sua sede.', 'No pinned IP at your site.', 'Ningún IP fijado en tu sede.'))); return; }
    const tb = el('tbody');
    claims.forEach((c) => {
      let armed = 0;
      const b = el('button', { class: 'btn ghost danger', type: 'button' }, T('soltar', 'release', 'soltar'));
      b.addEventListener('click', async () => {
        if (!armed || Date.now() - armed > 8000) { armed = Date.now(); b.textContent = T('confirmar', 'confirm', 'confirmar'); return; }
        b.disabled = true;
        try { await apiPost('/contest/admin/site-lock?contest=' + encodeURIComponent(CONTEST), { action: 'release', ip: c.ip }, G); await load(); }
        catch (e) { b.disabled = false; armed = 0; b.textContent = e.message || T('falha', 'failed', 'fallido'); }
      });
      tb.append(el('tr', {}, el('td', {}, el('code', {}, c.ip)), el('td', { class: 'n' }, String(c.logins)),
        el('td', { class: 'n' }, String(c.blocked)), el('td', {}, b)));
    });
    box.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' }, el('thead', {}, el('tr', {},
      el('th', {}, 'IP'), el('th', { class: 'n' }, T('Logins', 'Logins', 'Logins')), el('th', { class: 'n' }, T('Bloqueios', 'Blocks', 'Bloqueos')), el('th', {}, ''))), tb)));
  }
  load();
  return box;
}

async function boot() {
  if (!CONTEST) {
    app.innerHTML = '<div class="error-box">' + T('Contest não informado.', 'Contest not specified.', 'Competencia no especificada.') + '</div>';
    return;
  }
  let basic = null;
  try { basic = await apiGet('/contest/basic?contest=' + encodeURIComponent(CONTEST), {}); } catch { /* segue */ }
  try { await mountChrome(CONTEST, basic); } catch { /* nav opcional */ }
  app.innerHTML = '';
  try {
    const tab = makeMlinuxTab(CONTEST);
    app.append(tab.panel);
    const st = await status(CONTEST).catch(() => null);
    if (st && st.role === 'sistemas') app.append(siteLockCard());
    await tab.load();
  } catch (e) {
    app.append(el('div', { class: 'section' }, el('h2', {}, T('🔒 Restrito', '🔒 Restricted', '🔒 Restringido')),
      el('p', { class: 'muted' },
        T('Visível à organização e ao staff do contest. (', 'Visible to the contest organization and staff. (', 'Visible para la organización y el staff de la competencia. (')
        + (e.message || T('erro', 'error', 'error')) + ')')));
  }
}
boot();
