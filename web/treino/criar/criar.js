// treino/criar/criar.js — WIZARD multi-etapa de criação de contest (shell).
// Responsabilidades: gate por permissão, estado único `draft`, navegação entre passos,
// buildSpec (draft -> spec da API), submissão e tela de resultado. Os passos vivem em
// ./steps/*.js e RE-MONTAM lendo do draft (ir-e-voltar não perde nada). Editores pesados
// (opções/visual) são cacheados em ctx.editors e sobrevivem à navegação; aplicar
// template/duplicar reseta o cache (ctx.resetEditors) p/ recriá-los do draft novo.
import { apiGet, apiPost, getToken } from '/shared/api.js';
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
import { makeStepRevisao } from './steps/revisao.js';

const app = document.getElementById('app');
const authMount = document.getElementById('authArea');
const refreshAuth = () => renderAuthArea(authMount, 'treino', refreshAuth);

export const MODE_LABEL = {
  icpc: T('ICPC (tempo + penalidade)', 'ICPC (time + penalty)'), obi: T('OBI (pontos parciais)', 'OBI (partial points)'),
  treino: T('Treino (lista, sem penalidade)', 'Training (list, no penalty)'), heuristic: T('Heurístico / custom', 'Heuristic / custom'), outro: T('Outro (custom)', 'Other (custom)'),
};
const nowEpoch = () => Math.floor(Date.now() / 1000);
const nextFullHour = () => { const e = nowEpoch(); return e - (e % 3600) + 3600; };
const b64utf8 = (s) => btoa(unescape(encodeURIComponent(s)));

const STEPS = [
  { id: 'inicio', label: T('0 · Começar', '0 · Start'), make: makeStepInicio },
  { id: 'dados', label: T('1 · Dados', '1 · Details'), make: makeStepDados },
  { id: 'problemas', label: T('2 · Problemas', '2 · Problems'), make: makeStepProblemas },
  { id: 'usuarios', label: T('3 · Usuários', '3 · Users'), make: makeStepUsuarios },
  { id: 'admin', label: T('4 · Admin', '4 · Admin'), make: makeStepAdmin },
  { id: 'opcoes', label: T('5 · Opções', '5 · Options'), make: makeStepOpcoes },
  { id: 'visual', label: T('6 · Visual', '6 · Appearance'), make: makeStepVisual },
  { id: 'revisao', label: T('7 · Revisão', '7 · Review'), make: makeStepRevisao },
];

function newDraft(perm) {
  const me = perm.login || '';
  return {
    origem: T('em branco', 'blank'),
    name: '', id: '', mode: 'icpc',
    start: nowEpoch(), end: nowEpoch() + 3 * 3600,
    // problems: {kind:'bank'|'id', bank_id?|source+problem_id, name, _letter?, _stmt? (texto),
    //            _stmt_b64?/_stmt_pdf_b64? (herdados de export/template), languages?, _private?, _hasStmt?}
    problems: [],
    userMode: 'own', users: [], usersFrom: 'treino',
    admin: { login: me ? (me.endsWith('.admin') ? me : me + '.admin') : '', password: '', fullname: perm.name || '' },
    // opts alimenta o settings-editor (shape do GET /contest/admin/settings + priority do create)
    opts: { locale: 'pt', login_enabled: true, priority: 'lista-publica' },
    visual: { colors: {}, regions: [], teams_meta: [] },
  };
}

// ---------- telas terminais ----------
function showDenied(p) {
  app.innerHTML = '';
  app.append(el('div', { class: 'section' },
    el('h2', {}, T('🔒 Sem permissão para criar contests', '🔒 No permission to create contests')),
    el('p', { class: 'muted' }, T('Motivo: ', 'Reason: ') + ((p && p.reason) || T('não autenticado', 'not authenticated')) + '.'),
    p ? el('p', { class: 'small muted' },
      T('Você resolveu ', 'You solved ') + (p.solved_count || 0) + T(' problemas', ' problems') +
      (p.threshold > 0 ? (T(' — o limite automático para liberar é ', ' — the automatic threshold to unlock is ') + p.threshold) : '') +
      T('. Um administrador pode liberar seu acesso na lista de criadores.', '. An administrator can grant your access in the creators list.'))
      : el('p', {}, T('Faça login no Treino Livre primeiro.', 'Log in to Free Training first.')),
    el('a', { class: 'btn ghost', href: '/treino/' }, T('← Voltar ao treino', '← Back to training'))));
}


