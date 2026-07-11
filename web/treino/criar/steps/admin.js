// steps/admin.js — passo 4: conta admin do contest (obrigatória; sufixo .admin forçado no servidor).
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';

export function makeStepAdmin(ctx) {
  const a = ctx.draft.admin;
  const aLogin = el('input', { value: a.login || '', placeholder: T('login do admin (terá sufixo .admin)', 'admin login (will get the .admin suffix)') });
  aLogin.addEventListener('input', () => { a.login = aLogin.value; });
  const aPass = el('input', { value: a.password || '', placeholder: T('(gerada se vazio)', '(generated if empty)') });
  aPass.addEventListener('input', () => { a.password = aPass.value; });
  const aName = el('input', { value: a.fullname || '', placeholder: T('nome do admin', 'admin name') });
  aName.addEventListener('input', () => { a.fullname = aName.value; });
  const aGen = el('button', { class: 'btn ghost', onclick: async () => { const pw = await ctx.genPasswords(1); if (pw[0]) { aPass.value = pw[0]; a.password = pw[0]; } } }, T('gerar', 'generate'));
  const root = el('div', { class: 'section' },
    el('h2', {}, T('4 · Admin do contest ', '4 · Contest admin '), el('span', { class: 'small muted' }, T('(obrigatório)', '(required)'))),
    el('p', { class: 'muted small' }, T('Conta exclusiva para administrar o contest (sempre criada, mesmo no modo compartilhado; conta .admin já existente é reutilizada sem trocar a senha).', 'Account dedicated to administering the contest (always created, even in shared mode; an existing .admin account is reused without changing its password).')),
    el('div', { class: 'grid2' },
      el('div', { class: 'field' }, el('label', {}, T('Login', 'Login')), aLogin),
      el('div', { class: 'field' }, el('label', {}, T('Nome', 'Name')), aName)),
    el('div', { class: 'field' }, el('label', {}, T('Senha', 'Password')), el('div', { class: 'row' }, aPass, aGen)));
  return { el: root };
}
