// steps/dados.js — passo 1: nome, id, modo e datas. (Prioridade fica no passo Opções,
// junto dos demais campos do settings-editor.)
import { el } from '/shared/ui.js';
import { toLocalDT, dtToEpoch } from '/shared/contest-config/util.js';
import { MODE_LABEL } from '../criar.js';

export function makeStepDados(ctx) {
  const d = ctx.draft;
  const modes = (ctx.perm.allowed_modes && ctx.perm.allowed_modes.length) ? ctx.perm.allowed_modes : ['icpc', 'obi', 'treino', 'heuristic'];
  const name = el('input', { placeholder: 'Ex.: Maratona de Treino 2026', value: d.name || '' });
  name.addEventListener('input', () => { d.name = name.value; });
  const cid = el('input', { placeholder: '(gerado do nome se vazio) — a-z 0-9 . _ -', value: d.id || '' });
  cid.addEventListener('input', () => { d.id = cid.value; });
  const mode = el('select', {}, ...modes.map((m) => el('option', { value: m }, MODE_LABEL[m] || m)));
  if (modes.includes(d.mode)) mode.value = d.mode;
  d.mode = mode.value;
  mode.addEventListener('change', () => {
    d.mode = mode.value;
    // treino liga auto-cadastro por padrão (o usuário pode desligar no passo Opções)
    if (mode.value === 'treino' && !ctx.editors.settings && d.opts.allow_late === undefined) d.opts.allow_late = true;
  });
  const start = el('input', { type: 'datetime-local', value: toLocalDT(d.start) });
  start.addEventListener('input', () => { const e = dtToEpoch(start.value); if (e) d.start = e; });
  const end = el('input', { type: 'datetime-local', value: toLocalDT(d.end) });
  end.addEventListener('input', () => { const e = dtToEpoch(end.value); if (e) d.end = e; });

  const root = el('div', { class: 'section' },
    el('h2', {}, '1 · Dados do contest'),
    el('div', { class: 'field' }, el('label', {}, 'Nome'), name),
    el('div', { class: 'grid2' },
      el('div', { class: 'field' }, el('label', {}, 'ID (opcional)'), cid),
      el('div', { class: 'field' }, el('label', {}, 'Modo / placar'), mode)),
    el('div', { class: 'grid2' },
      el('div', { class: 'field' }, el('label', {}, 'Início'), start),
      el('div', { class: 'field' }, el('label', {}, 'Fim'), end)),
    el('p', { class: 'muted small' }, 'Linguagens, prioridade de julgamento e demais opções ficam no passo 5 · Opções.'));
  return { el: root };
}
