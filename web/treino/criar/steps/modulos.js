// steps/modulos.js — passo 7: MÓDULOS do contest (grupos de recursos que o admin liga). O mesmo
// catálogo do painel Central › Módulos (/contest/admin/modules.js); presets só pré-marcam.
// O que o passo Visual preencheu (cores, sedes, países/escolas) vai para as seções `baloes` e
// `sedes` do spec — ligado ou não, o dado não se perde (o admin liga depois em Módulos).
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';
import { MODULES, PRESETS } from '/contest/admin/modules.js';

export function makeStepModulos(ctx) {
  const d = ctx.draft;
  if (!Array.isArray(d.modules)) d.modules = [];
  const checks = {};
  const msg = el('div', { class: 'small muted', style: 'margin:.3rem 0' });
  const sync = () => { d.modules = Object.entries(checks).filter(([, cb]) => cb.checked).map(([id]) => id); };

  // `esqueletos` EXIGE o editor embutido (a API recusa com 422 editor_required): com o editor desligado no
  // passo 5, a caixa fica travada e desmarcada
  const noEditor = !!(d.opts && d.opts.show_editor === false);
  if (noEditor && d.modules.includes('esqueletos')) d.modules = d.modules.filter((x) => x !== 'esqueletos');
  const card = (m) => {
    const cb = el('input', { type: 'checkbox', onchange: sync }); cb.checked = d.modules.includes(m.id); checks[m.id] = cb;
    const blocked = m.id === 'esqueletos' && noEditor;
    if (blocked) { cb.checked = false; cb.disabled = true; }
    return el('div', { class: 'gen-card' + (blocked ? ' muted' : '') },
      el('label', { style: 'display:flex;gap:.5rem;align-items:flex-start;cursor:pointer' }, cb,
        el('div', { style: 'flex:1' },
          el('h4', { style: 'margin:0' }, m.icon + ' ' + m.name),
          el('div', { class: 'small muted', style: 'margin:.2rem 0' }, m.desc),
          el('div', { class: 'small' }, T('Abre: ', 'Opens: ', 'Abre: '), m.panels.join(' · ')),
          blocked ? el('div', { class: 'small', style: 'color:#b8860b' }, T('Precisa do editor de código no browser: ligue-o no passo 5 · Opções.', 'It needs the in-browser code editor: turn it on in step 5 · Options.', 'Necesita el editor de código en el navegador: actívalo en el paso 5 · Opciones.')) : '')));
  };
  const presets = el('div', { class: 'row', style: 'gap:.4rem;flex-wrap:wrap;align-items:center;margin:.4rem 0' },
    el('span', { class: 'small muted' }, T('Pré-marcar:', 'Pre-select:', 'Preseleccionar:')),
    ...PRESETS().map((p) => el('button', { class: 'btn ghost small', title: p.hint, onclick: () => {
      Object.entries(checks).forEach(([id, cb]) => { cb.checked = !cb.disabled && p.mods.includes(id); }); sync();
      msg.textContent = T(`preset «${p.name}»: `, `preset "${p.name}": `, `preset "${p.name}": `) + p.hint;
    } }, p.name)));

  const root = el('div', { class: 'section' },
    el('h2', {}, T('7 · Módulos ', '7 · Modules ', '7 · Módulos '), el('span', { class: 'small muted' }, T('(opcional)', '(optional)', '(opcional)'))),
    el('p', { class: 'muted small' },
      T('Um módulo é um grupo de recursos que este contest usa. Sem nenhum, o painel do admin mostra só o comum: problemas, contas, sessões, placar, staff e juízes. Ligar mostra os painéis, as checagens e os cartões correspondentes; tudo pode ser ligado ou desligado depois em Central › Módulos, sem perder dado.',
        'A module is a group of features this contest uses. With none, the admin panel shows only the common part: problems, accounts, sessions, scoreboard, staff and judges. Turning one on shows the matching panels, checks and cards; everything can be turned on or off later in Home › Modules, without losing data.',
        'Un módulo es un grupo de funciones que usa esta competencia. Sin ninguno, el panel del admin muestra solo lo común: problemas, cuentas, sesiones, marcador, staff y jueces. Activar uno muestra los paneles, las verificaciones y las tarjetas correspondientes; todo se puede activar o desactivar después en Central › Módulos, sin perder datos.')),
    presets, msg,
    el('div', { class: 'tcards' }, ...MODULES().map(card)));
  return { el: root };
}
