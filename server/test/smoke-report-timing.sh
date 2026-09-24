#!/bin/bash
# smoke-report-timing.sh — o gráfico "Tempo de execução" do report.html (mojtools/gen-report.sh) pinta pelo
# VEREDICTO e pela TOLERÂNCIA (drift), não só por "tempo >= limite". Relato do Daniel Saad (24/09/2026): um
# AC com dois testes acima do limite mas dentro da tolerância saía com barras VERMELHAS — a mesma cor do
# Wrong Answer na legenda do mapa, logo acima: "vermelho e verde ao mesmo tempo".
#   azul = dentro do limite · amarelo = acima do limite, aceito pela tolerância · cor de TLE = estourou
# Roda o gerador REAL sobre um workdirbase sintético; sem mojtools, SKIP. No fim confere a resolução da
# tolerância no build-and-test.sh: TLMOD[<lang>.drift] › TLMOD[default.drift] (pedido do Ribas) › 0.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
MT="${MOJTOOLS_DIR:-$(cd "$ROOT/.." && pwd)/mojtools}"
[[ -f "$MT/gen-report.sh" ]] || { echo "SKIP: sem mojtools ($MT)"; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; ((fail++)); fi; }
PKG="$T/pkg"; WB="$T/wb"; mkdir -p "$PKG/tests/input" "$PKG/tests/output" "$WB"
mk(){ # <teste> <veredicto> <tempo>
  printf '1\n' > "$PKG/tests/input/$1"; printf '1\n' > "$PKG/tests/output/$1"
  printf '%s\n' "$2" > "$WB/$1-log.verdict"; printf 'VERDICT[%s]=%s\n' "$1" "$2" >> "$WB/log.verdictall"
  printf 'real %s\nuser 0\nsys 0\nres 1024\ncpu 99%%\n' "$3" > "$WB/$1-log.timelog"; }
