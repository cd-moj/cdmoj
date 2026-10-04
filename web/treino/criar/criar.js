// treino/criar/criar.js — WIZARD multi-etapa de criação de contest (shell).
// Responsabilidades: gate por permissão, estado único `draft`, navegação entre passos,
// buildSpec (draft -> spec da API), submissão e tela de resultado. Os passos vivem em
// ./steps/*.js e RE-MONTAM lendo do draft (ir-e-voltar não perde nada). Editores pesados
// (opções/visual) são cacheados em ctx.editors e sobrevivem à navegação; aplicar
// template/duplicar reseta o cache (ctx.resetEditors) p/ recriá-los do draft novo.
import { apiGet, apiPost, getToken } from '/shared/api.js';
import { contestLoginHref } from '/shared/contest-guard.js';
import { el, renderAuthArea } from '/shared/ui.js';
import { T } from '/shared/i18n.js';
import { downloadCsv } from '/shared/users-batch.js';
import { makeStepInicio } from './steps/inicio.js';
import { makeStepDados } from './steps/dados.js';
import { makeStepProblemas } from './steps/problemas.js';
import { makeStepUsuarios } from './steps/usuarios.js';
import { makeStepAdmin } from './steps/admin.js';
import { makeStepOpcoes } from './steps/opcoes.js';
import { makeStepVisual } from './steps/visual.js';
import { makeStepModulos } from './steps/modulos.js';
import { makeStepRevisao } from './steps/revisao.js';

const app = document.getElementById('app');
const authMount = document.getElementById('authArea');
const refreshAuth = () => renderAuthArea(authMount, 'treino', refreshAuth);

export const MODE_LABEL = {
  icpc: T('ICPC (tempo + penalidade)', 'ICPC (time + penalty)', 'ICPC (tiempo + penalización)'), obi: T('OBI (pontos parciais)', 'OBI (partial points)', 'OBI (puntos parciales)'),
  treino: T('Treino (lista, sem penalidade)', 'Training (list, no penalty)', 'Entrenamiento (lista, sin penalización)'), heuristic: T('Heurístico / custom', 'Heuristic / custom', 'Heurístico / personalizado'), outro: T('Outro (custom)', 'Other (custom)', 'Otro (personalizado)'),
};
const nowEpoch = () => Math.floor(Date.now() / 1000);
const nextFullHour = () => { const e = nowEpoch(); return e - (e % 3600) + 3600; };
const b64utf8 = (s) => btoa(unescape(encodeURIComponent(s)));

const STEPS = [
  { id: 'inicio', label: T('0 · Começar', '0 · Start', '0 · Empezar'), make: makeStepInicio },
  { id: 'dados', label: T('1 · Dados', '1 · Details', '1 · Datos'), make: makeStepDados },
  { id: 'problemas', label: T('2 · Problemas', '2 · Problems', '2 · Problemas'), make: makeStepProblemas },
  { id: 'usuarios', label: T('3 · Usuários', '3 · Users', '3 · Usuarios'), make: makeStepUsuarios },
  { id: 'admin', label: T('4 · Admin', '4 · Admin', '4 · Admin'), make: makeStepAdmin },
  { id: 'opcoes', label: T('5 · Opções', '5 · Options', '5 · Opciones'), make: makeStepOpcoes },
  { id: 'visual', label: T('6 · Visual', '6 · Appearance', '6 · Apariencia'), make: makeStepVisual },
  { id: 'modulos', label: T('7 · Módulos', '7 · Modules', '7 · Módulos'), make: makeStepModulos },
  { id: 'revisao', label: T('8 · Revisão', '8 · Review', '8 · Revisión'), make: makeStepRevisao },
];

function newDraft(perm) {
  const me = perm.login || '';
  return {
    origem: T('em branco', 'blank', 'en blanco'),
    name: '', id: '', mode: 'icpc',
    start: nowEpoch(), end: nowEpoch() + 3 * 3600,
    // problems: {kind:'bank'|'id', bank_id?|source+problem_id, name ('' = automático), _letter?, _stmt? (texto),
    //            _stmt_b64?/_stmt_pdf_b64? (herdados de export/template), languages?, _private?, _hasStmt?,
    //            _title? (o título PT), _titles? ({pt,en,es} quando há tradução: as opções de nome)}
    problems: [],
    userMode: 'own', users: [], usersFrom: 'treino', sharedAck: false,
    admin: { login: me ? (me.endsWith('.admin') ? me : me + '.admin') : '', password: '', fullname: perm.name || '' },
    // opts alimenta o settings-editor (shape do GET /contest/admin/settings + priority do create)
    // sem `priority`: o assistente EXIGE a escolha (TCP 2026 — a prova nasceu lista-publica sem ninguém escolher)
    opts: { locale: 'pt', login_enabled: true },
    visual: { colors: {}, regions: [], teams_meta: [] },
    // módulos ligados (ids do catálogo) + seções cruas herdadas de template/export (ua_gate,
    // cohorts, rounds…): o wizard não tem editor p/ elas, mas não pode PERDÊ-LAS no create
    modules: [], moduleSections: {},
  };
}

