// cadastro.js — cadastro web-first do treino livre, confirmado pelo Telegram.
// Fluxo: POST /treino/signup/start -> {nonce, deep_link} -> abre o bot -> poll
// GET /treino/signup/status?nonce=… até created|already_linked|linked|expired.
// A SENHA nunca chega aqui: é entregue por DM do bot (posse do Telegram = prova).
import { apiPost, apiGet } from '/shared/api.js';
import { renderAuthArea } from '/shared/ui.js';
import { T } from '/shared/i18n.js';

const $ = (id) => document.getElementById(id);
let pollTimer = null;

// preenche o #authArea do topbar compartilhado (login/chip do usuário), como as demais páginas
const authMount = $('authArea');
if (authMount) renderAuthArea(authMount, 'treino', () => location.reload());

function showResult(cls, html) {
  const r = $('result');
  r.className = 'msg ' + cls;
  r.innerHTML = html;
  r.classList.remove('hidden');
}

async function poll(nonce) {
  let j;
  try { j = await apiGet('/treino/signup/status?nonce=' + encodeURIComponent(nonce)); }
  catch { return; }                       // erro transitório: tenta de novo no próximo tick
  const st = j.status;
  if (st === 'pending') return;           // segue aguardando
  clearInterval(pollTimer); pollTimer = null;
  $('step2').classList.add('hidden');
  if (st === 'created') {
    showResult('ok', T(`Conta criada! Seu login é <b>${j.login}</b>. Enviamos a senha por mensagem privada no Telegram. <br><a href="/treino/">Ir para o login →</a>`,
      `Account created! Your login is <b>${j.login}</b>. We sent your password via private message on Telegram. <br><a href="/treino/">Go to login →</a>`));
  } else if (st === 'linked') {
    showResult('ok', T(`Telegram vinculado à conta <b>${j.login}</b>.`, `Telegram linked to account <b>${j.login}</b>.`));
  } else if (st === 'already_linked') {
    showResult('info', T(`Você já tem uma conta: <b>${j.login}</b>. Se esqueceu a senha, envie <code>/trocarsenha</code> ao bot no Telegram.`,
      `You already have an account: <b>${j.login}</b>. If you forgot your password, send <code>/trocarsenha</code> to the bot on Telegram.`));
  } else { // expired / desconhecido
    showResult('err', T('O link de confirmação expirou. Recarregue a página e tente de novo.', 'The confirmation link expired. Reload the page and try again.'));
  }
}

$('form').addEventListener('submit', async (e) => {
  e.preventDefault();
  $('submit').disabled = true;
  const body = {
    fullname: $('fullname').value.trim(),
    login: $('login').value.trim(),
    university: $('university').value.trim(),
  };
  try {
    const j = await apiPost('/treino/signup/start', body);
    const a = $('deeplink');
    a.href = j.deep_link;
    $('step2').classList.remove('hidden');
    a.focus();
    pollTimer = setInterval(() => poll(j.nonce), 2500);
    poll(j.nonce);
  } catch (err) {
    $('submit').disabled = false;
    const code = err.code || '';
    const msg = code === 'login_taken' ? T('Esse login já está em uso — escolha outro.', 'This login is already taken — choose another.')
      : code === 'login_reserved' ? T('Esse login não é permitido.', 'This login is not allowed.')
      : code === 'login_invalid' ? T('Login inválido (2–32 caracteres: letras, números, . _ -).', 'Invalid login (2–32 characters: letters, numbers, . _ -).')
      : code === 'store_not_v2' ? T('O cadastro está temporariamente indisponível.', 'Sign up is temporarily unavailable.')
      : (err.message || T('Falha ao iniciar o cadastro.', 'Failed to start sign up.'));
    showResult('err', msg);
  }
});
