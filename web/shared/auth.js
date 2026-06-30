// shared/auth.js — login/status/logout sobre a API.
import { apiPost, apiGet, setToken, clearToken, getToken } from './api.js';
import { startChiefAlert } from './chief-alert.js';

export { getToken };

export async function login(contest, username, password) {
  const j = await apiPost('/auth/login?contest=' + encodeURIComponent(contest),
                          { username, password }, { contest });
  if (j.token) setToken(contest, j.token);
  return j;
}

export async function status(contest) {
  if (!getToken(contest)) return { logged_in: false };
  try {
    const st = await apiGet('/auth/status?contest=' + encodeURIComponent(contest),
                            { contest, auth: true });
    // chokepoint de auth: liga o alerta global de conflito p/ chief/admin em QUALQUER página
    // que consulta o status (best-effort, idempotente — não falha o status se algo der errado).
    try { startChiefAlert(contest, st); } catch { /* alerta é opcional */ }
    return st;
  } catch { return { logged_in: false }; }
}

export async function logout(contest) {
  try { await apiPost('/auth/logout', {}, { contest, auth: true }); } catch {}
  clearToken(contest);
}

// utilitário: lê arquivo -> base64 (sem o prefixo data:)
export function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const fr = new FileReader();
    fr.onload = () => resolve(String(fr.result).split(',')[1] || '');
    fr.onerror = reject;
    fr.readAsDataURL(file);
  });
}
export function textToBase64(text) {
  return btoa(unescape(encodeURIComponent(text)));
}
