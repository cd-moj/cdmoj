#!/bin/bash
# smoke-server-clock.gjs.sh — AS CONTAGENS DA PROVA CONTAM PELO RELÓGIO DO SERVIDOR (web/shared/server-clock.js), 18/10/2026.
# Relato do Daniel Saad (Maratona Padawan do IFB): duas máquinas de juízes mostravam tempos diferentes para o fim da prova —
# cada contagem usava o relógio do computador (Windows adiantado × Linux). Prende:
#   · a estimativa servidor − navegador pelo cabeçalho `Date` (mediana; Date quebrado não entra; data ANOS errada se corrige);
#   · TRÊS máquinas com relógios diferentes (−30 s, +5 s, +60 s) que recebem as mesmas respostas mostram o MESMO tempo
#     restante (diferença ≤ 1 s) — o caso do relato;
#   · o api.js passa toda resposta pelo relógio; nenhuma página de contest compara horário com o relógio do computador.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"; W="$ROOT/web"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "server-clock(gjs): gjs ausente — pulando"; exit 0; }
PASS=0; FAIL=0
ck(){ if eval "$2"; then echo "  ok: $1"; PASS=$((PASS+1)); else echo "  FALHOU: $1"; FAIL=$((FAIL+1)); fi; }
{ cat <<'JS'
// relógio do navegador controlável: Date.now() = verdade + desvio da "máquina"
const realNow = Date.now.bind(Date); let fakeNow = 0; Date.now = () => fakeNow;
JS
  sed -E 's/^export (function|const) /\1 /' "$W/shared/server-clock.js"
  cat <<'JS'
const httpDate = (ms) => new Date(ms).toUTCString();      // o cabeçalho Date (resolução de 1 s)
const END = 1792269000;                                     // fim da prova (epoch do servidor)
// uma "máquina": desvio do relógio dela, recebe N respostas do servidor (RTT de 80 ms), devolve o tempo restante
function machine(skewMs, n) {
  _resetServerClock();
  let truth = END * 1000 - 3600e3 + 123;                    // a 1 h do fim, no relógio do servidor
  for (let i = 0; i < n; i++) {
    fakeNow = truth + skewMs; const t0 = Date.now();
    const atServer = truth + 40; fakeNow = truth + 80 + skewMs; const t1 = Date.now();
    noteServerDate(httpDate(atServer), t0, t1);
    truth += 2000 + 137 * i;                                 // polls a cada ~2 s
  }
  fakeNow = truth + skewMs;
  return { left: END - serverNow(), localLeft: END - Math.floor(Date.now() / 1000), off: serverOffsetMs(), truthLeft: END - Math.floor(truth / 1000) };
}
const a = machine(-30000, 8), b = machine(5000, 8), c = machine(60000, 8);
print('left=' + [a.left, b.left, c.left].join(',') + ' truth=' + a.truthLeft + ' local=' + [a.localLeft, b.localLeft, c.localLeft].join(','));
print('off=' + [a.off, b.off, c.off].map((x) => Math.round(x)).join(','));
// sem resposta nenhuma: o relógio local (offset 0)
_resetServerClock(); fakeNow = 1000000; print('semamostra=' + serverOffsetMs() + ' ' + serverNow());
// Date quebrado e absurdo não entram; um valor fora da curva não puxa a mediana
_resetServerClock(); fakeNow = 5e12;
noteServerDate('lixo', fakeNow, fakeNow + 50); noteServerDate('', fakeNow, fakeNow + 50);
print('lixo=' + serverOffsetMs());
for (let i = 0; i < 6; i++) { noteServerDate(httpDate(fakeNow - 10000), fakeNow, fakeNow + 50); fakeNow += 1000; }
noteServerDate(httpDate(fakeNow + 300000), fakeNow, fakeNow + 50);
print('outlier=' + Math.round(serverOffsetMs()));
// máquina com a data ANOS errada (bateria da placa fraca): a contagem também se corrige
const y = machine(-2 * 365 * 86400e3, 5); print('anos=' + y.left + ' ' + y.truthLeft);
JS
} > "$T/c.js"
out="$(timeout 30 gjs "$T/c.js" 2>&1)" || { echo "$out"; echo "server-clock(gjs): gjs falhou"; exit 1; }
kv(){ sed -n "s/^$1=//p" <<<"$out" | head -1; }
IFS=, read -r la lb lc <<<"$(kv left | cut -d' ' -f1)"; TR="$(kv left | sed -n 's/.* truth=\([0-9]*\).*/\1/p')"
IFS=, read -r xa xb xc <<<"$(kv left | sed -n 's/.* local=//p')"
echo "== três máquinas com relógios diferentes (o relato) =="
ck "contagem pelo servidor igual nas 3 (±1 s): $la $lb $lc" '(( la - lb <= 1 && lb - la <= 1 && lb - lc <= 1 && lc - lb <= 1 ))'
ck "…e igual à verdade (±1 s; verdade $TR)" '(( la - TR <= 1 && TR - la <= 1 ))'
ck "pelo relógio local elas divergiam ($xa $xb $xc) — o defeito que o teste prende" '(( xa != xc ))'
echo "== estimativa =="
ck "sem resposta da API: o relógio local ($(kv semamostra))" '[[ "$(kv semamostra)" == "0 1000" ]]'
ck "Date quebrado ou vazio não entra ($(kv lixo))" '[[ "$(kv lixo)" == 0 ]]'
read -r YL YT <<<"$(kv anos)"
ck "máquina com a data 2 ANOS atrasada também conta certo ($YL × verdade $YT)" '(( YL - YT <= 1 && YT - YL <= 1 ))'
ck "um valor fora da curva não puxa a mediana ($(kv outlier) ms ≈ −10 s)" '(( $(kv outlier) > -11000 && $(kv outlier) < -9000 ))'
echo "== quem usa =="
ck "o api.js mede o relógio nos 4 fetch da API" '[[ "$(grep -c "timedFetch(API_BASE" "$W/shared/api.js")" == 4 ]] && grep -q "noteServerDate(r.headers.get(.Date.)" "$W/shared/api.js"'
BAD="$(grep -rn "Math.floor(Date.now() / 1000)\|Date.now() / 1000" --include=*.js "$W/contest" "$W/lib/contest-chrome.js" "$W/shared/contest-shell.js" "$W/shared/review-board.js" | grep -v "animeitor/animeitor.js" | wc -l)"
ck "nenhuma página de contest compara horário com o relógio do computador ($BAD)" '[[ "$BAD" == 0 ]]'
for f in contest/contest.js contest/score/score.js lib/contest-chrome.js shared/contest-shell.js contest/staff/staff.js contest/score/reveal.js contest/admin/central-tab.js; do
  ck "$f importa o relógio do servidor" 'grep -q "from ./shared/server-clock.js." "$W/$f"'
done
echo "server-clock(gjs): $PASS ok, $FAIL falhas"; [[ $FAIL -eq 0 ]]
