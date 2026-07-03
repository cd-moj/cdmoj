// steps/revisao.js — passo 7: resumo do spec, validações, Criar / Criar vazio, e
// "salvar como template" (o servidor relativiza datas e aplica a whitelist).
import { el } from '/shared/ui.js';
import { MODE_LABEL } from '../criar.js';

const fmtDate = (e) => new Date((+e || 0) * 1000).toLocaleString('pt-BR');

export function makeStepRevisao(ctx) {
  const d = ctx.draft;
  const spec = ctx.buildSpec(true);
  const msg = el('div', { class: 'small', style: 'margin:.5rem 0' });

  const probs = (spec.problems || []);
  const users = d.userMode === 'shared'
    ? 'compartilhados de "' + (d.usersFrom || 'treino') + '"'
    : (spec.users || []).length + ' conta(s) própria(s)';
  const optsBits = [];
  if (spec.priority && spec.priority !== 'lista-publica') optsBits.push('prioridade ' + spec.priority);
  if ((spec.languages || []).length) optsBits.push('linguagens: ' + spec.languages.join(' '));
  if (spec.score_anon) optsBits.push('placar anônimo');
  if (spec.manual_verdict) optsBits.push('veredicto manual');
  if (spec.login_ua_substring) optsBits.push('gate de UA');
  if (spec.freeze) optsBits.push('freeze ' + fmtDate(spec.freeze));
  if (spec.login_start) optsBits.push('login abre ' + fmtDate(spec.login_start));
  if (spec.show_log === false) optsBits.push('sem log');
  if (spec.show_editor === false) optsBits.push('sem editor');
  if (spec.showcode) optsBits.push('código visível');

  const issues = [];
  if (!(spec.name || '').trim()) issues.push('Falta o nome (passo 1).');
  if (!(spec.admin.login || '').trim()) issues.push('Falta o login do admin (passo 4).');
  if (!probs.length) issues.push('Sem problemas (passo 2) — só dá para criar vazio.');
  if (spec.end <= spec.start) issues.push('Fim antes do início (passo 1).');

  const row = (k, v) => el('tr', {}, el('td', { class: 'small muted', style: 'white-space:nowrap' }, k), el('td', {}, v));
  const table = el('table', { class: 'moj' }, el('tbody', {},
    row('Nome', spec.name || '—'),
    row('ID', spec.id || '(gerado do nome)'),
    row('Modo', MODE_LABEL[spec.mode] || spec.mode),
    row('Período', fmtDate(spec.start) + ' → ' + fmtDate(spec.end)),
    row('Problemas', probs.length ? probs.map((p) => p.letter + '·' + (p.name || p.bank_id || p.problem_id)).join('  ') : '—'),
    row('Usuários', users),
    row('Admin', (spec.admin.login || '—') + (spec.admin.password ? ' (senha definida)' : ' (senha gerada)')),
    row('Opções', optsBits.length ? optsBits.join(' · ') : '(padrões)'),
    row('Visual', [Object.keys(spec.colors || {}).length && 'cores', (spec.teams_meta || []).length && 'países/escolas', (spec.regions || []).length && 'regiões'].filter(Boolean).join(' · ') || '(nenhum)')));

  const createBtn = el('button', { class: 'btn', onclick: () => ctx.submit(false, msg) }, '🚀 Criar contest');
  const emptyBtn = el('button', { class: 'btn ghost', onclick: () => ctx.submit(true, msg) }, 'Criar vazio (configuro depois)');

  // salvar como template (envia o spec ABSOLUTO; o servidor relativiza + whitelist)
  const tplName = el('input', { placeholder: 'nome do template', style: 'min-width:180px' });
  const tplProbs = el('input', { type: 'checkbox' });
  const tplBtn = el('button', { class: 'btn ghost', onclick: async () => {
    const n = tplName.value.trim(); if (!n) { tplName.focus(); return; }
    const t = ctx.buildSpec(true);
    if (!tplProbs.checked) delete t.problems;
    msg.className = 'small'; msg.textContent = 'Salvando template…';
    try { await ctx.api.post('/treino/contest-create/templates', { op: 'save', name: n, template: t }); msg.textContent = '✓ template "' + n + '" salvo'; }
    catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || 'falha ao salvar template'; }
  } }, '💾 Salvar como template');

  const root = el('div', { class: 'section' },
    el('h2', {}, '7 · Revisão'),
    issues.length ? el('div', { class: 'warn-box', style: 'margin:.5rem 0' },
      el('b', {}, 'Pendências: '), el('ul', { style: 'margin:.2rem 0 0; padding-left:1.2rem' }, ...issues.map((x) => el('li', {}, x)))) : '',
    el('div', { class: 'chart-wrap' }, table),
    el('div', { class: 'row', style: 'margin-top:.8rem' }, createBtn, emptyBtn),
    msg,
    el('h3', { style: 'margin:1rem 0 .3rem' }, '💾 Reaproveitar depois'),
    el('div', { class: 'row' }, tplName, el('label', { class: 'small' }, tplProbs, ' incluir problemas'), tplBtn),
    el('p', { class: 'muted small', style: 'margin-top:.5rem' }, 'O contest entra no ar imediatamente. Um administrador pode removê-lo depois, se necessário.'));
  return { el: root };
}