function showResult(res) {
  app.innerHTML = '';
  const card = el('div', { class: 'result-card' },
    el('h2', { style: 'margin:.1rem 0 .6rem' }, T('✅ Contest criado e no ar!', '✅ Contest created and live!')),
    el('p', {}, T('O contest ', 'The contest '), el('b', {}, res.contest_id), ' (', String(res.problems), T(' problemas) foi publicado.', ' problems) was published.')),
    el('div', { class: 'warn-box', style: 'margin:.6rem 0' },
      T('⚠ Guarde as credenciais abaixo — as senhas só são exibidas agora.', '⚠ Save the credentials below — passwords are only shown now.')),
    el('p', {}, T('Admin do contest: ', 'Contest admin: '), el('span', { class: 'cred' }, res.admin_login),
      res.admin_reused
        ? el('span', { class: 'small muted' }, T(' · conta existente reutilizada — use sua senha atual do Treino Livre.', ' · existing account reused — use your current Free Training password.'))
        : [T(' · senha: ', ' · password: '), el('span', { class: 'cred' }, res.admin_password)]));
  if (res._secret) card.append(el('div', { class: 'warn-box', style: 'margin:.4rem 0' },
    T('🕵️ SUPER SECRETO: o contest NÃO aparece na home/arquivo/status e o placar exige login — distribua o link ', '🕵️ SUPER SECRET: the contest does NOT appear on home/archive/status and the scoreboard requires login — share the link '), el('b', {}, res.url), T(' aos participantes.', ' with participants.')));
  if (res.users_from) card.append(el('p', { class: 'small muted' }, T('Usuários: compartilhados do "', 'Users: shared from "') + res.users_from + T('" (login com a conta do Treino Livre).', '" (log in with your Free Training account).')));
  if (res.users && res.users.length > 1) {
    card.append(el('p', {}, res.users.length + T(' contas criadas. ', ' accounts created. '),
      el('button', { class: 'btn ghost', onclick: () => downloadCsv(res.contest_id + '-credenciais.csv', res.users) }, T('⬇ baixar credenciais (CSV)', '⬇ download credentials (CSV)'))));
  }
  card.append(el('div', { class: 'row', style: 'margin-top:.7rem' },
    el('a', { class: 'btn', href: res.url }, T('Abrir contest →', 'Open contest →')),
    el('a', { class: 'btn ghost', href: '/contest/admin/?c=' + encodeURIComponent(res.contest_id) }, T('⚙️ Admin do contest', '⚙️ Contest admin')),
    el('a', { class: 'btn ghost', href: res.scoreboard_url }, T('Placar', 'Scoreboard')),
    el('a', { class: 'btn ghost', href: '/treino/criar/' }, T('Criar outro', 'Create another'))));
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
      meta: async () => {
        const [t, c] = await Promise.all([
          apiGet('/treino/contest-create/tags', { contest: 'treino', auth: true }).catch(() => ({ tags: [] })),
          apiGet('/treino/contest-create/collections', { contest: 'treino', auth: true }).catch(() => ({ collections: [] })),
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
      priority: o.priority || 'lista-publica',
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
        name: p.name, letter: p._letter || autoLetter(i),
        ...(p._stmt ? { statement_b64: b64utf8(p._stmt) } : (p._stmt_b64 ? { statement_b64: p._stmt_b64 } : {})),
        ...(p._stmt_pdf_b64 ? { statement_pdf_b64: p._stmt_pdf_b64 } : {}),
        ...((p.languages || []).length ? { languages: p.languages } : {}),
        ...((p.judges || []).length ? { judges: p.judges } : {}),
      })),
      ...(Object.keys(colors).length ? { colors } : {}),
      ...(regionsV.length ? { regions: regionsV } : {}),
      ...(teamsV.length ? { teams_meta: teamsV } : {}),
      locale: o.locale, login_enabled: o.login_enabled,
      ...(o.login_start ? { login_start: o.login_start } : {}),
      ...(o.freeze ? { freeze: o.freeze } : {}),
      showcode: !!o.show_code,
      show_log: o.show_log !== false, show_editor: o.show_editor !== false, show_tl: o.show_tl !== false,
      allow_backup: o.allow_backup !== false, allow_print: o.allow_print !== false,
      score_anon: !!o.score_anon, manual_verdict: !!o.manual_verdict,
      ...(o.secret ? { secret: true } : {}),
      ...(o.allow_late !== undefined ? { allow_late: !!o.allow_late } : {}),
      ...(o.login_ua_substring ? { login_ua_substring: o.login_ua_substring } : {}),
      ...((o.score_full_users || []).length ? { score_full_users: o.score_full_users } : {}),
      ...((o.judges || []).length ? { judges: o.judges } : {}),
      ...(o.penalty_minutes !== undefined ? { penalty_minutes: o.penalty_minutes } : {}),
      ...(o.penalty_verdicts !== undefined ? { penalty_verdicts: o.penalty_verdicts } : {}),
    };
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
      'allow_print', 'score_anon', 'manual_verdict', 'allow_late', 'login_ua_substring',
      'score_full_users', 'languages', 'judges', 'penalty_minutes', 'penalty_verdicts'].forEach((k) => { if (spec[k] !== undefined) o[k] = spec[k]; });
    if (spec.showcode !== undefined) o.show_code = spec.showcode;
    if (spec.show_code !== undefined) o.show_code = spec.show_code;
    if (spec.login_lead) o.login_start = st - spec.login_lead;
    if (spec.freeze_before_end) o.freeze = d.end - spec.freeze_before_end;
    d.opts = o;
    d.visual = { colors: spec.colors || {}, regions: spec.regions || [], teams_meta: spec.teams_meta || [] };
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
      'allow_print', 'score_anon', 'manual_verdict', 'allow_late', 'login_ua_substring',
      'score_full_users', 'languages', 'judges', 'penalty_minutes', 'penalty_verdicts'].forEach((k) => { if (spec[k] !== undefined) o[k] = spec[k]; });
    if (spec.showcode !== undefined) o.show_code = spec.showcode;
    if (spec.login_start && spec.start && spec.start > spec.login_start) o.login_start = st - (spec.start - spec.login_start);
    if (spec.freeze && spec.end && spec.end > spec.freeze) o.freeze = d.end - (spec.end - spec.freeze);
    d.opts = o;
    d.visual = { colors: spec.colors || {}, regions: spec.regions || [], teams_meta: spec.teams_meta || [] };
    d.problems = (spec.problems || []).map(fromSpecProblem);
    if (spec.users_from) { d.userMode = 'shared'; d.usersFrom = spec.users_from; }
    ctx.resetEditors();
  }

  function fromSpecProblem(p) {
    return {
      ...(p.bank_id ? { kind: 'bank', bank_id: p.bank_id } : { kind: 'id', source: p.source || 'cdmoj', problem_id: p.problem_id }),
      name: p.name || p.bank_id || p.problem_id || '',
      _letter: p.letter || '',
      ...(p.statement_b64 ? { _stmt_b64: p.statement_b64 } : {}),
      ...(p.statement_pdf_b64 ? { _stmt_pdf_b64: p.statement_pdf_b64 } : {}),
      ...((p.languages || []).length ? { languages: p.languages } : {}),
      ...((p.judges || []).length ? { judges: p.judges } : {}),
    };
  }

  async function submit(allowEmpty, msg) {
    const d = ctx.draft;
    if (!(d.name || '').trim()) { msg.className = 'small error-box'; msg.textContent = T('Informe o nome (passo 1).', 'Enter the name (step 1).'); return; }
    if (!(d.admin.login || '').trim()) { msg.className = 'small error-box'; msg.textContent = T('Defina o login do admin (passo 4).', 'Set the admin login (step 4).'); return; }
    if (!allowEmpty && !d.problems.length) { msg.className = 'small error-box'; msg.textContent = T('Adicione problemas (passo 2), ou use "Criar vazio".', 'Add problems (step 2), or use "Create empty".'); return; }
    msg.className = 'small'; msg.textContent = T('Criando…', 'Creating…');
    try {
      const spec = buildSpec(allowEmpty);
      const res = await ctx.api.post('/treino/contest-create/create', spec);
      res._secret = !!spec.secret;
      showResult(res);
    }
    catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha ao criar', 'failed to create'); }
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
      i > 0 ? el('button', { class: 'btn ghost', onclick: () => goto(i - 1) }, T('← Voltar', '← Back')) : '',
      i < STEPS.length - 1 ? el('button', { class: 'btn', onclick: () => goto(i + 1) }, T('Continuar →', 'Continue →')) : '',
      el('span', { class: 'small muted', style: 'margin-left:auto' }, T('origem: ', 'source: ') + ctx.draft.origem)));
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
