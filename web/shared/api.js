// shared/api.js — cliente da API MOJ v1 (fetch + Bearer + envelope).
import './contest-guard.js';   // isolamento por subdomínio (roda em toda página que usa a API)
export const API_BASE = '/api/v1';

export class ApiError extends Error {
  constructor(status, message, code) { super(message); this.status = status; this.code = code; }
}

// --- token por contest (localStorage) -------------------------------------
const tkey = (c) => 'moj_token_' + (c || 'treino');
export const getToken   = (c) => localStorage.getItem(tkey(c)) || '';
export const setToken   = (c, t) => localStorage.setItem(tkey(c), t);
export const clearToken = (c) => localStorage.removeItem(tkey(c));

function authHeaders(contest) {
  const t = getToken(contest);
  return t ? { 'Authorization': 'Bearer ' + t } : {};
}

async function unwrap(r) {
  let j;
  try { j = await r.json(); }
  catch { throw new ApiError(r.status, 'Resposta inválida do servidor'); }
  if (!r.ok || j.success === false) {
    const err = j && j.error ? j.error : {};
    throw new ApiError(r.status, err.message || ('HTTP ' + r.status), err.code);
  }
  return j;
}

// GET JSON (envelope desempacotado)
export async function apiGet(path, { contest, auth = false } = {}) {
  const r = await fetch(API_BASE + path, { headers: auth ? authHeaders(contest) : {} });
  return unwrap(r);
}
// GET texto cru (histórico, placar)
export async function apiGetText(path, { contest, auth = false } = {}) {
  const r = await fetch(API_BASE + path, { headers: auth ? authHeaders(contest) : {} });
  if (!r.ok) throw new ApiError(r.status, 'HTTP ' + r.status);
  return r.text();
}
// POST JSON
export async function apiPost(path, body, { contest, auth = false } = {}) {
  const r = await fetch(API_BASE + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(auth ? authHeaders(contest) : {}) },
    body: JSON.stringify(body || {}),
  });
  return unwrap(r);
}