// ---------- telas terminais ----------
function showDenied(p) {
  app.innerHTML = '';
  app.append(el('div', { class: 'section' },
    el('h2', {}, T('🔒 Sem permissão para criar contests', '🔒 No permission to create contests', '🔒 Sin permiso para crear competencias')),
    el('p', { class: 'muted' }, T('Motivo: ', 'Reason: ', 'Motivo: ') + ((p && p.reason) || T('não autenticado', 'not authenticated', 'no autenticado')) + '.'),
    p ? el('p', { class: 'small muted' },
      T('Você resolveu ', 'You solved ', 'Resolviste ') + (p.solved_count || 0) + T(' problemas', ' problems', ' problemas') +
      (p.threshold > 0 ? (T(' — o limite automático para liberar é ', ' — the automatic threshold to unlock is ', ' — el umbral automático para desbloquear es ') + p.threshold) : '') +
      T('. Um administrador pode liberar seu acesso na lista de criadores.', '. An administrator can grant your access in the creators list.', '. Un administrador puede habilitar tu acceso en la lista de creadores.'))
      : el('p', {}, T('Faça login no Treino Livre primeiro.', 'Log in to Free Training first.', 'Inicia sesión en Entrenamiento libre primero.')),
    el('a', { class: 'btn ghost', href: '/treino/' }, T('← Voltar ao treino', '← Back to training', '← Volver al entrenamiento'))));
}


function showResult(res) {
  app.innerHTML = '';
  const card = el('div', { class: 'result-card' },
    el('h2', { style: 'margin:.1rem 0 .6rem' }, T('✅ Contest criado e no ar!', '✅ Contest created and live!', '✅ ¡Competencia creada y en línea!')),
    el('p', {}, T('O contest ', 'The contest ', 'La competencia '), el('b', {}, res.contest_id), ' (', String(res.problems), T(' problemas) foi publicado.', ' problems) was published.', ' problemas) fue publicada.')),
    el('div', { class: 'warn-box', style: 'margin:.6rem 0' },
      T('⚠ Guarde as credenciais abaixo — as senhas só são exibidas agora.', '⚠ Save the credentials below — passwords are only shown now.', '⚠ Guarda las credenciales de abajo — las contraseñas solo se muestran ahora.')),
    el('p', {}, T('Admin do contest: ', 'Contest admin: ', 'Admin de la competencia: '), el('span', { class: 'cred' }, res.admin_login),
      res.admin_reused
        ? el('span', { class: 'small muted' }, T(' · conta existente reutilizada — use sua senha atual do Treino Livre.', ' · existing account reused — use your current Free Training password.', ' · cuenta existente reutilizada — usa tu contraseña actual de Entrenamiento libre.'))
        : [T(' · senha: ', ' · password: ', ' · contraseña: '), el('span', { class: 'cred' }, res.admin_password)]));
  if (res._secret) card.append(el('div', { class: 'warn-box', style: 'margin:.4rem 0' },
    T('🕵️ SUPER SECRETO: o contest NÃO aparece na home/arquivo/status e o placar exige login — distribua o link ', '🕵️ SUPER SECRET: the contest does NOT appear on home/archive/status and the scoreboard requires login — share the link ', '🕵️ SUPER SECRETO: la competencia NO aparece en la portada/archivo/estado y el marcador exige inicio de sesión — comparte el enlace '), el('b', {}, res.url), T(' aos participantes.', ' with participants.', ' con los participantes.')));
  card.append(el('p', { class: 'small muted' }, T('É com essa conta que se entra no PAINEL do contest (o seu login comum entra como competidor).',
    'That is the account that opens the contest ADMIN panel (your ordinary login enters as a competitor).',
    'Con esta cuenta se entra al PANEL de la competencia (tu usuario común entra como competidor).')));
  if (res.users_from) card.append(el('div', { class: 'notice small', style: 'margin:.4rem 0' }, T('Usuários: compartilhados do "', 'Users: shared from "', 'Usuarios: compartidos de "') + res.users_from + T('" (login com a conta do Treino Livre). Para uma prova, converta em contas próprias em Pessoas › Contas — senhas novas, sem volta.', '" (log in with the Free Training account). For an exam, convert them into own accounts in People › Accounts — new passwords, no way back.', '" (inicia sesión con la cuenta de Entrenamiento libre). Para un examen, conviértelas en cuentas propias en Personas › Cuentas — contraseñas nuevas, sin vuelta atrás.')));
  if (res.users && res.users.length > 1) {
    card.append(el('p', {}, res.users.length + T(' contas criadas. ', ' accounts created. ', ' cuentas creadas. '),
      el('button', { class: 'btn ghost', onclick: () => downloadCsv(res.contest_id + '-credenciais.csv', res.users) }, T('⬇ baixar credenciais (CSV)', '⬇ download credentials (CSV)', '⬇ descargar credenciales (CSV)'))));
  }
  card.append(el('div', { class: 'row', style: 'margin-top:.7rem' },
    el('a', { class: 'btn', href: res.url }, T('Abrir contest →', 'Open contest →', 'Abrir competencia →')),
    el('a', { class: 'btn ghost', href: contestLoginHref(res.contest_id, '/contest/admin/?c=' + encodeURIComponent(res.contest_id)) }, T('⚙️ Admin do contest', '⚙️ Contest admin', '⚙️ Admin de la competencia')),
    el('a', { class: 'btn ghost', href: res.scoreboard_url }, T('Placar', 'Scoreboard', 'Marcador')),
    el('a', { class: 'btn ghost', href: '/treino/criar/' }, T('Criar outro', 'Create another', 'Crear otra'))));
  app.append(card);
}

