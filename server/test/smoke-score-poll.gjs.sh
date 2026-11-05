#!/bin/bash
# smoke-score-poll.gjs.sh — o poll do placar SOBREVIVE a erro (05/11/2026, véspera da LATAM). Antes, um 429/502/falha de
# rede trocava a tabela por "Falha ao carregar o placar" e voltava SEM reagendar: a aba ficava sem placar até o F5 — e o
# F5 em massa é a própria rajada. Extrai as funções REAIS do web/contest/score/score.js (pollScore, pollOk, retryBoot,
# applyBootPiece e as declarações de estado) e roda no gjs com DOM/API falsos. Garante:
#   · erro antes do 1º placar = aviso de erro + nova tentativa em 10–20 s;
#   · erro com placar na tela = o placar FICA, o aviso #scoreStale aparece, espera crescente 10–20 / 20–40 / 30–60 s;
#   · sucesso = aviso some, espera zera, ritmo normal 30–60 s;
#   · duas cadeias (início da prova × troca de coorte): a velha morre sem reagendar;
#   · contest secreto com 401 = convite ao login, sem reagendar;
#   · peça do boot que falhou (ex.: /contest/teams) é pedida de novo no próximo poll bem-sucedido.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
SJ="$ROOT/web/contest/score/score.js"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "score-poll: gjs ausente — pulando"; exit 0; }
{ cat <<'JS'
const CONTEST = 'c1';
let basic = { secret: false }, isAuth = true, cohortView = '', parsed = null, serverAnon = false, anonMode = false;
let frozenView = false;
let BALLOONS = {}, regions = [], teamsMeta = [], teamsDir = {}, classified = null, genPlace = null;
const T = (pt) => pt;
const els = {};
function mkEl(id) { const cl = new Set(); return els[id] = { id, innerHTML: '', classList: { add: (c) => cl.add(c), remove: (c) => cl.delete(c), toggle: () => {}, has: (c) => cl.has(c) } }; }
mkEl('scoreContainer'); mkEl('scoreStale').classList.add('hidden'); mkEl('scoreFilters');
const document = { getElementById: (id) => els[id] || null };
let timers = [];
const setTimeout = (fn, ms) => { timers.push({ fn, ms }); return timers.length; };
const clearTimeout = () => {};
// a API falsa: uma fila de respostas (Error com status = falha; objeto = sucesso)
let queue = [], pending = null;
class ApiError extends Error { constructor(s) { super('HTTP ' + s); this.status = s; } }
async function apiGetTextMeta() {
  if (pending) { const p = pending; pending = null; return p; }
  const r = queue.shift(); if (r instanceof Error) throw r;
  return { text: r, headers: new Map([['X-MOJ-Frozen', '0']]) };
}
let apiCalls = [];
async function apiGet(path) { apiCalls.push(path); if (path.includes('/contest/teams?')) return { teams: { t1: { has_logo: true } } }; return null; }
function setFrozenNotice() {} function renderAnon() {} function renderFilters() {} function reRender() {}
function applyTeamsDir() {} function applyTeamsMeta() {} async function fetchGenPlace() {} function renderNav() {}
function parseICPC() { return { teams: [] }; } function parseOBI() { return null; } function parseGeneric() { return null; }
function classifiedMap(x) { return x; }
let refreshTimer = null;
JS
  grep -E '^let pollGen = |^const BOOT_RETRY = ' "$SJ"
  sed -n '/^async function pollScore(/,/^}/p; /^function pollOk(/,/^}/p; /^async function retryBoot(/,/^}/p; /^function applyBootPiece(/,/^}/p' "$SJ"
  cat <<'JS'
const out = [];
const last = () => timers[timers.length - 1];
const run = async () => { const t = timers.shift(); await t.fn(); };
(async () => {
  // 1) erro antes do 1º placar
  queue = [new ApiError(429)];
  await pollScore();
  out.push('e1_box=' + (els.scoreContainer.innerHTML.includes('tentando de novo') ? 1 : 0));
  out.push('e1_ms=' + (timers.length === 1 && last().ms >= 10000 && last().ms <= 20000 ? 1 : 0));
  // 2) sucesso: placar (vazio) na tela, ritmo normal
  queue = ['icpc\n']; await run();
  out.push('ok_ms=' + (timers.length === 1 && last().ms >= 30000 && last().ms <= 60000 ? 1 : 0));
  const shown = els.scoreContainer.innerHTML;
  // 3) três erros seguidos com placar na tela: o placar FICA, aviso aparece, espera cresce até o teto
  queue = [new ApiError(502), new ApiError(429), new ApiError(429), new ApiError(429)];
  const ms = [];
  for (let i = 0; i < 4; i++) { await run(); ms.push(last().ms); }
  out.push('keep=' + (els.scoreContainer.innerHTML === shown ? 1 : 0));
  out.push('stale_on=' + (els.scoreStale.classList.has('hidden') ? 0 : 1));
  out.push('back=' + (ms[0] >= 10000 && ms[0] <= 20000 && ms[1] >= 20000 && ms[1] <= 40000 && ms[2] >= 30000 && ms[2] <= 60000 && ms[3] >= 30000 && ms[3] <= 60000 ? 1 : 0));
  // 4) volta: aviso some, espera zera
  queue = ['icpc\n']; await run();
  out.push('stale_off=' + (els.scoreStale.classList.has('hidden') ? 1 : 0));
  queue = [new ApiError(429)]; await run();
  out.push('reset=' + (last().ms >= 10000 && last().ms <= 20000 ? 1 : 0));
  // 5) duas cadeias: a 1ª fica esperando a resposta; a 2ª começa e termina; a 1ª, ao voltar, morre sem reagendar
  timers = [];
  let release; pending = new Promise((r) => { release = r; });
  const first = pollScore();                       // pega o `pending` e espera
  queue = ['icpc\n']; await pollScore();           // a 2ª cadeia
  const before = timers.length;
  release({ text: 'icpc\n', headers: new Map() }); await first;
  out.push('one_chain=' + (before === 1 && timers.length === 1 ? 1 : 0));
  // 6) peça do boot que falhou volta no próximo poll bem-sucedido
  timers = []; BOOT_RETRY['teams'] = '/contest/teams?contest=c1';
  queue = ['icpc\n']; await pollScore();
  out.push('boot=' + (teamsDir.t1 && !BOOT_RETRY.teams ? 1 : 0));
  apiCalls = []; queue = ['icpc\n']; await run();
  out.push('boot_once=' + (apiCalls.length === 0 ? 1 : 0));
  // 7) contest secreto, sessão encerrada (401): convite ao login, sem reagendar
  timers = []; basic = { secret: true }; queue = [new ApiError(401)];
  await pollScore();
  out.push('secret401=' + (els.scoreContainer.innerHTML.includes('Contest privado') && timers.length === 0 ? 1 : 0));
  print(out.join(' '));
})().catch((e) => print('ERRO ' + e + ' ' + e.stack));
JS
} > "$T/p.js"
out="$(gjs -m "$T/p.js" 2>&1 || gjs "$T/p.js" 2>&1)"
PASS=0; FAIL=0
chk(){ if [[ " $out " == *" $1=1 "* ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: $2" >&2; fi; }
chk e1_box    "erro antes do 1º placar: aviso de erro com 'tentando de novo'"
chk e1_ms     "…e nova tentativa em 10–20 s (antes: nenhuma)"
chk ok_ms     "sucesso: ritmo normal 30–60 s"
chk keep      "erro com placar na tela: o placar FICA"
chk stale_on  "…e o aviso #scoreStale aparece"
chk back      "espera crescente 10–20 / 20–40 / 30–60 / teto 30–60 s"
chk stale_off "sucesso tira o aviso"
chk reset     "…e zera a espera"
chk one_chain "duas cadeias: a velha morre sem reagendar"
chk boot      "peça do boot que falhou (teams) volta no próximo poll"
chk boot_once "…e não é pedida de novo depois de vir"
chk secret401 "contest secreto com 401: convite ao login, sem reagendar"
[[ $FAIL -eq 0 ]] || echo "saída: $out" >&2
echo "score-poll: $PASS ok, $FAIL falhas"; [[ $FAIL -eq 0 ]]
