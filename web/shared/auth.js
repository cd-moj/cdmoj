// shared/auth.js — login/status/logout sobre a API.
import { apiPost, apiGet, setToken, clearToken, getToken } from './api.js';
import { startStaffAlert } from './staff-alert.js';

export { getToken };

export async function login(contest, username, password) {
  const j = await apiPost('/auth/login?contest=' + encodeURIComponent(contest),
                          { username, password }, { contest });
  if (j.token) setToken(contest, j.token);
  return j;
}

// status(contest, {alerts}) — `alerts:false` p/ página PROJETADA ou embutida (revelação, telão do
// Animeitor, janela de editor), onde o banner da organização não pode aparecer.
export async function status(contest, opts = {}) {
  if (!getToken(contest)) return { logged_in: false };
  try {
    const st = await apiGet('/auth/status?contest=' + encodeURIComponent(contest),
                            { contest, auth: true });
    // chokepoint de auth: liga o alerta global da organização (juiz/chefe/admin/.mon: clarification sem
    // resposta, voto pendente, conflito) em QUALQUER página que consulta o status (best-effort, idempotente).
    try { startStaffAlert(contest, st, opts); } catch { /* alerta é opcional */ }
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
