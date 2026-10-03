// steps/revisao.js — passo 8: resumo do spec, validações, Criar / Criar vazio, e
// "salvar como template" (o servidor relativiza datas e aplica a whitelist).
import { el } from '/shared/ui.js';
import { T, uiLocale } from '/shared/i18n.js';
import { MODE_LABEL } from '../criar.js';
import { MODULES } from '/contest/admin/modules.js';

const fmtDate = (e) => new Date((+e || 0) * 1000).toLocaleString(uiLocale());

export function makeStepRevisao(ctx) {
  const d = ctx.draft;
  const spec = ctx.buildSpec(true);
  const msg = el('div', { class: 'small', style: 'margin:.5rem 0' });

  const probs = (spec.problems || []);
  const users = d.userMode === 'shared'
    ? T('compartilhados de "', 'shared from "', 'compartidos de "') + (d.usersFrom || 'treino') + T('" — login e senha do Treino Livre; para prova, converta depois em Pessoas › Contas (sem volta)', '" — Free Training login and password; for an exam, convert later in People › Accounts (no way back)', '" — usuario y contraseña de Entrenamiento libre; para un examen, convierte después en Personas › Cuentas (sin vuelta atrás)')
    : (spec.users || []).length + T(' conta(s) própria(s)', ' own account(s)', ' cuenta(s) propia(s)');
  const optsBits = [];
  if (spec.secret) optsBits.push(T('🕵️ SUPER SECRETO (não listado; placar exige login)', '🕵️ SUPER SECRET (not listed; scoreboard requires login)', '🕵️ SUPER SECRETO (no listada; el marcador exige inicio de sesión)'));
  // a prioridade sempre aparece (é obrigatória): sem ela, o aviso — o Criar recusa
  optsBits.push(spec.priority ? T('prioridade ', 'priority ', 'prioridad ') + spec.priority : T('⚠ prioridade não escolhida (passo 5)', '⚠ priority not chosen (step 5)', '⚠ prioridad no elegida (paso 5)'));
  if ((spec.languages || []).length) optsBits.push(T('linguagens: ', 'languages: ', 'lenguajes: ') + spec.languages.join(' '));
  if (spec.score_anon) optsBits.push(T('placar anônimo', 'anonymous scoreboard', 'marcador anónimo'));
  if (spec.manual_verdict) optsBits.push(T('veredicto manual', 'manual verdict', 'veredicto manual'));
  if (spec.login_ua_substring) optsBits.push(T('gate de UA', 'UA gate', 'gate de UA'));
  if (spec.freeze) optsBits.push(T('freeze ', 'freeze ', 'congelamiento ') + fmtDate(spec.freeze));
  if (spec.login_start) optsBits.push(T('login abre ', 'login opens ', 'el ingreso abre ') + fmtDate(spec.login_start));
  if (spec.show_log === false) optsBits.push(T('sem log', 'no log', 'sin registro'));
  if (spec.show_editor === false) optsBits.push(T('sem editor', 'no editor', 'sin editor'));

  const issues = [];
  if (!(spec.name || '').trim()) issues.push(T('Falta o nome (passo 1).', 'Name is missing (step 1).', 'Falta el nombre (paso 1).'));
  if (!(spec.admin.login || '').trim()) issues.push(T('Falta o login do admin (passo 4).', 'Admin login is missing (step 4).', 'Falta el usuario del admin (paso 4).'));
  if (!probs.length) issues.push(T('Sem problemas (passo 2) — só dá para criar vazio.', 'No problems (step 2) — you can only create empty.', 'Sin problemas (paso 2) — solo se puede crear vacía.'));
  if (d.userMode === 'shared' && !d.sharedAck) issues.push(T('Usuários compartilhados: marque "Entendi" nas consequências (passo 3).', 'Shared users: tick "I understand" on the consequences (step 3).', 'Usuarios compartidos: marca "Entendido" en las consecuencias (paso 3).'));
  if (spec.end <= spec.start) issues.push(T('Fim antes do início (passo 1).', 'End before start (step 1).', 'El fin es antes del inicio (paso 1).'));

  const row = (k, v) => el('tr', {}, el('td', { class: 'small muted', style: 'white-space:nowrap' }, k), el('td', {}, v));
  const table = el('table', { class: 'moj' }, el('tbody', {},
    row(T('Nome', 'Name', 'Nombre'), spec.name || '—'),
    row(T('ID', 'ID', 'ID'), spec.id || T('(gerado do nome)', '(generated from name)', '(generado del nombre)')),
    row(T('Modo', 'Mode', 'Modo'), MODE_LABEL[spec.mode] || spec.mode),
    row(T('Período', 'Period', 'Período'), fmtDate(spec.start) + ' → ' + fmtDate(spec.end)),
    row(T('Problemas', 'Problems', 'Problemas'), probs.length ? probs.map((p) => p.letter + '·' + (p.name || p.bank_id || p.problem_id)).join('  ') : '—'),
    row(T('Usuários', 'Users', 'Usuarios'), users),
    row(T('Admin', 'Admin', 'Admin'), (spec.admin.login || '—') + (spec.admin.password ? T(' (senha definida)', ' (password set)', ' (contraseña definida)') : T(' (senha gerada)', ' (password generated)', ' (contraseña generada)'))),
    row(T('Opções', 'Options', 'Opciones'), optsBits.length ? optsBits.join(' · ') : T('(padrões)', '(defaults)', '(predeterminados)')),
    row(T('Módulos', 'Modules', 'Módulos'), (() => {
      const ms = spec.modules || {};
      const on = MODULES().filter((m) => ms[m.id] === true || (ms[m.id] && ms[m.id].on !== false));
      return on.length ? on.map((m) => m.icon + ' ' + m.name).join(' · ') : T('(nenhum — prova comum)', '(none — plain contest)', '(ninguno — competencia común)');
    })()),
    row(T('Visual', 'Appearance', 'Aspecto visual'), (() => {
      const ms = spec.modules || {};
      const colors = (ms.baloes && ms.baloes.colors) || {}, sedes = ms.sedes || {};
      return [Object.keys(colors).length && T('cores', 'colors', 'colores'), (sedes.teams_meta || []).length && T('países/escolas', 'countries/schools', 'países/escuelas'), (sedes.regions || []).length && T('regiões', 'regions', 'regiones')].filter(Boolean).join(' · ') || T('(nenhum)', '(none)', '(ninguno)');
    })())));

  const createBtn = el('button', { class: 'btn', onclick: () => ctx.submit(false, msg) }, T('🚀 Criar contest', '🚀 Create contest', '🚀 Crear competencia'));
  const emptyBtn = el('button', { class: 'btn ghost', onclick: () => ctx.submit(true, msg) }, T('Criar vazio (configuro depois)', 'Create empty (configure later)', 'Crear vacía (configuro después)'));

  // salvar como template (envia o spec ABSOLUTO; o servidor relativiza + whitelist)
  const tplName = el('input', { placeholder: T('nome do template', 'template name', 'nombre de la plantilla'), style: 'min-width:180px' });
  const tplProbs = el('input', { type: 'checkbox' });
  const tplBtn = el('button', { class: 'btn ghost', onclick: async () => {
    const n = tplName.value.trim(); if (!n) { tplName.focus(); return; }
    const t = ctx.buildSpec(true);
    if (!tplProbs.checked) delete t.problems;
    msg.className = 'small'; msg.textContent = T('Salvando template…', 'Saving template…', 'Guardando plantilla…');
    try { await ctx.api.post('/treino/contest-create/templates', { op: 'save', name: n, template: t }); msg.textContent = '✓ template "' + n + T('" salvo', '" saved', '" guardada'); }
    catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha ao salvar template', 'failed to save template', 'no se pudo guardar la plantilla'); }
  } }, T('💾 Salvar como template', '💾 Save as template', '💾 Guardar como plantilla'));

  const root = el('div', { class: 'section' },
    el('h2', {}, T('8 · Revisão', '8 · Review', '8 · Revisión')),
    issues.length ? el('div', { class: 'warn-box', style: 'margin:.5rem 0' },
      el('b', {}, T('Pendências: ', 'Pending items: ', 'Pendientes: ')), el('ul', { style: 'margin:.2rem 0 0; padding-left:1.2rem' }, ...issues.map((x) => el('li', {}, x)))) : '',
    el('div', { class: 'chart-wrap' }, table),
    el('div', { class: 'row', style: 'margin-top:.8rem' }, createBtn, emptyBtn),
    msg,
    el('h3', { style: 'margin:1rem 0 .3rem' }, T('💾 Reaproveitar depois', '💾 Reuse later', '💾 Reutilizar después')),
    el('div', { class: 'row' }, tplName, el('label', { class: 'small' }, tplProbs, T(' incluir problemas', ' include problems', ' incluir problemas')), tplBtn),
    el('p', { class: 'muted small', style: 'margin-top:.5rem' }, T('O contest entra no ar imediatamente. Um administrador pode removê-lo depois, se necessário.', 'The contest goes live immediately. An administrator can remove it later if needed.', 'La competencia entra en línea de inmediato. Un administrador puede eliminarla después si es necesario.')));
  return { el: root };
}
