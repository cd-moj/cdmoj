// steps/visual.js — passo 6: cores dos balões, países/escolas e regiões do placar
// (editores compartilhados; locale/login/freeze ficam no passo Opções). Instâncias cacheadas.
import { el } from '/shared/ui.js';
import { makeColorsEditor, makeTeamsEditor, makeRegionsEditor } from '/shared/contest-config/index.js';

export function makeStepVisual(ctx) {
  const d = ctx.draft;
  const currentLetters = () => d.problems.map((p, i) => (p._letter && /^[A-Za-z0-9]{1,3}$/.test(p._letter)) ? p._letter : autoLetter(i));
  if (!ctx.editors.colors) ctx.editors.colors = makeColorsEditor({ letters: currentLetters(), initial: d.visual.colors || {} });
  if (!ctx.editors.regions) ctx.editors.regions = makeRegionsEditor({ initial: d.visual.regions || [] });

  const teamsMount = el('div', {}, el('p', { class: 'muted small' }, 'carregando seletor de bandeiras…'));
  if (ctx.editors.teams) { teamsMount.innerHTML = ''; teamsMount.append(ctx.editors.teams.el); }
  else {
    // preview de matches contra os usuários já preenchidos no passo 3 (compartilhado: sem lista)
    const logins = d.userMode === 'own' ? (d.users || []).map((u) => u.login).filter(Boolean) : [];
    makeTeamsEditor({ initial: d.visual.teams_meta || [], logins })
      .then((edt) => { ctx.editors.teams = edt; teamsMount.innerHTML = ''; teamsMount.append(edt.el); })
      .catch(() => { teamsMount.innerHTML = ''; teamsMount.append(el('p', { class: 'small error-box' }, 'falha ao carregar bandeiras')); });
  }

  const hh = (t) => el('h3', { style: 'margin:1rem 0 .3rem' }, t);
  const root = el('div', { class: 'section' },
    el('h2', {}, '6 · Visual e placar ', el('span', { class: 'small muted' }, '(opcional)')),
    hh('🎈 Cores dos balões'),
    el('div', {}, el('button', { class: 'btn ghost', style: 'margin-bottom:.3rem', onclick: () => ctx.editors.colors.setLetters(currentLetters()) }, '↻ sincronizar com os problemas')),
    ctx.editors.colors.el,
    hh('🏳️ Países e escolas (bandeira/sigla por regex no login)'), teamsMount,
    hh('🔎 Filtros de região do placar'), ctx.editors.regions.el);
  return { el: root };
}

function autoLetter(i) {
  if (i < 26) return String.fromCharCode(65 + i);
  return String.fromCharCode(65 + Math.floor(i / 26) - 1) + String.fromCharCode(65 + (i % 26));
}
