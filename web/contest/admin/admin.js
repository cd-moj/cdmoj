// contest/admin/admin.js — SHELL do painel de administração do contest (.admin).
//
// Só navegação: 4 GRUPOS (Central, Prova, Pessoas, Operação) × painéis, hash `#grupo/painel`,
// ALIAS dos hashes antigos (link salvo não quebra) e a guarda de admin. Cada painel é um módulo
// com o MESMO contrato `{panel, load}` — quem quiser reusar um painel fora daqui (o `chief.js`
// já faz isso com Documentos e Rodadas) só importa o módulo.
//
// As páginas AVULSAS (etiquetas, jplag, fila do staff, placar, revelação, todas as submissões)
// continuam páginas próprias, linkadas da Central — não são painéis daqui.
import { el } from '/shared/ui.js';
import { initContestShell } from '/shared/contest-shell.js';
import { makeCentralTab } from './central-tab.js';
import { makeSettingsTab } from './settings-tab.js';
import { makeProblemsTab } from './problems-tab.js';
import { makeRoundsTab } from './rounds-tab.js';
import { makeDocsTab } from './docs-tab.js';
import { makeBalloonsTab } from './balloons-tab.js';
import { makeUsersTab } from './users-tab.js';
import { makeTeamsTab } from './teams-tab.js';
import { makeCohortsTab } from './cohorts-tab.js';
import { makeRegistrationsTab } from './registrations-tab.js';
import { makeSitesTab } from './sites-tab.js';
import { makeMachinesTab } from './machines-tab.js';
import { makeSessionsTab } from './sessions-tab.js';
import { makeStatusTab } from './status-tab.js';
import { makeTasksTab } from './tasks.js';
import { makeJudgesTab } from './judges-tab.js';
import { makeAuditTab } from './audit-tab.js';
import { makeMlinuxTab } from './mlinux-tab.js';
import { T } from '/shared/i18n.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const enc = encodeURIComponent;

// Fábrica preguiçosa: T() no topo do módulo rodaria ANTES de initContestShell aplicar o LOCALE
// do contest (o rótulo sairia no idioma do browser). Ver shared/i18n.js.
const GROUPS = () => [
  { id: 'central', label: T('🏁 Central', '🏁 Home'), panels: [
    { id: 'central', label: T('Central', 'Home'), make: () => makeCentralTab(CONTEST, { go }) },
    { id: 'regras', label: T('Regras', 'Rules'), make: () => makeSettingsTab(CONTEST) },
  ] },
  { id: 'prova', label: T('🧩 Prova', '🧩 Contest'), panels: [
    { id: 'problemas', label: T('Problemas', 'Problems'), make: () => makeProblemsTab(CONTEST) },
    { id: 'rodadas', label: T('Rodadas', 'Rounds'), make: () => makeRoundsTab(CONTEST) },
    { id: 'documentos', label: T('Documentos', 'Documents'), make: () => makeDocsTab(CONTEST) },
    { id: 'baloes', label: T('Balões', 'Balloons'), make: () => makeBalloonsTab(CONTEST) },
  ] },
  { id: 'pessoas', label: T('👥 Pessoas', '👥 People'), panels: [
    { id: 'contas', label: T('Contas', 'Accounts'), make: () => makeUsersTab(CONTEST) },
    { id: 'inscricoes', label: T('Inscrições', 'Registrations'), make: () => makeRegistrationsTab(CONTEST) },
    { id: 'times', label: T('Times', 'Teams'), make: () => makeTeamsTab(CONTEST) },
    { id: 'coortes', label: T('Coortes', 'Cohorts'), make: () => makeCohortsTab(CONTEST) },
    { id: 'sedes', label: T('Sedes & escolas', 'Sites & schools'), make: () => makeSitesTab(CONTEST) },
    { id: 'maquinas', label: T('Máquinas & gate', 'Machines & gate'), make: () => makeMachinesTab(CONTEST) },
    { id: 'sessoes', label: T('Sessões', 'Sessions'), make: () => makeSessionsTab(CONTEST) },
  ] },
  { id: 'operacao', label: T('🎛️ Operação', '🎛️ Operations'), panels: [
    { id: 'situacao', label: T('Situação', 'Status'), make: () => makeStatusTab(CONTEST) },
    { id: 'staff', label: T('Staff', 'Staff'), make: () => makeTasksTab(CONTEST) },
    { id: 'juizes', label: T('Juízes', 'Judges'), make: () => makeJudgesTab(CONTEST) },
    { id: 'mlinux', label: T('mlinux', 'mlinux'), make: () => makeMlinuxTab(CONTEST) },
    { id: 'auditoria', label: T('Auditoria', 'Audit'), make: () => makeAuditTab(CONTEST) },
  ] },
];

