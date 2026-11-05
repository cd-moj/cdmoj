#!/bin/bash
# smoke-judge-poll.gjs.sh — o poll da fila de revisão do juiz SOBREVIVE a erro (05/11/2026, véspera da LATAM). Antes, um
# 429/502 na /contest/review/list trocava a fila por "Falha ao carregar a fila" e voltava sem reagendar: o juiz ficava
# parado até recarregar a página. Extrai o loadReview REAL de web/contest/judge/judge.js e roda no gjs. Garante:
#   · erro sem fila na tela = aviso + nova tentativa em 10–20 s;
#   · erro com fila na tela = a fila FICA (nada redesenhado) + nova tentativa;
#   · 401/403 = para (sessão encerrada / sem permissão: repetir não resolve);
#   · sucesso sem avaliação ativa = o ritmo de sempre (6–9 s).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
JJ="$ROOT/web/contest/judge/judge.js"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "judge-poll: gjs ausente — pulando"; exit 0; }
{ cat <<'JS'
const CONTEST = 'c1', G = {}, enc = encodeURIComponent, T = (pt) => pt;
let REVIEW = true, rv = null, ME = '', OPTIONS = [], IS_CHIEF = false, pollT = null, tickT = null, renders = 0;
const box = { innerHTML: '' };
const document = { getElementById: () => box };
let timers = [];
const setTimeout = (fn, ms) => { timers.push({ fn, ms }); return timers.length; };
const clearTimeout = () => {};
class ApiError extends Error { constructor(s) { super('HTTP ' + s); this.status = s; } }
let queue = [];
async function apiGet() { const r = queue.shift(); if (r instanceof Error) throw r; return r; }
function renderReview() { renders++; box.innerHTML = 'FILA'; }
JS
  sed -n '/^async function loadReview(/,/^}/p' "$JJ"
  cat <<'JS'
const out = [];
const last = () => timers[timers.length - 1];
(async () => {
  queue = [new ApiError(429)]; await loadReview();
  out.push('e1=' + (box.innerHTML.includes('Tentando de novo') && timers.length === 1 && last().ms >= 10000 && last().ms <= 20000 ? 1 : 0));
  timers = []; queue = [{ options: [], my_active: null }]; await loadReview();
  out.push('ok=' + (box.innerHTML === 'FILA' && timers.length === 1 && last().ms >= 6000 && last().ms <= 9000 ? 1 : 0));
  timers = []; const r0 = renders; queue = [new ApiError(502)]; await loadReview();
  out.push('keep=' + (box.innerHTML === 'FILA' && renders === r0 && timers.length === 1 && last().ms >= 10000 ? 1 : 0));
  timers = []; queue = [new ApiError(401)]; await loadReview();
  out.push('stop401=' + (timers.length === 0 && box.innerHTML.includes('Falha') ? 1 : 0));
  timers = []; queue = [new ApiError(403)]; await loadReview();
  out.push('stop403=' + (timers.length === 0 ? 1 : 0));
  print(out.join(' '));
})().catch((e) => print('ERRO ' + e + ' ' + e.stack));
JS
} > "$T/j.js"
out="$(gjs -m "$T/j.js" 2>&1)"
PASS=0; FAIL=0
chk(){ if [[ " $out " == *" $1=1 "* ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: $2" >&2; fi; }
chk e1      "erro sem fila na tela: aviso + nova tentativa em 10–20 s (antes: nenhuma)"
chk ok      "sucesso sem avaliação ativa: o ritmo de sempre (6–9 s)"
chk keep    "erro com fila na tela: a fila FICA + nova tentativa"
chk stop401 "401: para"
chk stop403 "403: para"
[[ $FAIL -eq 0 ]] || echo "saída: $out" >&2
echo "judge-poll: $PASS ok, $FAIL falhas"; [[ $FAIL -eq 0 ]]
