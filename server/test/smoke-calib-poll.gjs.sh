#!/bin/bash
# A TELA DO AUTOR ESPERA A CALIBRAÇÃO TERMINAR — quem diz que terminou é o SERVIDOR.
#
# O editor desistia no relógio: 20 ticks de 4 s (80 s), e então zerava o estado, sumia com o aviso
# "Calibrando no juiz…" e PARAVA DE BUSCAR PARA SEMPRE. Uma calibração real leva MINUTOS (medido em
# produção em 21/09/2026: 2m49s a 7m20s, conforme nº de soluções × testes), então o autor via a
# mensagem aparecer e sumir sem nada mudar, clicava de novo, recarregava — relatos do José Leite e
# do Arthur Botelho. Pior: a âncora antiga (`calibPrevMax`/`maxCalibAt`) lia dado EM MEMÓRIA que
# podia ser null e declarava "pronto" no primeiro tick.
# Este teste tranca o novo contrato: a decisão vem de `/problems/calib` (`calibrating[]`), erro de
# rede não apaga a tela, e a aba escondida re-arma o polling ao voltar.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"; F="$ROOT/web/problemas/editar.js"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "calib-poll: gjs ausente — pulando"; exit 0; }
PASS=0; FAIL=0
ck(){ if eval "$2"; then echo "  ok: $1"; PASS=$((PASS+1)); else echo "  FALHOU: $1"; FAIL=$((FAIL+1)); fi; }
chk(){ if [[ "$1" == "$2" ]]; then echo "  ok: $3"; PASS=$((PASS+1)); else echo "  FALHOU: $3 (got '$1', want '$2')"; FAIL=$((FAIL+1)); fi; }

echo "== o que não pode mais existir no editor =="
ck "a âncora de relógio saiu (calibPrevMax/maxCalibAt)" '! grep -qE "^[^/]*\b(calibPrevMax|maxCalibAt)\b" "$F"'
ck "erro de rede NÃO zera os cartões"                   'grep -q "if (calib) { LASTCALIB = calib" "$F"'
ck "poll serializado (uma volta por vez)"               'grep -q "if (calibBusy) return" "$F"'
ck "re-arma ao voltar p/ a aba"                         'grep -q "visibilitychange" "$F"'
ck "a decisão vem do servidor"                          'grep -q "calibRunning = () => CALIB_LIVE.length > 0" "$F"'
ck "e o clique repetido lê o dedup da resposta"         'grep -q "already_queued" "$F"'

echo "== funções puras, extraídas do editar.js real =="
{ sed -n '/^const minsSince = /p' "$F"
  sed -n '/^const calibRunning = /p' "$F"
  sed -n '/^const savedSinceCalib = /,/^  && SAVED_AT/p' "$F"
  sed -n '/^function calibWhere()/,/^}/p' "$F"
  cat <<'JS'
const T = (pt) => pt;                      // a tela é bilíngue; aqui basta o PT
const NOW = Math.floor(Date.now() / 1000);
let CALIB_LIVE = [], SAVED_AT = 0;
CALIB_LIVE = [];                    print('roda_vazio=' + calibRunning());
CALIB_LIVE = [{ host: 'judge-sp1', since: NOW - 185, state: 'running' }];
print('roda_um=' + calibRunning());
print('onde=' + calibWhere());
CALIB_LIVE = [{ host: '', since: NOW - 30, state: 'queued' }];
print('onde_fila=' + calibWhere());
// pedir de novo: só é legítimo se o autor SALVOU depois que a calibração em voo começou
CALIB_LIVE = [{ host: 'judge', since: NOW - 100, state: 'running' }];
SAVED_AT = 0;          print('salvou_nao=' + savedSinceCalib());
SAVED_AT = NOW - 200;  print('salvou_antes=' + savedSinceCalib());
SAVED_AT = NOW - 10;   print('salvou_depois=' + savedSinceCalib());
CALIB_LIVE = [];       print('sem_voo=' + savedSinceCalib());
print('mins=' + minsSince(NOW - 125));
JS
} > "$T/t.js"
out="$(gjs "$T/t.js" 2>&1)" || { echo "$out" >&2; echo "calib-poll: gjs falhou"; exit 1; }
kv(){ sed -n "s/^$1=//p" <<<"$out" | head -1; }
chk "$(kv roda_vazio)"    "false" "sem nada em voo, não está calibrando"
chk "$(kv roda_um)"       "true"  "com um juiz em voo, está calibrando"
ck  "o aviso diz o juiz e há quanto tempo ($(kv onde))" '[[ "$(kv onde)" == *judge-sp1* && "$(kv onde)" == *"3 min"* ]]'
ck  "pedido só na fila aparece como fila ($(kv onde_fila))" '[[ "$(kv onde_fila)" == *fila* ]]'
chk "$(kv salvou_nao)"    "false" "não salvou desde o pedido => não repete"
chk "$(kv salvou_antes)"  "false" "salvou ANTES do pedido => não repete"
chk "$(kv salvou_depois)" "true"  "salvou DEPOIS => pedir de novo é legítimo"
chk "$(kv sem_voo)"       "false" "nada em voo => nada a comparar"
chk "$(kv mins)"          "2"     "minutos decorridos"
echo; echo "RESULT: $PASS passed, $FAIL failed"; (( FAIL == 0 ))
