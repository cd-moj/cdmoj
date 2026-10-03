#!/bin/bash
# smoke-staff-alert.gjs.sh — o alerta GLOBAL da organização (web/shared/staff-alert.js), com o módulo REAL,
# DOM/relógio/áudio/Web Locks/BroadcastChannel falsos. Substitui o smoke-chief-alert-hidden.gjs.sh (o alerta
# de conflito virou um caso deste). O que se prova:
#   · quem recebe: juiz/chefe/admin/.mon sim; time, treino e página com alerts:false não pedem nada;
#   · ritmo: 8–12 s com aba visível, 30–40 s oculta; voltar a ficar visível consulta na hora; um poke com
#     outro poll em voo não duplica a cadeia de timers; 401/403 PARA o poll;
#   · banner + "(N)" no título; 1ª fotografia NÃO toca (abrir página não bipa); chegada nova toca o som do
#     tipo; mudo não toca; áudio bloqueado mostra "ativar som" e um gesto o libera; lembrete em 2 min;
#   · DUAS abas: só a líder (Web Locks) consulta; a outra recebe pelo canal; o poke da seguidora faz a
#     líder consultar; a líder fechou ⇒ a outra assume.
# Sem gjs: pula (rc 0).
set -u
command -v gjs >/dev/null 2>&1 || { echo "staff-alert: gjs ausente — pulando"; exit 0; }
WEB="$(cd "$(dirname "$(readlink -f "$0")")/../../web" && pwd)"
SRC="$(sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$WEB/shared/staff-alert.js")"
[[ "$SRC" == *"function startStaffAlert"* ]] || { echo "FAIL: startStaffAlert não encontrado"; exit 1; }
gjs -c "
let pass = 0, fail = 0;
const ck = (msg, ok, dbg) => { if (ok) { print('  ok: ' + msg); pass++; } else { print('  FAIL: ' + msg + ' :: ' + (dbg === undefined ? '' : JSON.stringify(dbg))); fail++; } };
const flush = async () => { for (let i = 0; i < 30; i++) await Promise.resolve(); };
let NOW = 1000000; Date.now = () => NOW;

// ---- DOM mínimo -------------------------------------------------------------------------------
function El(tag){ this.tag = tag; this.children = []; this.classList = { _s:new Set(), add(c){ this._s.add(c); }, remove(c){ this._s.delete(c); }, has(c){ return this._s.has(c); } };
  this.attrs = {}; this._text = ''; this.className = ''; this.onclick = null; }
El.prototype.setAttribute = function(k, v){ this.attrs[k] = v; };
El.prototype.appendChild = function(c){ this.children.push(c); return c; };
Object.defineProperty(El.prototype, 'textContent', { get(){ return this._text + this.children.map(c => c.textContent).join(' '); }, set(v){ this._text = v; this.children = []; } });
function mkDoc(){
  const ids = {};
  const d = { hidden:false, visibilityState:'visible', title:'Contest — MOJ', LIS:{},
    head:new El('head'), body:new El('body'),
    getElementById:(id) => ids[id] || null,
    createElement:(t) => new El(t),
    addEventListener(t, f){ (this.LIS[t] = this.LIS[t] || []).push(f); },
    fire(t){ (this.LIS[t] || []).forEach(f => f({})); } };
  const reg = (parent) => { const o = parent.appendChild; parent.appendChild = function(c){ if (c.id) ids[c.id] = c; return o.call(this, c); }; };
  reg(d.head); reg(d.body);
  return d;
}
const setVis = (d, v) => { d.hidden = !v; d.visibilityState = v ? 'visible' : 'hidden'; };
// achar o banner e os botões
const bar = (d) => d.getElementById('mojStaffAlert');
const shown = (d) => { const b = bar(d); return !!(b && b.classList.has('show')); };
const btnText = (d) => { const b = bar(d); return b ? b.children.map(c => c._text) : []; };

// ---- timers falsos (por aba) ------------------------------------------------------------------
function mkTimers(){
  const TIM = new Map(); let tid = 0;
  return { TIM,
    setTimeout:(fn, ms) => { TIM.set(++tid, { fn, ms, at:NOW + (ms || 0) }); return tid; },
    clearTimeout:(id) => { TIM.delete(id); },
    setInterval:(fn, ms) => { TIM.set(++tid, { fn, ms, at:NOW + ms, every:true }); return tid; } };
}
// roda os timers que vencem até NOW (os de intervalo se reagendam)
const runDue = (tm) => { for (const [id, t] of [...tm.TIM.entries()].sort((a, b) => a[1].at - b[1].at)) {
  if (t.at > NOW) continue; if (t.every) t.at += t.ms; else tm.TIM.delete(id); t.fn(); } };
const pollTimers = (tm) => [...tm.TIM.values()].filter(t => !t.every);

