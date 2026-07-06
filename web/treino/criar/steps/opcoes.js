// steps/opcoes.js — passo 5: TODAS as opções do contest (o MESMO settings-editor da aba
// Configurações do admin — paridade real), + prioridade de julgamento (só na criação).
// A instância fica cacheada em ctx.editors.settings: navegar não perde o que foi mexido,
// e o buildSpec lê getValue() dela.
import { el } from '/shared/ui.js';
import { makeSettingsEditor } from '/shared/contest-config/index.js';

export function makeStepOpcoes(ctx) {
  if (!ctx.editors.settings) {
    ctx.editors.settings = makeSettingsEditor({ value: ctx.draft.opts, mode: 'create', isAdmin: !!ctx.perm.is_admin, contestMode: ctx.draft.mode });
  }
  // o usuário pode voltar ao passo Dados e trocar o modo — ressincroniza a seção de penalidade
  ctx.editors.settings.setContestMode?.(ctx.draft.mode);
  const root = el('div', { class: 'section' },
    el('h2', {}, '5 · Opções ', el('span', { class: 'small muted' }, '(as mesmas da aba Configurações do admin)')),
    ctx.editors.settings.el);
  return { el: root };
}
