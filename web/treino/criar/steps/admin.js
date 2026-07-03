// steps/admin.js — passo 4: conta admin do contest (obrigatória; sufixo .admin forçado no servidor).
import { el } from '/shared/ui.js';

export function makeStepAdmin(ctx) {
  const a = ctx.draft.admin;
  const aLogin = el('input', { value: a.login || '', placeholder: 'login do admin (terá sufixo .admin)' });
  aLogin.addEventListener('input', () => { a.login = aLogin.value; });
  const aPass = el('input', { value: a.password || '', placeholder: '(gerada se vazio)' });
  aPass.addEventListener('input', () => { a.password = aPass.value; });
  const aName = el('input', { value: a.fullname || '', placeholder: 'nome do admin' });
  aName.addEventListener('input', () => { a.fullname = aName.value; });
  const aGen = el('button', { class: 'btn ghost', onclick: async () => { const pw = await ctx.genPasswords(1); if (pw[0]) { aPass.value = pw[0]; a.password = pw[0]; } } }, 'gerar');
  const root = el('div', { class: 'section' },
    el('h2', {}, '4 · Admin do contest ', el('span', { class: 'small muted' }, '(obrigatório)')),
    el('p', { class: 'muted small' }, 'Conta exclusiva para administrar o contest (sempre criada, mesmo no modo compartilhado; conta .admin já existente é reutilizada sem trocar a senha).'),
    el('div', { class: 'grid2' },
      el('div', { class: 'field' }, el('label', {}, 'Login'), aLogin),
      el('div', { class: 'field' }, el('label', {}, 'Nome'), aName)),
    el('div', { class: 'field' }, el('label', {}, 'Senha'), el('div', { class: 'row' }, aPass, aGen)));
  return { el: root };
}
