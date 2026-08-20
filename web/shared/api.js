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
// GET texto cru + os CABEÇALHOS da resposta. O /contest/score responde `X-MOJ-Frozen: 0|1`:
// só o servidor sabe qual dos dois placares (congelado × completo) acabou de escolher para
// este login, e é isso que a página usa p/ avisar o competidor. Quem recebe o completo (juiz,
// telão, SCORE_FULL_USERS) recebe 0.
export async function apiGetTextMeta(path, { contest, auth = false } = {}) {
  const r = await fetch(API_BASE + path, { headers: auth ? authHeaders(contest) : {} });
  if (!r.ok) throw new ApiError(r.status, 'HTTP ' + r.status);
  return { text: await r.text(), headers: r.headers };
}
// GET texto cru (histórico, placar)
export async function apiGetText(path, opts = {}) {
  return (await apiGetTextMeta(path, opts)).text;
}
// GET binário (enunciado em PDF): texto corromperia os bytes
export async function apiGetBlob(path, { contest, auth = false } = {}) {
  const r = await fetch(API_BASE + path, { headers: auth ? authHeaders(contest) : {} });
  if (!r.ok) throw new ApiError(r.status, 'HTTP ' + r.status);
  return r.blob();
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
