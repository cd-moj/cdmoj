#!/bin/bash
# smoke-report-caps.sh — o report.html do juiz (mojtools/gen-report.sh) tem TETO POR BYTES em cada
# bloco embutido (REPORT_MAX_BYTES, default 64 KB): uma linha de 3 MB na entrada/stderr/diff não
# entra inteira (LATAM 2026: reports de 17 MB, 38 GB de mojlog). Roda o gerador REAL sobre um
# workdirbase sintético (report.env + arquivos por teste); sem mojtools, SKIP.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
MT="${MOJTOOLS_DIR:-$(cd "$ROOT/.." && pwd)/mojtools}"
[[ -x "$MT/gen-report.sh" || -f "$MT/gen-report.sh" ]] || { echo "SKIP: sem mojtools ($MT)"; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; ((fail++)); fi; }
PKG="$T/pkg"; WB="$T/wb"; mkdir -p "$PKG/tests/input" "$PKG/tests/output" "$WB"
# t1: entrada de 3 MB numa linha só; t2: pequena
head -c 3000000 /dev/zero | tr '\0' 'x' > "$PKG/tests/input/t1"; printf '\n' >> "$PKG/tests/input/t1"; printf 'ok\n' > "$PKG/tests/output/t1"
printf '1 2\n' > "$PKG/tests/input/t2"; printf '3\n' > "$PKG/tests/output/t2"
printf 'WA\n' > "$WB/t1-log.verdict"; printf 'AC\n' > "$WB/t2-log.verdict"
printf 'WA\nAC\n' > "$WB/log.verdictall"
# diff de 2 MB numa linha + stderr de 5 MB numa linha (o caso que inflava o report)
{ printf '< '; head -c 2000000 /dev/zero | tr '\0' 'e'; printf '\n> obtido\n'; } > "$WB/t1-log.compare"
head -c 5000000 /dev/zero | tr '\0' 's' > "$WB/t1-stderr"; printf '\n' >> "$WB/t1-stderr"
printf '0.01\n' > "$WB/t1-log.timelog"; printf '0.01\n' > "$WB/t2-log.timelog"
{ printf 'PROBLEM=%q\nLANGUAGE=%q\nSRCBASENAME=%q\nTL_LANG=%q\nSMALLRESP=%q\nFINALRESP=%q\n' col#pa C sol.c 1 WA "Wrong Answer"
  printf 'VERDICT_CANON=%q\nSCORE=%q\nSCORE_MAX=%q\nSCORE_KIND=%q\nSCORE_GROUPS=%q\n' "Wrong Answer" 50 100 tests ""
  printf 'CORRECT=%q\nTOTALTESTS=%q\nTOTALTIME=%q\nPROBLEMTEMPLATEDIR=%q\nHOSTBT=%q\nSTARTDATE=%q\nRUNALL=%q\nNPROCINFO=%q\nREPORTMODE=%q\n' 1 2 0.02 "$PKG" testhost 2026-09-16 y 1 normal
} > "$WB/report.env"

echo "== gen-report com o teto padrão (64 KB) =="
bash "$MT/gen-report.sh" "$WB" >/dev/null 2>&1
R="$WB/report.html"
ck "report.html gerado"                    '[[ -s "$R" ]]'
sz=$(stat -c%s "$R" 2>/dev/null || echo 0)
ck "report < 400 KB (era ~10 MB sem o teto): $((sz/1024)) KB" '(( sz < 409600 ))'
ck "aviso de truncagem por bytes (entrada e stderr)" '[[ "$(grep -o "truncado: mostrando 64 KB de" "$R" | wc -l)" -ge 2 ]]'
ck "diff também truncado por bytes"        'grep -q "diff truncado: mostrando 64 KB de" "$R"'
ck "teste pequeno intacto (1 2 / sem aviso)" 'grep -q "1 2" "$R" && [[ "$(grep -c "truncado" "$R")" -le 3 ]]'
ck "HTML fecha os <pre> que abre"          '[[ "$(grep -o "<pre" "$R" | wc -l)" == "$(grep -o "</pre>" "$R" | wc -l)" ]]'

echo "== REPORT_MAX_BYTES=1000000 (teto maior) =="
REPORT_MAX_BYTES=1000000 bash "$MT/gen-report.sh" "$WB" >/dev/null 2>&1
sz2=$(stat -c%s "$R" 2>/dev/null || echo 0)
ck "report cresce com o teto ($((sz2/1024)) KB) mas ainda corta a linha de 3 MB" '(( sz2 > sz && sz2 < 4000000 ))' 

echo; echo "RESULT: $pass passed, $fail failed"; [[ $fail -eq 0 ]]