// ---- áudio falso ------------------------------------------------------------------------------
let TONES = 0;
function AC(){ this.state = 'suspended'; this.currentTime = 0; this.destination = {}; AC.made++; }
AC.made = 0;
AC.prototype.resume = function(){ this.state = 'running'; return Promise.resolve(); };
AC.prototype.createOscillator = function(){ return { type:'', frequency:{ value:0 }, connect(){}, start(){ TONES++; }, stop(){} }; };
AC.prototype.createGain = function(){ return { gain:{ value:0, setValueAtTime(){}, exponentialRampToValueAtTime(){} }, connect(){} }; };

// ---- Web Locks + BroadcastChannel falsos, compartilhados entre as abas -------------------------
function mkCoord(){
  const holders = {}, queue = {}, chans = [];
  const locks = (tab) => ({ request(name, cb){ return new Promise(() => {
    const grant = () => { holders[name] = tab; cb(); };
    if (!holders[name]) grant(); else (queue[name] = queue[name] || []).push({ tab, grant }); }); } });
  const release = (tab) => { for (const n of Object.keys(holders)) if (holders[n] === tab) {
    delete holders[n]; const nx = (queue[n] || []).shift(); if (nx) nx.grant(); } };
  function BC(tab){ return function(name){ this.name = name; this.tab = tab; this.onmessage = null; chans.push(this);
    this.postMessage = (data) => { for (const c of chans) if (c !== this && c.name === name && c.onmessage && !c.tab.closed) {
      const msg = { data: JSON.parse(JSON.stringify(data)) }; Promise.resolve().then(() => c.onmessage(msg)); } }; }; }
  return { locks, release, BC };
}

// ---- uma 'aba' = o módulo avaliado com os globais dela ------------------------------------------
function mkTab(opts){
  const tab = { closed:false, calls:[], doc:mkDoc(), tm:mkTimers(), store:{} };
  tab.reply = (i, v) => tab.calls[i].res(v);
  tab.fail = (i, st) => tab.calls[i].rej(Object.assign(new Error('x'), { status:st }));
  const apiGet = (url) => { if (tab.closed) return new Promise(() => {}); let res, rej; const p = new Promise((a, b) => { res = a; rej = b; }); tab.calls.push({ url, res, rej }); return p; };
  const T = (pt) => pt;
  const document = tab.doc, setTimeout = tab.tm.setTimeout, clearTimeout = tab.tm.clearTimeout, setInterval = tab.tm.setInterval;
  const window = { AudioContext:AC, dispatchEvent(){}, focus(){} };
  const navigator = opts.coord ? { locks:opts.coord.locks(tab) } : {};
  const BroadcastChannel = opts.coord ? opts.coord.BC(tab) : undefined;
  const location = { pathname:'/contest/', href:'' };
  const localStorage = { getItem:(k) => (k in tab.store ? tab.store[k] : null), setItem:(k, v) => { tab.store[k] = String(v); }, removeItem:(k) => { delete tab.store[k]; } };
  const Notification = undefined;
  const CustomEvent = function(){};
  $SRC
  tab.start = (st, o) => startStaffAlert(opts.contest || 'c', st, o || {});
  tab.poke = pokeStaffAlert;
  return tab;
}
const SNAP = (unc, last, mine, mlast, conf) => ({ clar:{ open:unc, unclaimed:unc, last }, review:{ manual:true, quorum:2, needing:mine, mine_todo:mine, mine_last:mlast, conflicts:conf } });

