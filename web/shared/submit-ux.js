// shared/submit-ux.js — o ENVIO de solução pela web (contest, janela ⧉ só-editor e treino), SEM pop-up
// (decisão do Ribas, 01/10/2026; relatos de 28–29/09: o "enviado" cinza e fraco, 10 cliques = 10 julgamentos,
// mouse travando sem saber se foi). O estado mora no BOTÃO e numa linha de status ao lado dele:
//   idle → sending (roda + "Enviando…", só enquanto a requisição está no ar; começa NO CLIQUE, antes de ler
//          o arquivo — era a janela do clique duplo)
//        → sent ("✓ Enviado" verde por SENT_MS, cliques ignorados) → idle.
//   Código IGUAL ao último enviado daquele problema + linguagem (hash no localStorage) ⇒ o 1º clique só ARMA:
//   o botão fica âmbar ("Mesmo código do envio das 14:03 — enviar de novo?") por CONFIRM_MS e o 2º clique envia.
//   O servidor NÃO barra conteúdo: há quem reenvie o mesmo código de propósito (heurística aleatória).
// O estado é POR PROBLEMA: os botões ligados ao mesmo fluxo (a linha e o editor do contest) compartilham a
// máquina — clique num enquanto o outro envia é ignorado. A lógica (makeSubmitFlow, codeHash, submitErrorText)
// não toca no DOM e é testada no gjs (server/test/smoke-submit-ux.gjs.sh); o DOM fica em attachSubmitButton.
// Strings sempre pelo T() NA HORA (nunca no topo do módulo: congelaria o idioma antes do LOCALE do contest).
import { el } from '/shared/dom.js';
import { T, uiLocale } from '/shared/i18n.js';

export const SENT_MS = 1500, CONFIRM_MS = 5000;

// cyrb53 — "é o mesmo código?" é comparação LOCAL, não segurança: uma colisão custaria só um 2º clique.
// Síncrono de propósito (o crypto.subtle só existe em contexto seguro e é assíncrono).
export function codeHash(lang, codeB64) {
  const s = String(lang || '').toLowerCase() + '\n' + String(codeB64 || '');
  let h1 = 0xdeadbeef, h2 = 0x41c6ce57;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    h1 = Math.imul(h1 ^ c, 2654435761); h2 = Math.imul(h2 ^ c, 1597334677);
  }
  h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
  h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);
  return (4294967296 * (2097151 & h2) + (h1 >>> 0)).toString(36);
}

// memória do último envio com sucesso, por contest + login + problema (a janela ⧉ e a página principal são a
// mesma origem: um envio numa arma o "mesmo código" na outra). localStorage pode faltar ou lançar (aba
// privada, armazenamento cheio): sem memória, o envio segue normal.
export function lastSubKey(contest, login, problem) { return 'moj_lastsub:' + [contest || '', login || '', problem || ''].join('|'); }
function defaultStorage() { try { return globalThis.localStorage || null; } catch { return null; } }
function readLast(storage, key) {
  try { const j = JSON.parse((storage && storage.getItem(key)) || 'null'); return j && j.h ? j : null; } catch { return null; }
}
function writeLast(storage, key, rec) { try { if (storage) storage.setItem(key, JSON.stringify(rec)); } catch { /* sem memória */ } }

// makeSubmitFlow({key, send}) — a máquina de estados de UM problema.
//   click(by, prepare): `by` = quem clicou (cada botão é um), `prepare()` = async → {payload, lang} ou lança
//   Error(mensagem) (validação: editor vazio, arquivo fora da lista…). Devolve {kind}: ignored | invalid |
//   confirm | sent | error. `send(payload)` faz o POST e devolve a resposta.
export function makeSubmitFlow({ key, send, storage = defaultStorage(), now = () => Date.now(),
  setTimer = (f, ms) => setTimeout(f, ms), clearTimer = (t) => clearTimeout(t) } = {}) {
  let state = 'idle', src = null, armedAt = 0, timer = null;
  const subs = new Set();
  const set = (s, by = null, at = 0) => {
    state = s; src = by; armedAt = at;
    for (const f of subs) { try { f(state, src); } catch { /* quem ouve cuida */ } }
  };
  const stopTimer = () => { if (timer != null) { clearTimer(timer); timer = null; } };
  async function click(by, prepare) {
    if (state === 'sending' || state === 'sent') return { kind: 'ignored' };
    const force = state === 'confirm' && src === by;      // 2º clique NO MESMO botão, dentro da janela
    stopTimer(); set('sending', by);
    let prep;
    try { prep = await prepare(); } catch (e) { set('idle'); return { kind: 'invalid', message: (e && e.message) || String(e) }; }
    const h = codeHash(prep.lang, prep.payload && prep.payload.code_b64), last = readLast(storage, key);
    if (!force && last && last.h === h) {
      set('confirm', by, last.at || 0);
      timer = setTimer(() => { timer = null; if (state === 'confirm') set('idle'); }, CONFIRM_MS);
      return { kind: 'confirm', at: last.at || 0 };
    }
    let resp;
    try { resp = await send(prep.payload); } catch (error) { set('idle'); return { kind: 'error', error }; }
    // a hora do SERVIDOR (a mesma da linha de status): máquina de prova com relógio torto não desencontra as duas
    const ep = resp && Number(resp.epoch);
    writeLast(storage, key, { h, lang: prep.lang || '', at: ep > 0 ? ep * 1000 : now() });
    set('sent', by);
    timer = setTimer(() => { timer = null; if (state === 'sent') set('idle'); }, SENT_MS);
    return { kind: 'sent', resp, prep };
  }
  return { click, onChange(f) { subs.add(f); return () => subs.delete(f); },
    get state() { return state; }, get source() { return src; }, get armedAt() { return armedAt; } };
}

