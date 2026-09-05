// contest/admin/admin.js — SHELL do painel de administração do contest (.admin).
//
// Só navegação: os grupos × painéis vêm de nav.js (puro, testável); os MÓDULOS ligados do contest
// (`basic.modules`) decidem quais painéis e grupos aparecem — grupos comuns (Central, Prova,
// Pessoas, Operação) sempre, grupos de EVENTO (🏟️ Evento, 🖥️ Máquinas) só com módulo ligado,
// depois do separador. Hash `#grupo/painel`; ALIAS dos hashes antigos (link salvo não quebra);
// painel de módulo desligado cai em Central › Módulos com aviso. Cada painel é um módulo com o
// MESMO contrato `{panel, load}` — quem quiser reusar um painel fora daqui (o `chief.js` já faz
// isso com Documentos e Rodadas) só importa o módulo. Cada painel recebe `has(mod)` p/ gatear
// suas próprias seções (ex.: Staff só mostra balões com o módulo `baloes`).
//
// As páginas AVULSAS (etiquetas, jplag, fila do staff, placar, revelação, todas as submissões)
// continuam páginas próprias, linkadas da Central — não são painéis daqui.
import { el } from '/shared/ui.js';
import { initContestShell } from '/shared/contest-shell.js';
import { T } from '/shared/i18n.js';
import { resolveHash, panelVisible, EVENT_GROUPS } from './nav.js';
import { makeCentralTab } from './central-tab.js';
import { makeModulesTab } from './modules-tab.js';
import { makeSettingsTab } from './settings-tab.js';
import { makeProblemsTab } from './problems-tab.js';
import { makeReportTab } from './report-tab.js';
import { makeRoundsTab } from './rounds-tab.js';
import { makeDocsTab } from './docs-tab.js';
import { makeBalloonsTab } from './balloons-tab.js';
import { makeClassifyTab } from './classify-tab.js';
import { makeUsersTab } from './users-tab.js';
import { makeRegistrationsTab } from './registrations-tab.js';
import { makeSessionsTab } from './sessions-tab.js';
import { makeTeamsTab } from './teams-tab.js';
import { makeCohortsTab } from './cohorts-tab.js';
import { makeSitesTab } from './sites-tab.js';
import { makeMachinesTab } from './machines-tab.js';
import { makeAnomaliesTab } from './anomalies-tab.js';
import { makeMlinuxTab } from './mlinux-tab.js';
import { makeStatusTab } from './status-tab.js';
import { makeTasksTab } from './tasks.js';
import { makeJudgesTab } from './judges-tab.js';
import { makeAuditTab } from './audit-tab.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const enc = encodeURIComponent;

let MODS = new Set();                       // módulos ligados (basic.modules; atualizado por moj:modules)
const has = (m) => MODS.has(m);
const mods = () => [...MODS];
const visible = (panelId) => panelVisible(panelId, MODS);

// id do painel -> fábrica (ids são únicos no painel inteiro; ver nav.js)
const MK = {
  central: () => makeCentralTab(CONTEST, { go, has, mods, visible }),
  modulos: () => makeModulesTab(CONTEST),
  regras: () => makeSettingsTab(CONTEST, { has }),
  problemas: () => makeProblemsTab(CONTEST),
  relatorio: () => makeReportTab(CONTEST, { has }),
  contas: () => makeUsersTab(CONTEST),
  inscricoes: () => makeRegistrationsTab(CONTEST),
  sessoes: () => makeSessionsTab(CONTEST, { has }),
  situacao: () => makeStatusTab(CONTEST, { has }),
  staff: () => makeTasksTab(CONTEST, { has }),
  juizes: () => makeJudgesTab(CONTEST),
  auditoria: () => makeAuditTab(CONTEST),
  rodadas: () => makeRoundsTab(CONTEST),
  documentos: () => makeDocsTab(CONTEST),
  baloes: () => makeBalloonsTab(CONTEST),
  classificacao: () => makeClassifyTab(CONTEST),
  times: () => makeTeamsTab(CONTEST),
  coortes: () => makeCohortsTab(CONTEST),
  sedes: () => makeSitesTab(CONTEST),
  gate: () => makeMachinesTab(CONTEST),
  anomalias: () => makeAnomaliesTab(CONTEST),
  mlinux: () => makeMlinuxTab(CONTEST),
};