async function main() {
  print('== quem recebe ==');
  { const t = mkTab({}); t.start({ logged_in:true, login:'aluno1' }); ck('time: nenhuma requisição', t.calls.length === 0); }
  { const t = mkTab({ contest:'treino' }); t.start({ logged_in:true, login:'x.admin', is_admin:true, is_judge:true }); ck('treino: nada (era o vazamento do .admin)', t.calls.length === 0); }
  { const t = mkTab({}); t.start({ logged_in:true, login:'j.judge', is_judge:true }, { alerts:false }); ck('alerts:false (telão/revelação/editor): nada', t.calls.length === 0); }
  { const t = mkTab({}); t.start({ logged_in:true, login:'m.mon' }); ck('.mon pelo sufixo do login: consulta', t.calls.length === 1 && /staff-alerts\?contest=c/.test(t.calls[0].url), t.calls.map(c => c.url)); }

  print('== ritmo, cadeia única, 403 (aba sozinha) ==');
  const a = mkTab({});
  a.start({ logged_in:true, login:'j1.judge', is_judge:true });
  ck('1º poll na largada', a.calls.length === 1);
  a.reply(0, SNAP(0, 0, 0, 0, null)); await flush();
  let pt = pollTimers(a.tm);
  ck('visível: próximo em 8–12 s', pt.length === 1 && pt[0].ms >= 8000 && pt[0].ms <= 12000, pt.map(t => t.ms));
  setVis(a.doc, false); NOW += 13000; runDue(a.tm);
  ck('timer venceu ⇒ 2º poll', a.calls.length === 2);
  a.reply(1, SNAP(0, 0, 0, 0, null)); await flush();
  pt = pollTimers(a.tm);
  ck('oculta: próximo em 30–40 s', pt.length === 1 && pt[0].ms >= 30000 && pt[0].ms <= 40000, pt.map(t => t.ms));
  NOW += 5000; setVis(a.doc, true); a.doc.fire('visibilitychange');
  ck('voltou a ficar visível: consulta na hora', a.calls.length === 3);
  a.poke();
  ck('poke com poll em voo: dispara outro', a.calls.length === 4);
  a.reply(2, SNAP(0, 0, 0, 0, null)); a.reply(3, SNAP(0, 0, 0, 0, null)); await flush();
  ck('…e sobra UMA cadeia de timers', pollTimers(a.tm).length === 1, pollTimers(a.tm).length);

  print('== banner, título e som ==');
  ck('nada pendente: sem banner, título intacto', !shown(a.doc) && a.doc.title === 'Contest — MOJ', a.doc.title);
  NOW += 13000; runDue(a.tm);
  TONES = 0;
  a.reply(4, SNAP(2, 500, 0, 0, null)); await flush();
  ck('clarification nova: banner + (2) no título', shown(a.doc) && a.doc.title === '(2) Contest — MOJ', [btnText(a.doc), a.doc.title]);
  ck('áudio ainda bloqueado: nenhum som e o botão ativar som', TONES === 0 && btnText(a.doc).some(s => /ativar som/.test(s)), btnText(a.doc));
  a.doc.fire('pointerdown'); await flush(); NOW += 400; runDue(a.tm);
  ck('gesto na página liberou o áudio (o botão some)', !btnText(a.doc).some(s => /ativar som/.test(s)) && AC.made >= 1, btnText(a.doc));
  NOW += 13000; runDue(a.tm);
  a.reply(5, SNAP(2, 500, 0, 0, null)); await flush();
  ck('mesma fotografia: não toca de novo', TONES === 0, TONES);
  NOW += 13000; runDue(a.tm);
  a.reply(6, SNAP(2, 700, 0, 0, null)); await flush();
  ck('outra chegou (mesma contagem, last maior): toca', TONES > 0, TONES);
  TONES = 0; NOW += 13000; runDue(a.tm);
  a.reply(7, SNAP(2, 700, 1, 900, null)); await flush();
  ck('voto pendente novo: toca e mostra o item', TONES > 0 && btnText(a.doc).some(s => /esperando o seu voto/.test(s)), btnText(a.doc));
  a.store['moj_alert_mute_c'] = '1';
  TONES = 0; NOW += 13000; runDue(a.tm);
  a.reply(8, SNAP(3, 800, 1, 900, null)); await flush();
  ck('mudo: chegou mais uma e não toca', TONES === 0, TONES);
  delete a.store['moj_alert_mute_c'];
  TONES = 0;
  for (let i = 9; i < 30 && TONES === 0; i++) { NOW += 13000; runDue(a.tm); if (a.calls[i]) { a.reply(i, SNAP(3, 800, 1, 900, null)); await flush(); } }
  ck('lembrete: a pendência continua ⇒ toca de novo em ~2 min', TONES > 0, TONES);
  NOW += 13000; runDue(a.tm);
  const k = a.calls.length - 1; a.fail(k, 403); await flush();
  ck('403: o poll PARA (nenhum timer de poll)', pollTimers(a.tm).length === 0, pollTimers(a.tm).length);

  print('== duas abas: uma consulta, a outra escuta ==');
  const co = mkCoord();
  const A = mkTab({ coord:co }), B = mkTab({ coord:co });
  const ST = { logged_in:true, login:'cj.cjudge', is_judge:true, is_chief:true };
  A.start(ST); await flush(); B.start(ST); await flush();
  ck('só a líder (A) consultou', A.calls.length === 1 && B.calls.length === 0, [A.calls.length, B.calls.length]);
  A.reply(0, SNAP(1, 100, 0, 0, 0)); await flush();
  ck('a seguidora (B) recebeu pelo canal e mostra o banner', shown(B.doc) && B.doc.title === '(1) Contest — MOJ', [btnText(B.doc), B.doc.title]);
  B.poke(); await flush();
  ck('poke da seguidora: a LÍDER consulta', A.calls.length === 2 && B.calls.length === 0, [A.calls.length, B.calls.length]);
  A.reply(1, SNAP(1, 100, 0, 0, 1)); await flush();
  ck('conflito chega às duas', btnText(B.doc).some(s => /conflito/.test(s)) && btnText(A.doc).some(s => /conflito/.test(s)), btnText(B.doc));
  A.closed = true; co.release(A); await flush();
  ck('a líder fechou: B assume e consulta', B.calls.length === 1, B.calls.length);
}
const loop = new imports.gi.GLib.MainLoop(null, false);
main().catch(e => { print('  FAIL: exceção ' + e + ' ' + (e && e.stack)); fail++; }).finally(() => loop.quit());
loop.run();
print(''); print('smoke-staff-alert: ' + pass + ' ok, ' + fail + ' falha(s)');
if (fail) imports.system.exit(1);
"