// ---------- wizard ----------
async function boot() {
  let perm;
  try { perm = await apiGet('/treino/contest-create/permission', { contest: 'treino', auth: true }); }
  catch { showDenied(null); return; }
  if (!perm || !perm.can_create) { showDenied(perm); return; }

  const ctx = {
    perm,
    draft: newDraft(perm),
    editors: {},                       // instâncias cacheadas (settings/colors/regions/teams)
    resetEditors() { this.editors = {}; },
    goto: null,                        // preenchido abaixo
    nowEpoch, nextFullHour, b64utf8, downloadCsv, showResult,
    api: {
      get: (p) => apiGet(p, { contest: 'treino', auth: true }),
      post: (p, body) => apiPost(p, body, { contest: 'treino', auth: true }),
      token: () => getToken('treino'),
    },
    // adaptador do painel de busca+sorteio (rotas do wizard)
    bankApi: {
      meta: async (q) => {
        const qs = '?' + new URLSearchParams(q || {}).toString();
        // com o opt-in dos privados a falha (índice indisponível, 503) sobe p/ o painel avisar;
        // sem ele, lista vazia basta
        const orEmpty = (k) => (e) => { if (q && q.include_private) throw e; return { [k]: [] }; };
        const [t, c] = await Promise.all([
          apiGet('/treino/contest-create/tags' + qs, { contest: 'treino', auth: true }).catch(orEmpty('tags')),
          apiGet('/treino/contest-create/collections' + qs, { contest: 'treino', auth: true }).catch(orEmpty('collections')),
        ]);
        return { tags: t.tags || [], collections: c.collections || [] };
      },
      draw: (p) => apiGet('/treino/contest-create/draw?' + new URLSearchParams(p).toString(), { contest: 'treino', auth: true }),
      search: (q) => apiGet('/treino/contest-create/problems?limit=30&q=' + encodeURIComponent(q), { contest: 'treino', auth: true }),
    },
    genPasswords: async (n) => {
      try { const r = await apiGet('/treino/contest-create/genpass?n=' + n, { contest: 'treino', auth: true }); return r.passwords || []; }
      catch { return []; }
    },
    buildSpec, applyTemplate, applyExport, submit,
    // idioma da prova (passo 5) — decide o nome AUTOMÁTICO dos problemas (passo 2 e Revisão)
    contestLocale: () => (optsValue() || {}).locale || 'pt',
  };

  function optsValue() { return ctx.editors.settings ? ctx.editors.settings.getValue() : ctx.draft.opts; }

  function buildSpec(allowEmpty) {
    const d = ctx.draft;
    const o = optsValue();
    const colors = ctx.editors.colors ? ctx.editors.colors.getValue() : (d.visual.colors || {});
    const regionsV = ctx.editors.regions ? ctx.editors.regions.getValue() : (d.visual.regions || []);
    const teamsV = ctx.editors.teams ? ctx.editors.teams.getValue() : (d.visual.teams_meta || []);
    return {
      id: (d.id || '').trim() || undefined, name: (d.name || '').trim(), mode: d.mode,
      ...(o.priority ? { priority: o.priority } : {}),
      start: d.start, end: d.end,
      allow_empty: !!allowEmpty,
      admin: {
        login: (d.admin.login || '').trim() || undefined,
        password: (d.admin.password || '').trim() || undefined,
        fullname: (d.admin.fullname || '').trim() || undefined,
      },
      ...(d.userMode === 'shared' ? { users_from: d.usersFrom || 'treino' }
        : { users: (d.users || []).filter((u) => u.login || u.fullname).map((u) => ({ login: u.login || undefined, password: u.password || undefined, fullname: u.fullname || undefined, email: u.email || undefined })) }),
      problems: (d.problems || []).map((p, i) => ({
        ...(p.bank_id ? { bank_id: p.bank_id } : { source: p.source || 'cdmoj', problem_id: p.problem_id }),
        // nome vazio = AUTOMÁTICO: o servidor põe o título no idioma da prova (cc_prob_title)
        ...((p.name || '').trim() ? { name: p.name.trim() } : {}), letter: p._letter || autoLetter(i),
        ...(p._stmt ? { statement_b64: b64utf8(p._stmt) } : (p._stmt_b64 ? { statement_b64: p._stmt_b64 } : {})),
        ...(p._stmt_pdf_b64 ? { statement_pdf_b64: p._stmt_pdf_b64 } : {}),
        ...((p.languages || []).length ? { languages: p.languages } : {}),
        ...((p.judges || []).length ? { judges: p.judges } : {}),
      })),
      ...buildModules(d, colors, regionsV, teamsV),
      locale: o.locale, login_enabled: o.login_enabled,
      ...(o.login_start ? { login_start: o.login_start } : {}),
      ...(o.freeze ? { freeze: o.freeze } : {}),
      show_log: o.show_log !== false, show_editor: o.show_editor !== false, show_tl: o.show_tl !== false,
      allow_backup: o.allow_backup !== false, allow_print: o.allow_print !== false,
      score_anon: !!o.score_anon, manual_verdict: !!o.manual_verdict,
      ...(o.secret ? { secret: true } : {}),
      ...(o.login_ua_substring ? { login_ua_substring: o.login_ua_substring } : {}),
      ...((o.score_full_users || []).length ? { score_full_users: o.score_full_users } : {}),
      ...((o.judges || []).length ? { judges: o.judges } : {}),
      ...(o.penalty_minutes !== undefined ? { penalty_minutes: o.penalty_minutes } : {}),
      ...(o.penalty_verdicts !== undefined ? { penalty_verdicts: o.penalty_verdicts } : {}),
    };
  }

  // spec UNIFICADO: `modules` = { id: true | {on, …seção…} }. As seções cruas vindas de
  // template/export são preservadas; o passo Visual sobrepõe cores/sedes/escolas nas seções
  // `baloes`/`sedes`; a caixa do passo Módulos decide o `on`. Nada mais vai no topo.
  function buildModules(d, colors, regionsV, teamsV) {
    const on = new Set(d.modules || []);
    const m = {};
    Object.entries(d.moduleSections || {}).forEach(([id, sec]) => { m[id] = (sec && typeof sec === 'object') ? { ...sec } : {}; });
    on.forEach((id) => { if (!m[id]) m[id] = {}; });
    if (Object.keys(colors).length) { m.baloes = { ...(m.baloes || {}), colors }; } else if (m.baloes) delete m.baloes.colors;
    if (regionsV.length) { m.sedes = { ...(m.sedes || {}), regions: regionsV }; } else if (m.sedes) delete m.sedes.regions;
    if (teamsV.length) { m.sedes = { ...(m.sedes || {}), teams_meta: teamsV }; } else if (m.sedes) delete m.sedes.teams_meta;
    Object.keys(m).forEach((id) => { m[id].on = on.has(id); });
    return Object.keys(m).length ? { modules: m } : {};
  }
  // do spec (template/export) p/ o draft: ids ligados + seções cruas + o visual (sedes/baloes
  // ou, compat, colors/regions/teams_meta no topo)
  function modulesFromSpec(spec) {
    const ms = (spec && spec.modules && typeof spec.modules === 'object') ? spec.modules : {};
    const on = Object.entries(ms).filter(([, v]) => v === true || (v && typeof v === 'object' && v.on !== false)).map(([k]) => k);
    const sections = {};
    Object.entries(ms).forEach(([k, v]) => { if (v && typeof v === 'object') { const { on: _on, colors, regions, teams_meta, ...rest } = v; sections[k] = rest; } });
    if ((spec.regions || []).length || (spec.teams_meta || []).length) on.push('sedes');
    if (Object.keys(spec.colors || {}).length) on.push('baloes');
    const visual = {
      colors: (ms.baloes && ms.baloes.colors) || spec.colors || {},
      regions: (ms.sedes && ms.sedes.regions) || spec.regions || [],
      teams_meta: (ms.sedes && ms.sedes.teams_meta) || spec.teams_meta || [],
    };
    return { on: [...new Set(on)], sections, visual };
  }

  // aplica um TEMPLATE salvo (spec RELATIVO: duration/login_lead/freeze_before_end)
  function applyTemplate(spec, label) {
    const d = ctx.draft;
    const st = nextFullHour();
    d.origem = label;
    if (spec.mode) d.mode = spec.mode;
    d.start = st; d.end = st + (spec.duration || 10800);
    const o = { ...d.opts };
    ['priority', 'locale', 'login_enabled', 'show_log', 'show_editor', 'show_tl', 'allow_backup',
      'allow_print', 'score_anon', 'manual_verdict', 'login_ua_substring',
      'score_full_users', 'languages', 'judges', 'penalty_minutes', 'penalty_verdicts'].forEach((k) => { if (spec[k] !== undefined) o[k] = spec[k]; });
    if (spec.login_lead) o.login_start = st - spec.login_lead;
    if (spec.freeze_before_end) o.freeze = d.end - spec.freeze_before_end;
    d.opts = o;
    { const mm = modulesFromSpec(spec); d.visual = mm.visual; d.modules = mm.on; d.moduleSections = mm.sections; }
    if (spec.problems && spec.problems.length) d.problems = spec.problems.map(fromSpecProblem);
    ctx.resetEditors();
  }

  // aplica um EXPORT (spec ABSOLUTO de contest existente) — datas novas, sem usuários
  function applyExport(spec, label) {
    const d = ctx.draft;
    const st = nextFullHour();
    const dur = (spec.end && spec.start && spec.end > spec.start) ? (spec.end - spec.start) : 10800;
    d.origem = label;
    d.name = spec.name || ''; d.id = '';
    if (spec.mode) d.mode = spec.mode;
    d.start = st; d.end = st + dur;
    const o = { ...newDraft(perm).opts };
    ['priority', 'locale', 'login_enabled', 'show_log', 'show_editor', 'show_tl', 'allow_backup',
      'allow_print', 'score_anon', 'manual_verdict', 'login_ua_substring',
      'score_full_users', 'languages', 'judges', 'penalty_minutes', 'penalty_verdicts'].forEach((k) => { if (spec[k] !== undefined) o[k] = spec[k]; });
    if (spec.login_start && spec.start && spec.start > spec.login_start) o.login_start = st - (spec.start - spec.login_start);
    if (spec.freeze && spec.end && spec.end > spec.freeze) o.freeze = d.end - (spec.end - spec.freeze);
    d.opts = o;
    { const mm = modulesFromSpec(spec); d.visual = mm.visual; d.modules = mm.on; d.moduleSections = mm.sections; }
    d.problems = (spec.problems || []).map(fromSpecProblem);
    if (spec.users_from) { d.userMode = 'shared'; d.usersFrom = spec.users_from; d.sharedAck = false; }   // template/duplicata: confirma de novo
    ctx.resetEditors();
  }

  function fromSpecProblem(p) {
    return {
      ...(p.bank_id ? { kind: 'bank', bank_id: p.bank_id } : { kind: 'id', source: p.source || 'cdmoj', problem_id: p.problem_id }),
      // sem nome no spec = automático (o servidor decide); nunca o id como nome (virava "org#prob" na sanfona)
      name: p.name || '',
      _letter: p.letter || '',
      ...(p.statement_b64 ? { _stmt_b64: p.statement_b64 } : {}),
      ...(p.statement_pdf_b64 ? { _stmt_pdf_b64: p.statement_pdf_b64 } : {}),
      ...((p.languages || []).length ? { languages: p.languages } : {}),
      ...((p.judges || []).length ? { judges: p.judges } : {}),
    };
  }

  async function submit(allowEmpty, msg) {
    const d = ctx.draft;
    if (!(d.name || '').trim()) { msg.className = 'small error-box'; msg.textContent = T('Informe o nome (passo 1).', 'Enter the name (step 1).', 'Ingresa el nombre (paso 1).'); return; }
    if (!(d.admin.login || '').trim()) { msg.className = 'small error-box'; msg.textContent = T('Defina o login do admin (passo 4).', 'Set the admin login (step 4).', 'Define el usuario del admin (paso 4).'); return; }
    if (!allowEmpty && !d.problems.length) { msg.className = 'small error-box'; msg.textContent = T('Adicione problemas (passo 2), ou use "Criar vazio".', 'Add problems (step 2), or use "Create empty".', 'Agrega problemas (paso 2), o usa "Crear vacía".'); return; }
    if (!optsValue().priority) { msg.className = 'small error-box'; msg.textContent = T('Escolha a prioridade no julgamento (passo 5 · Opções): Prova para ICPC/OBI de verdade, Lista para aula/exercício.', 'Choose the judging priority (step 5 · Options): Contest for a real ICPC/OBI contest, List for a class/exercise.', 'Elige la prioridad en la evaluación (paso 5 · Opciones): Competencia para un ICPC/OBI de verdad, Lista para clase/ejercicio.'); return; }
    if (d.userMode === 'shared' && !d.sharedAck) { msg.className = 'small error-box'; msg.textContent = T('Usuários compartilhados (passo 3): leia as consequências e marque "Entendi".', 'Shared users (step 3): read the consequences and tick "I understand".', 'Usuarios compartidos (paso 3): lee las consecuencias y marca "Entendido".'); return; }
    const rbad = ctx.editors.regions && ctx.editors.regions.validate ? ctx.editors.regions.validate() : '';
    if (rbad) { msg.className = 'small error-box'; msg.textContent = T('Sedes (passo 6 · Visual): ', 'Sites (step 6 · Appearance): ', 'Sedes (paso 6 · Apariencia): ') + rbad; return; }
    msg.className = 'small'; msg.textContent = T('Criando…', 'Creating…', 'Creando…');
    try {
      const spec = buildSpec(allowEmpty);
      const res = await ctx.api.post('/treino/contest-create/create', spec);
      res._secret = !!spec.secret;
      showResult(res);
    }
    catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha ao criar', 'failed to create', 'no se pudo crear'); }
  }

  // navegação
  const nav = el('div', { class: 'steps' });
  const wrap = el('div', {});
  const btns = {};
  let current = 0;
  function goto(i) {
    if (i < 0 || i >= STEPS.length) return;
    current = i;
    STEPS.forEach((s, k) => btns[s.id].classList.toggle('active', k === i));
    wrap.innerHTML = '';
    const step = STEPS[i].make(ctx);
    wrap.append(step.el);
    wrap.append(el('div', { class: 'wiz-nav' },
      i > 0 ? el('button', { class: 'btn ghost', onclick: () => goto(i - 1) }, T('← Voltar', '← Back', '← Volver')) : '',
      i < STEPS.length - 1 ? el('button', { class: 'btn', onclick: () => goto(i + 1) }, T('Continuar →', 'Continue →', 'Continuar →')) : '',
      el('span', { class: 'small muted', style: 'margin-left:auto' }, T('origem: ', 'source: ', 'origen: ') + ctx.draft.origem)));
    window.scrollTo({ top: 0 });
  }
  ctx.goto = goto;
  STEPS.forEach((s, i) => { btns[s.id] = el('button', { onclick: () => goto(i) }, s.label); nav.append(btns[s.id]); });

  app.innerHTML = '';
  app.append(nav, wrap);
  goto(0);
}

function autoLetter(i) {
  if (i < 26) return String.fromCharCode(65 + i);
  return String.fromCharCode(65 + Math.floor(i / 26) - 1) + String.fromCharCode(65 + (i % 26));
}

refreshAuth();
boot();