// hash antigo (13 abas planas) -> novo. Link salvo/atalho de manual não pode quebrar.
const ALIAS = {
  dash: 'operacao/situacao', preflight: 'central/central', settings: 'central/regras',
  problems: 'prova/problemas', teams: 'pessoas/times', cohorts: 'pessoas/coortes',
  appearance: 'pessoas/sedes', users: 'pessoas/contas', log: 'pessoas/sessoes',
  backups: 'operacao/auditoria', rounds: 'prova/rodadas', machines: 'pessoas/maquinas',
  docs: 'prova/documentos', tasks: 'operacao/staff', staff: 'operacao/staff',
  verdict: 'operacao/juizes', audit: 'operacao/auditoria', registrations: 'pessoas/inscricoes',
};

const built = {};           // 'grupo/painel' -> {panel, load}
let wrap = null, gbar = null, snav = null;

function go(g, p) {
  location.hash = '#' + g + '/' + p;   // o hashchange chama render()
}

function resolve() {
  let h = decodeURIComponent((location.hash || '').replace(/^#/, ''));
  if (ALIAS[h]) h = ALIAS[h];
  const groups = GROUPS();
  const [hg, hp] = h.split('/');
  const grp = groups.find((x) => x.id === hg) || groups[0];
  const pan = grp.panels.find((x) => x.id === hp) || grp.panels[0];
  return { groups, grp, pan };
}

async function render() {
  const { groups, grp, pan } = resolve();
  const key = grp.id + '/' + pan.id;
  // canonicaliza a URL (hash vazio no boot, alias antigo, painel inexistente) sem re-renderizar:
  // replaceState não dispara hashchange.
  const canon = '#' + key;
  if (location.hash !== canon) history.replaceState(null, '', location.pathname + '?c=' + enc(CONTEST) + canon);

  gbar.innerHTML = '';
  groups.forEach((x) => gbar.append(el('button', {
    class: x.id === grp.id ? 'active' : '',
    onclick: () => go(x.id, x.panels[0].id),
  }, x.label)));
  gbar.append(el('span', { style: 'flex:1' }),
    el('a', { class: 'btn ghost', target: '_blank', href: '/docs/MANUAL-ADMIN.html' },
      T('📖 Manual', '📖 Manual')));

  snav.innerHTML = '';
  grp.panels.forEach((x) => snav.append(el('button', {
    class: x.id === pan.id ? 'active' : '',
    onclick: () => go(grp.id, x.id),
  }, x.label)));

  // painéis são construídos uma vez e só escondidos (mantêm estado, filtros e timers)
  Object.entries(built).forEach(([k, inst]) => { inst.panel.hidden = (k !== key); });
  if (!built[key]) {
    const inst = pan.make();
    built[key] = inst; wrap.append(inst.panel);
    if (inst.load) await inst.load();
  } else if (built[key].load) {
    await built[key].load();
  }
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">' + T('Contest não informado.', 'Contest not provided.') + '</div>'; return; }
  const { st } = await initContestShell(CONTEST);
  if (!st || !st.logged_in || !st.is_admin) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, T('🔒 Acesso restrito', '🔒 Restricted access')),
      el('a', { class: 'btn', href: '/contest/login/?c=' + enc(CONTEST) }, T('Login do contest', 'Contest login'))));
    return;
  }
  app.innerHTML = '';
  gbar = el('div', { class: 'groupbar' });
  snav = el('div', { class: 'subnav' });
  wrap = el('div', {});
  app.append(gbar, snav, wrap);   // o <h1> já vem no HTML da página
  window.addEventListener('hashchange', render);
  await render();
}
boot();
