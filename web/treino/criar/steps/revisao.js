// steps/revisao.js — passo 7: resumo do spec, validações, Criar / Criar vazio, e
// "salvar como template" (o servidor relativiza datas e aplica a whitelist).
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';
import { MODE_LABEL } from '../criar.js';

const fmtDate = (e) => new Date((+e || 0) * 1000).toLocaleString('pt-BR');

export function makeStepRevisao(ctx) {
  const d = ctx.draft;
  const spec = ctx.buildSpec(true);
  const msg = el('div', { class: 'small', style: 'margin:.5rem 0' });

  const probs = (spec.problems || []);
  const users = d.userMode === 'shared'
    ? T('compartilhados de "', 'shared from "') + (d.usersFrom || 'treino') + '"'
    : (spec.users || []).length + T(' conta(s) própria(s)', ' own account(s)');
  const optsBits = [];
  if (spec.secret) optsBits.push(T('🕵️ SUPER SECRETO (não listado; placar exige login)', '🕵️ SUPER SECRET (not listed; scoreboard requires login)'));
  if (spec.priority && spec.priority !== 'lista-publica') optsBits.push(T('prioridade ', 'priority ') + spec.priority);
  if ((spec.languages || []).length) optsBits.push(T('linguagens: ', 'languages: ') + spec.languages.join(' '));
  if (spec.score_anon) optsBits.push(T('placar anônimo', 'anonymous scoreboard'));
  if (spec.manual_verdict) optsBits.push(T('veredicto manual', 'manual verdict'));
  if (spec.login_ua_substring) optsBits.push(T('gate de UA', 'UA gate'));
  if (spec.freeze) optsBits.push(T('freeze ', 'freeze ') + fmtDate(spec.freeze));
  if (spec.login_start) optsBits.push(T('login abre ', 'login opens ') + fmtDate(spec.login_start));
  if (spec.show_log === false) optsBits.push(T('sem log', 'no log'));
  if (spec.show_editor === false) optsBits.push(T('sem editor', 'no editor'));
  if (spec.showcode) optsBits.push(T('código visível', 'code visible'));

  const issues = [];
  if (!(spec.name || '').trim()) issues.push(T('Falta o nome (passo 1).', 'Name is missing (step 1).'));
  if (!(spec.admin.login || '').trim()) issues.push(T('Falta o login do admin (passo 4).', 'Admin login is missing (step 4).'));
  if (!probs.length) issues.push(T('Sem problemas (passo 2) — só dá para criar vazio.', 'No problems (step 2) — you can only create empty.'));
  if (spec.end <= spec.start) issues.push(T('Fim antes do início (passo 1).', 'End before start (step 1).'));

  const row = (k, v) => el('tr', {}, el('td', { class: 'small muted', style: 'white-space:nowrap' }, k), el('td', {}, v));
  const table = el('table', { class: 'moj' }, el('tbody', {},
    row(T('Nome', 'Name'), spec.name || '—'),
    row(T('ID', 'ID'), spec.id || T('(gerado do nome)', '(generated from name)')),
    row(T('Modo', 'Mode'), MODE_LABEL[spec.mode] || spec.mode),
    row(T('Período', 'Period'), fmtDate(spec.start) + ' → ' + fmtDate(spec.end)),
    row(T('Problemas', 'Problems'), probs.length ? probs.map((p) => p.letter + '·' + (p.name || p.bank_id || p.problem_id)).join('  ') : '—'),
    row(T('Usuários', 'Users'), users),
    row(T('Admin', 'Admin'), (spec.admin.login || '—') + (spec.admin.password ? T(' (senha definida)', ' (password set)') : T(' (senha gerada)', ' (password generated)'))),
    row(T('Opções', 'Options'), optsBits.length ? optsBits.join(' · ') : T('(padrões)', '(defaults)')),
    row(T('Visual', 'Appearance'), [Object.keys(spec.colors || {}).length && T('cores', 'colors'), (spec.teams_meta || []).length && T('países/escolas', 'countries/schools'), (spec.regions || []).length && T('regiões', 'regions')].filter(Boolean).join(' · ') || T('(nenhum)', '(none)'))));

  const createBtn = el('button', { class: 'btn', onclick: () => ctx.submit(false, msg) }, T('🚀 Criar contest', '🚀 Create contest'));
  const emptyBtn = el('button', { class: 'btn ghost', onclick: () => ctx.submit(true, msg) }, T('Criar vazio (configuro depois)', 'Create empty (configure later)'));

  // salvar como template (envia o spec ABSOLUTO; o servidor relativiza + whitelist)
  const tplName = el('input', { placeholder: T('nome do template', 'template name'), style: 'min-width:180px' });
  const tplProbs = el('input', { type: 'checkbox' });
  const tplBtn = el('button', { class: 'btn ghost', onclick: async () => {
    const n = tplName.value.trim(); if (!n) { tplName.focus(); return; }
    const t = ctx.buildSpec(true);
    if (!tplProbs.checked) delete t.problems;
    msg.className = 'small'; msg.textContent = T('Salvando template…', 'Saving template…');
    try { await ctx.api.post('/treino/contest-create/templates', { op: 'save', name: n, template: t }); msg.textContent = '✓ template "' + n + T('" salvo', '" saved'); }
    catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha ao salvar template', 'failed to save template'); }
  } }, T('💾 Salvar como template', '💾 Save as template'));

  const root = el('div', { class: 'section' },
    el('h2', {}, T('7 · Revisão', '7 · Review')),
    issues.length ? el('div', { class: 'warn-box', style: 'margin:.5rem 0' },
      el('b', {}, T('Pendências: ', 'Pending items: ')), el('ul', { style: 'margin:.2rem 0 0; padding-left:1.2rem' }, ...issues.map((x) => el('li', {}, x)))) : '',
    el('div', { class: 'chart-wrap' }, table),
    el('div', { class: 'row', style: 'margin-top:.8rem' }, createBtn, emptyBtn),
    msg,
    el('h3', { style: 'margin:1rem 0 .3rem' }, T('💾 Reaproveitar depois', '💾 Reuse later')),
    el('div', { class: 'row' }, tplName, el('label', { class: 'small' }, tplProbs, T(' incluir problemas', ' include problems')), tplBtn),
    el('p', { class: 'muted small', style: 'margin-top:.5rem' }, T('O contest entra no ar imediatamente. Um administrador pode removê-lo depois, se necessário.', 'The contest goes live immediately. An administrator can remove it later if needed.')));
  return { el: root };
}