const built = {};           // id do painel -> {panel, load, notice?}
let wrap = null, gbar = null, snav = null;

function go(g, p) {
  location.hash = '#' + g + '/' + p;   // o hashchange chama render()
}

async function render() {
  const { groups, grp, pan, notice } = resolveHash(location.hash, MODS);
  // canonicaliza a URL (hash vazio no boot, alias antigo, painel inexistente) sem re-renderizar:
  // replaceState não dispara hashchange.
  const canon = '#' + grp.id + '/' + pan.id;
  if (location.hash !== canon) history.replaceState(null, '', location.pathname + '?c=' + enc(CONTEST) + canon);

  gbar.innerHTML = '';
  const common = groups.filter((x) => !EVENT_GROUPS.includes(x.id));
  const event = groups.filter((x) => EVENT_GROUPS.includes(x.id));
  const gbtn = (x) => el('button', { class: x.id === grp.id ? 'active' : '', onclick: () => go(x.id, x.panels[0].id) }, x.label);
  common.forEach((x) => gbar.append(gbtn(x)));
  if (event.length) { gbar.append(el('span', { class: 'groupbar-sep' })); event.forEach((x) => gbar.append(gbtn(x))); }
  gbar.append(el('span', { style: 'flex:1' }),
    el('a', { class: 'btn ghost', target: '_blank', href: '/docs/MANUAL-ADMIN.html' }, T('📖 Manual', '📖 Manual')));

  snav.innerHTML = '';
  grp.panels.forEach((x) => snav.append(el('button', { class: x.id === pan.id ? 'active' : '', onclick: () => go(grp.id, x.id) }, x.label)));

  // painéis são construídos uma vez e só escondidos (mantêm estado, filtros e timers)
  Object.entries(built).forEach(([k, inst]) => { inst.panel.hidden = (k !== pan.id); });
  if (!built[pan.id]) {
    const inst = MK[pan.id]();
    built[pan.id] = inst; wrap.append(inst.panel);
    if (inst.load) await inst.load();
  } else if (built[pan.id].load) {
    await built[pan.id].load();
  }
  if (notice && built[pan.id].notice) {
    const need = notice.modules.join(T(' ou ', ' or '));
    built[pan.id].notice(T(`O painel «${notice.panel}» pertence ao módulo «${need}», que está desligado neste contest. Ligue-o aqui para abri-lo.`,
      `The "${notice.panel}" panel belongs to the "${need}" module, which is off in this contest. Turn it on here to open it.`));
  }
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">' + T('Contest não informado.', 'Contest not provided.') + '</div>'; return; }
  const { st, basic } = await initContestShell(CONTEST);
  if (!st || !st.logged_in || !st.is_admin) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, T('🔒 Acesso restrito', '🔒 Restricted access')),
      el('a', { class: 'btn', href: '/contest/login/?c=' + enc(CONTEST) }, T('Login do contest', 'Contest login'))));
    return;
  }
  MODS = new Set((basic && basic.modules) || []);
  app.innerHTML = '';
  gbar = el('div', { class: 'groupbar' });
  snav = el('div', { class: 'subnav' });
  wrap = el('div', {});
  app.append(gbar, snav, wrap);   // o <h1> já vem no HTML da página
  window.addEventListener('hashchange', render);
  // o painel Módulos salvou: a nav muda na hora (painéis já construídos ficam, escondidos)
  window.addEventListener('moj:modules', (ev) => { MODS = new Set((ev.detail && ev.detail.enabled) || []); render(); });
  await render();
}
boot();
