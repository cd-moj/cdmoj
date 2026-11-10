#!/bin/bash
# smoke-api-retry.gjs.sh — o cliente web repete o 429 do NGINX só na AUTORIA (web/shared/api.js `timedFetch`, 10/11/2026).
# O nginx limita /api/v1/problems/* a 6 em voo por sessão e 12 no total (smoke-problems-limit.sh); duas abas do editor
# abrindo juntas passam de 6. Prende: 429 HTML em /problems/ repete (0,5/1/2/4 s) e passa; 429 JSON (da API) não repete;
# 429 fora da autoria (o quebra-circuito do contest) não repete; o teto de 4 repetições devolve o 429.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"; JS="$ROOT/web/shared/api.js"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "api-retry(gjs): gjs ausente — pulando"; exit 0; }
blk="$(awk '/^const AUTHORING_RETRY_MS/{f=1} f{print} f&&/^}$/{exit}' "$JS")"
[[ "$blk" == *"async function timedFetch("* ]] || { echo "FAIL: o bloco do timedFetch não foi achado no api.js"; exit 1; }
{ cat <<'JS'
const API_BASE = '/api/v1'; const noteServerDate = () => {};
let CALLS = 0, PLAN = [];   // PLAN: a resposta de cada chamada {status, ct}
const resp = (s, ct) => ({ status: s, headers: { get: (h) => (h === 'Content-Type' ? ct : null) } });
globalThis.fetch = async () => { const p = PLAN[Math.min(CALLS, PLAN.length - 1)]; CALLS++; return resp(p.status, p.ct); };
const _st = globalThis.setTimeout; let WAITS = [];
globalThis.setTimeout = (fn, ms) => { WAITS.push(ms); return _st(fn, 0); };   // sem esperar de verdade
JS
  printf '%s\n' "$blk"
  cat <<'JS'
let pass = 0, fail = 0; const ck = (n, c) => { if (c) pass++; else { fail++; print('  FAIL: ' + n); } };
const H = { status: 429, ct: 'text/html' }, OK = { status: 200, ct: 'application/json' };
const run = async (url, plan) => { CALLS = 0; WAITS = []; PLAN = plan; return timedFetch(url, {}); };
async function main() {
  let r = await run('/api/v1/problems/calib?id=x', [H, H, OK]);
  ck('autoria: 2 × 429 do nginx e passa', r.status === 200 && CALLS === 3 && WAITS.length === 2 && WAITS[0] >= 500 && WAITS[1] >= 1000);
  r = await run('/api/v1/problems/test-run', [{ status: 429, ct: 'application/json; charset=utf-8' }, OK]);
  ck('autoria: 429 JSON (da API) não repete', r.status === 429 && CALLS === 1);
  r = await run('/api/v1/contest/score?contest=x', [H, OK]);
  ck('fora da autoria (quebra-circuito do contest): não repete', r.status === 429 && CALLS === 1);
  r = await run('/api/v1/problems/status', [H]);
  ck('teto: 4 repetições e devolve o 429', r.status === 429 && CALLS === 5 && WAITS.length === 4 && WAITS[3] >= 4000);
  r = await run('/api/v1/problems/get?id=x', [OK]);
  ck('200 de primeira: uma chamada, sem espera', r.status === 200 && CALLS === 1 && WAITS.length === 0);
}
const loop = new imports.gi.GLib.MainLoop(null, false);
main().catch((e) => { print('  FAIL: exceção ' + e); fail++; }).finally(() => loop.quit());
loop.run();
print(`RESULT: ${pass} passed, ${fail} failed`);
JS
} > "$T/t.js"
out="$(gjs "$T/t.js" 2>&1)"; echo "$out"
grep -q "RESULT: [0-9]* passed, 0 failed" <<<"$out"