env_(){ # [TL_DRIFT] — report.env mínimo (sem o 1º argumento = build-and-test antigo, sem TL_DRIFT)
  { printf 'PROBLEM=%q\nLANGUAGE=%q\nSRCBASENAME=%q\nTL_LANG=%q\nSMALLRESP=%q\nFINALRESP=%q\n' 'saad#x' cpp s.cpp .82 TLE "Time Limit Exceeded,67p"
    printf 'VERDICT_CANON=%q\nSCORE=%q\nSCORE_MAX=%q\nSCORE_KIND=%q\n' "Time Limit Exceeded" 67 100 tests
    printf 'CORRECT=%q\nTOTALTESTS=%q\nTOTALTIME=%q\nPROBLEMTEMPLATEDIR=%q\nREPORTMODE=%q\n' 2 3 2.78 "$PKG" normal
    [[ $# -ge 1 ]] && printf 'TL_DRIFT=%q\n' "$1"
  } > "$WB/report.env"; }
mk t1 AC 0.50; mk t2 AC 0.98; mk t3 TLE 1.30
timing(){ awk '/Tempo de execução/{f=1} f&&/Lista de casos/{exit} f' "$WB/report.html"; }

echo "== com a tolerância no report.env (TL_DRIFT=0.2) =="
env_ 0.2; bash "$MT/gen-report.sh" "$WB" >/dev/null 2>&1
ck "report.html gerado"                                  '[[ -s "$WB/report.html" ]]'
G="$(timing)"
ck "cabeçalho: limite com zero à esquerda + tolerância"  'grep -q "limite 0.82s · tolerância +0.2s" <<<"$G"'
ck "t1 (0,50 s) azul"                                    'grep -A1 ">t1<" <<<"$G" | grep -q "background:#1e57c4"'
ck "t2 (0,98 s, AC) AMARELO, não vermelho"               'grep -A1 ">t2<" <<<"$G" | grep -q "background:#eab308"'
ck "t2 diz quanto passou (e o title explica)"           'grep -q "0.98s <span class=\"muted\">(+0.16s)" <<<"$G" && grep -q "title=\"acima do limite, aceito pela tolerância de 0.2s\"" <<<"$G"'
ck "t3 (TLE) na cor de TLE do mapa"                      'grep -A1 ">t3<" <<<"$G" | grep -q "background:#9a6700"'
ck "o vermelho do Wrong Answer saiu do gráfico"          '! grep -q "#be1241" <<<"$G"'
ck "legenda própria com as três cores"                   'grep -q "dentro do limite" <<<"$G" && grep -q "aceito pela tolerância de 0.2s" <<<"$G" && grep -q "estourou o limite" <<<"$G"'
ck "linha do teste t2 explica a tolerância"              'grep -q "0.98s / TL 0.82s · acima do limite, aceito pela tolerância de 0.2s" "$WB/report.html"'
ck "tabela Ambiente: a tolerância"                       'grep -q "Tolerância acima do limite (drift)</td><td>0.2s" "$WB/report.html"'

echo "== report.env de um build-and-test antigo (sem TL_DRIFT) =="
env_; bash "$MT/gen-report.sh" "$WB" >/dev/null 2>&1
G="$(timing)"
ck "gera assim mesmo"                                    '[[ -s "$WB/report.html" ]]'
ck "cabeçalho só com o limite"                           'grep -q "(limite 0.82s)" <<<"$G"'
ck "t2 (AC acima do limite) segue AMARELO"               'grep -A1 ">t2<" <<<"$G" | grep -q "background:#eab308"'
ck "legenda sem o valor da tolerância"                   'grep -q "aceito pela tolerância</span>" <<<"$G"'

echo "== tudo dentro do limite: sem legenda extra =="
: > "$WB/log.verdictall"; rm -f "$WB"/t*-log.*; rm -f "$PKG"/tests/*/t*
mk t1 AC 0.30; mk t2 AC 0.40; env_ 0.2; bash "$MT/gen-report.sh" "$WB" >/dev/null 2>&1
G="$(timing)"
ck "só azul, sem legenda do gráfico"                     '! grep -q "eab308\|9a6700" <<<"$G" && ! grep -q "dentro do limite" <<<"$G"'

echo "== build-and-test.sh: a tolerância é TLMOD[<lang>.drift] › TLMOD[default.drift] › 0 =="
# o trecho REAL do script (no dev a jaula não executa, então o julgamento inteiro não roda aqui)
SNIP="$(awk '/^TLDRIFT=/{f=1} f; /^LOG " - Drift/{exit}' "$MT/build-and-test.sh")"
drift(){ bash -c 'declare -A TLMOD; LOG(){ :; }; LANGUAGE="$1"; eval "$2"; eval "$3"; printf "%s|%s" "$TLDRIFT" "${TLMOD[$LANGUAGE.drift]}"' _ "$1" "$2" "$SNIP"; }
ck "trecho encontrado no build-and-test.sh"              '[[ -n "$SNIP" ]] && grep -q "default.drift" <<<"$SNIP"'
ck "só default.drift: vale p/ a linguagem"               '[[ "$(drift cpp "TLMOD[default.drift]=0.3")" == "0.3|0.3" ]]'
ck "a da linguagem vence a default"                      '[[ "$(drift cpp "TLMOD[default.drift]=0.3; TLMOD[cpp.drift]=0.05")" == "0.05|0.05" ]]'
ck "java.drift não vale p/ cpp (sem default: 0)"         '[[ "$(drift cpp "TLMOD[java.drift]=0.02")" == "0|0" ]]'
ck "…e vale p/ java"                                     '[[ "$(drift java "TLMOD[java.drift]=0.02")" == "0.02|0.02" ]]'
ck "sem nada: 0"                                         '[[ "$(drift py ":")" == "0|0" ]]'
ck "valor que não é número vira 0"                       '[[ "$(drift c "TLMOD[default.drift]=abc")" == "0|0" ]]'
ck "report.env leva o TL_DRIFT"                          'grep -q "TL_DRIFT=%q" "$MT/build-and-test.sh"'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
