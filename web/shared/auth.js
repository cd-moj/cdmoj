// shared/auth.js — login/status/logout sobre a API.
import { apiPost, apiGet, setToken, clearToken, getToken } from './api.js';

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
    return await apiGet('/auth/status?contest=' + encodeURIComponent(contest),
                        { contest, auth: true });
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
