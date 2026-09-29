// steps/dados.js — passo 1: nome, id, modo e datas. (Prioridade fica no passo Opções,
// junto dos demais campos do settings-editor.)
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';
import { toLocalDT, dtToEpoch } from '/shared/contest-config/util.js';
import { MODE_LABEL } from '../criar.js';

export function makeStepDados(ctx) {
  const d = ctx.draft;
  const modes = (ctx.perm.allowed_modes && ctx.perm.allowed_modes.length) ? ctx.perm.allowed_modes : ['icpc', 'obi', 'treino', 'heuristic'];
  const name = el('input', { placeholder: T('Ex.: Maratona de Treino 2026', 'E.g.: Training Marathon 2026', 'Ej.: Maratón de Entrenamiento 2026'), value: d.name || '' });
  name.addEventListener('input', () => { d.name = name.value; });
  const cid = el('input', { placeholder: T('(gerado do nome se vazio) — a-z 0-9 . _ -', '(generated from the name if empty) — a-z 0-9 . _ -', '(generado del nombre si está vacío) — a-z 0-9 . _ -'), value: d.id || '' });
  // prefixos reservados (`icpc*` = só super-admin): a API recusa com 403; aqui só avisa antes
  const reserved = Array.isArray(ctx.perm.reserved_id_prefixes) ? ctx.perm.reserved_id_prefixes : ['icpc'];
  const idWarn = el('div', { class: 'small error-box', style: 'display:none;margin-top:.3rem' });
  const checkId = () => {
    const v = (cid.value || '').trim().toLowerCase();
    const hit = !ctx.perm.is_superadmin && reserved.find((pfx) => v.startsWith(pfx));
    idWarn.style.display = hit ? '' : 'none';
    if (hit) idWarn.textContent = T(`Ids que começam por "${hit}" são da organização: só um super-admin cria. Escolha outro id.`, `Ids starting with "${hit}" belong to the organization: only a super-admin can create them. Pick another id.`, `Los ids que empiezan por "${hit}" son de la organización: solo un super-admin puede crearlos. Elige otro id.`);
  };
  cid.addEventListener('input', () => { d.id = cid.value; checkId(); }); checkId();
  const mode = el('select', {}, ...modes.map((m) => el('option', { value: m }, MODE_LABEL[m] || m)));
  if (modes.includes(d.mode)) mode.value = d.mode;
  d.mode = mode.value;
  mode.addEventListener('change', () => { d.mode = mode.value; });
  const start = el('input', { type: 'datetime-local', value: toLocalDT(d.start) });
  start.addEventListener('input', () => { const e = dtToEpoch(start.value); if (e) d.start = e; });
  const end = el('input', { type: 'datetime-local', value: toLocalDT(d.end) });
  end.addEventListener('input', () => { const e = dtToEpoch(end.value); if (e) d.end = e; });

  const root = el('div', { class: 'section' },
    el('h2', {}, T('1 · Dados do contest', '1 · Contest details', '1 · Datos de la competencia')),
    el('div', { class: 'field' }, el('label', {}, T('Nome', 'Name', 'Nombre')), name),
    el('div', { class: 'grid2' },
      el('div', { class: 'field' }, el('label', {}, T('ID (opcional)', 'ID (optional)', 'ID (opcional)')), cid, idWarn),
      el('div', { class: 'field' }, el('label', {}, T('Modo / placar', 'Mode / scoreboard', 'Modo / marcador')), mode)),
    el('div', { class: 'grid2' },
      el('div', { class: 'field' }, el('label', {}, T('Início', 'Start', 'Inicio')), start),
      el('div', { class: 'field' }, el('label', {}, T('Fim', 'End', 'Fin')), end)),
    el('p', { class: 'muted small' }, T('Linguagens, prioridade de julgamento e demais opções ficam no passo 5 · Opções.', 'Languages, judging priority and other options are in step 5 · Options.', 'Los lenguajes, la prioridad de evaluación y las demás opciones están en el paso 5 · Opciones.')));
  return { el: root };
}
