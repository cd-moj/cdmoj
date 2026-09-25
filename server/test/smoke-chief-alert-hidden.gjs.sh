#!/bin/bash
# smoke-chief-alert-hidden.gjs.sh — o alerta de conflitos do juiz-chefe (web/shared/chief-alert.js) em ABA
# OCULTA espaça o poll, volta NA HORA quando a aba reaparece e mantém UMA cadeia de timers.
#
# XIV Maratona UnB (25/09/2026): 677 GET /contest/review/conflicts em 15 min — abas do chefe/admin
# esquecidas polando a cada 8–12 s. O poll não PARA na aba oculta (o bip existe p/ chamar quem não está
# olhando): passa a 30–40 s. Com o módulo REAL, apiGet e timers falsos:
#   · aba visível: próximo poll em 8–12 s; oculta: 30–40 s;
#   · `visibilitychange` p/ visível consulta na hora;
#   · poll disparado com outro EM VOO (poke/visibilidade) não duplica a cadeia: sobra 1 timer vivo.
# Sem gjs: pula (rc 0).
set -u
command -v gjs >/dev/null 2>&1 || { echo "chief-alert-hidden: gjs ausente — pulando"; exit 0; }
WEB="$(cd "$(dirname "$(readlink -f "$0")")/../../web" && pwd)"
SRC="$(sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$WEB/shared/chief-alert.js")"
[[ "$SRC" == *"function startChiefAlert"* ]] || { echo "FAIL: startChiefAlert não encontrado"; exit 1; }
gjs -c "
const GLib = imports.gi.GLib;
function El(){ this.classList = { _s:new Set(), add(c){ this._s.add(c); }, remove(c){ this._s.delete(c); } }; this.style = {}; }
El.prototype.setAttribute = function(){}; El.prototype.appendChild = function(){};
const LIS = {};
globalThis.document = { hidden:false, head:new El(), body:new El(), getElementById:() => null,
  createElement:() => new El(), addEventListener:(t, f) => { (LIS[t] = LIS[t] || []).push(f); } };
globalThis.window = { dispatchEvent(){} }; globalThis.navigator = {}; globalThis.location = { pathname:'/contest/', href:'' };
const TIM = new Map(); let tid = 0;
globalThis.setTimeout = (fn, ms) => { TIM.set(++tid, { fn, ms }); return tid; };
globalThis.clearTimeout = (id) => { TIM.delete(id); };
const T = (pt) => pt;
const CALLS = [];
function apiGet(){ let res; const p = new Promise(r => { res = r; }); CALLS.push(res); return p; }
$SRC
let pass = 0, fail = 0;
const ck = (msg, ok, dbg) => { if (ok) { print('  ok: ' + msg); pass++; } else { print('  FAIL: ' + msg + ' :: ' + (dbg || '')); fail++; } };
const flush = async () => { for (let i = 0; i < 20; i++) await Promise.resolve(); };
const live = () => [...TIM.values()];
const fire = () => { const [id, t] = [...TIM.entries()][0]; TIM.delete(id); t.fn(); };
async function main() {
  startChiefAlert('c', { is_chief:true });
  ck('1º poll na largada', CALLS.length === 1, CALLS.length);
  CALLS[0]({ n:0 }); await flush();
  ck('aba visível: próximo poll em 8–12 s', live().length === 1 && live()[0].ms >= 8000 && live()[0].ms <= 12000, JSON.stringify(live().map(t => t.ms)));
  document.hidden = true; fire(); CALLS[1]({ n:1 }); await flush();
  ck('aba OCULTA: próximo poll em 30–40 s (não para)', live().length === 1 && live()[0].ms >= 30000 && live()[0].ms <= 40000, JSON.stringify(live().map(t => t.ms)));
  fire();                                                     // poll 3 em voo…
  document.hidden = false; (LIS.visibilitychange || []).forEach(f => f());
  ck('aba volta: consulta NA HORA', CALLS.length === 4, CALLS.length);
  CALLS[2]({ n:1 }); CALLS[3]({ n:1 }); await flush();
  ck('poll no meio de outro em voo: UMA cadeia de timers', live().length === 1, live().length + ' timers vivos');
}
const loop = new GLib.MainLoop(null, false);
main().catch(e => { print('  FAIL: exceção ' + e); fail++; }).finally(() => loop.quit());
loop.run();
print(''); print('RESULT: ' + pass + ' passed, ' + fail + ' failed');
if (fail) imports.system.exit(1);
"
