// cadastro.js — cadastro web-first do treino livre, confirmado pelo Telegram.
// Fluxo: POST /treino/signup/start -> {nonce, deep_link} -> abre o bot -> poll
// GET /treino/signup/status?nonce=… até created|already_linked|linked|expired.
// A SENHA nunca chega aqui: é entregue por DM do bot (posse do Telegram = prova).
import { apiPost, apiGet } from '/shared/api.js';
import { renderAuthArea } from '/shared/ui.js';

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
    showResult('ok', `Conta criada! Seu login é <b>${j.login}</b>. Enviamos a senha por mensagem privada no Telegram. ` +
      `<br><a href="/treino/">Ir para o login →</a>`);
  } else if (st === 'linked') {
    showResult('ok', `Telegram vinculado à conta <b>${j.login}</b>.`);
  } else if (st === 'already_linked') {
    showResult('info', `Você já tem uma conta: <b>${j.login}</b>. Se esqueceu a senha, envie <code>/trocarsenha</code> ao bot no Telegram.`);
  } else { // expired / desconhecido
    showResult('err', 'O link de confirmação expirou. Recarregue a página e tente de novo.');
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
    const msg = code === 'login_taken' ? 'Esse login já está em uso — escolha outro.'
      : code === 'login_reserved' ? 'Esse login não é permitido.'
      : code === 'login_invalid' ? 'Login inválido (2–32 caracteres: letras, números, . _ -).'
      : code === 'store_not_v2' ? 'O cadastro está temporariamente indisponível.'
      : (err.message || 'Falha ao iniciar o cadastro.');
    showResult('err', msg);
  }
});