const hhmm = (ms) => new Date(ms).toLocaleTimeString(uiLocale(), { hour: '2-digit', minute: '2-digit' });
const hhmmss = (ms) => new Date(ms).toLocaleTimeString(uiLocale(), { hour: '2-digit', minute: '2-digit', second: '2-digit' });

// texto do erro de um envio. 429 submit_busy = o teto de envios na fila (treino e listas); sem status (rede) ou
// 502/503/504 sem código = o servidor pode ter recebido: manda conferir antes de reenviar (nunca "nada foi enviado").
export function submitErrorText(e) {
  const code = e && e.code, st = e && e.status;
  if (code === 'submit_busy') {
    const n = (e.data && e.data.inflight) || 3;
    return T(`Você já tem ${n} envios esperando o veredicto — espere sair um resultado para enviar de novo.`,
      `You already have ${n} submissions waiting for a verdict — wait for a result before submitting again.`,
      `Ya tienes ${n} envíos esperando el veredicto: espera un resultado para enviar de nuevo.`);
  }
  if (!code && (st == null || st === 502 || st === 503 || st === 504)) {
    return T('O servidor não respondeu. Confira a lista de envios antes de enviar de novo.',
      'The server did not respond. Check your submissions list before you submit again.',
      'El servidor no respondió. Revisa tu lista de envíos antes de enviar de nuevo.');
  }
  return T('Erro: ', 'Error: ', 'Error: ') + ((e && e.message) || T('falha ao enviar', 'failed to submit', 'no se pudo enviar'));
}

// liga o className sem classList (o DOM falso dos testes não tem)
function setCls(n, on) {
  const have = new Set(String(n.className || '').split(/\s+/).filter(Boolean));
  for (const [c, v] of Object.entries(on)) { if (v) have.add(c); else have.delete(c); }
  n.className = [...have].join(' ');
}

// attachSubmitButton(flow, btn, statusEl, {prepare, label, describe, hint, onSent})
//   label(): rótulo de repouso (função: o T() vale no idioma da hora); describe(r): o que foi enviado ("A · C++");
//   hint(): onde acompanhar (texto ou nó); onSent(resp, prep): a página atualiza a lista na hora.
export function attachSubmitButton(flow, btn, statusEl, { prepare, label, describe, hint, onSent } = {}) {
  const me = {};
  if (statusEl) { statusEl.setAttribute('role', 'status'); statusEl.setAttribute('aria-live', 'polite'); }
  const paint = () => {
    const s = flow.state, mine = flow.source === me;
    const busy = s === 'sending' || s === 'sent';
    setCls(btn, { 'is-busy': busy, 'is-sending': s === 'sending' && mine, 'is-sent': s === 'sent' && mine,
      'is-confirm': s === 'confirm' && mine });
    btn.setAttribute('aria-disabled', busy ? 'true' : 'false');
    btn.setAttribute('aria-busy', s === 'sending' && mine ? 'true' : 'false');
    btn.textContent = '';
    if (s === 'sending' && mine) btn.append(el('span', { class: 'spin', 'aria-hidden': 'true' }), ' ' + T('Enviando…', 'Sending…', 'Enviando…'));
    else if (s === 'sent' && mine) btn.append('✓ ' + T('Enviado', 'Sent', 'Enviado'));
    else if (s === 'confirm' && mine) {
      const t = hhmm(flow.armedAt || Date.now());
      btn.append(T(`Mesmo código do envio das ${t} — enviar de novo?`, `Same code as the ${t} submission — submit again?`,
        `Mismo código que el envío de las ${t}: ¿enviar de nuevo?`));
    } else btn.append(label ? label() : T('Enviar', 'Submit', 'Enviar'));
  };
  const say = (node) => { if (!statusEl) return; statusEl.textContent = ''; if (node) statusEl.append(node); };
  flow.onChange((s) => { if (s === 'sending') say(null); paint(); });
  btn.addEventListener('click', async () => {
    if (flow.state === 'sending' || flow.state === 'sent') return;
    const r = await flow.click(me, prepare);
    if (r.kind === 'invalid') say(el('span', { class: 'error-box' }, r.message));
    else if (r.kind === 'error') say(el('span', { class: 'error-box' }, submitErrorText(r.error)));
    else if (r.kind === 'sent') {
      const ep = r.resp && Number(r.resp.epoch);
      const what = describe ? describe(r) : '';
      const h = hint ? hint() : '';
      say(el('span', { class: 'submit-ok' }, '✓ ' + T('Enviado às ', 'Submitted at ', 'Enviado a las ')
        + hhmmss(ep > 0 ? ep * 1000 : Date.now()) + (what ? ' — ' + what : ''), h ? ' · ' : '', h || ''));
      if (onSent) { try { onSent(r.resp, r.prep); } catch { /* a página cuida */ } }
    }
  });
  paint();
  return { paint };
}

// aviso entre janelas da MESMA origem (a ⧉ só-editor avisa a página principal, que recarrega a tabela).
// Sem BroadcastChannel (navegador antigo) não avisa — a tabela segue no poll de sempre.
export function submitChannel(contest) {
  let ch = null;
  try { ch = typeof BroadcastChannel === 'function' ? new BroadcastChannel('moj-submit-' + (contest || '')) : null; } catch { ch = null; }
  return {
    post(msg) { try { if (ch) ch.postMessage(msg); } catch { /* */ } },
    listen(fn) { if (ch) ch.onmessage = (ev) => { try { fn(ev.data || {}); } catch { /* */ } }; },
  };
}
