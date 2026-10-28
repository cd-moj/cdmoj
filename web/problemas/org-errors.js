// problemas/org-errors.js — o texto (pt/en/es) dos erros de CRIAR org que vêm com código próprio:
// `name_is_login` (o nome é o login de uma conta — a org pessoal dela) e `implicit` (org pessoal não tem gestão).
// A mensagem do servidor é só PT; o resto cai nela. Usado por problemas.js (aba Orgs) e editar.js (nova org).
import { T } from '/shared/i18n.js';

export function orgCreateErr(e) {
  if (e && e.code === 'name_is_login') return T('Esse nome é o login de uma conta do treino (a org pessoal dela). Escolha outro nome.', 'That name is the login of a training account (its personal org). Choose another name.', 'Ese nombre es el login de una cuenta del entrenamiento (su org personal). Elige otro nombre.');
  if (e && e.code === 'implicit') return T('Essa é uma org pessoal: ela não aceita gestão de membros.', 'That is a personal org: it does not accept member management.', 'Esa es una org personal: no acepta gestión de miembros.');
  return (e && e.message) || String(e);
}
