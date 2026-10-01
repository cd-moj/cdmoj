#!/bin/bash
# smoke-countdown.gjs.sh — o cronômetro da prova (web/shared/ui.js: fmtCountdown) mostra DIAS.
#
# Num contest de 2 meses o "Termina em" acumulava as horas: "1447:04:14". Agora, de 24 h para cima,
# "60d 07:04:14"; abaixo disso segue "HH:MM:SS"/"MM:SS". Os cronômetros da prova (contest.js,
# score.js, lib/contest-chrome.js, shared/contest-shell.js) e o relógio da participação virtual
# (treino/virtual/virtual.js) usam todos esta função — e o teste confere que cada um a USA.
# Sem gjs: pula (rc 0).
set -u
command -v gjs >/dev/null 2>&1 || { echo "countdown: gjs ausente — pulando"; exit 0; }
WEB="$(cd "$(dirname "$(readlink -f "$0")")/../../web" && pwd)"
SRC="$(python3 - "$WEB/shared/ui.js" <<'PY'
import re, sys
s = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'^export function fmtCountdown\(.*?^}\n', s, re.S | re.M)
print(m.group(0).replace('export function', 'function', 1) if m else '')
PY
)"
[[ "$SRC" == *"function fmtCountdown"* ]] || { echo "FAIL: fmtCountdown não encontrado em web/shared/ui.js"; exit 1; }
# nenhum cronômetro de prova com cópia própria (a cópia era o que acumulava as horas), e cada um USA a
# função compartilhada (sem o import, a página quebra só em tempo de execução — o node --check não pega)
dup=0
for f in contest/contest.js contest/score/score.js lib/contest-chrome.js shared/contest-shell.js treino/virtual/virtual.js; do
  grep -q -E "Math\.floor\( *s(ec)? */ *3600 *\)" "$WEB/$f" && { echo "  FAIL: $f ainda formata horas por conta própria"; dup=1; }
  grep -q "fmtCountdown" "$WEB/$f" || { echo "  FAIL: $f não usa fmtCountdown"; dup=1; }
done
gjs -c "
$SRC
let pass = 0, fail = 0;
const ck = (entrada, esperado) => { const v = fmtCountdown(entrada);
  if (v === esperado) { print('  ok: ' + entrada + ' -> ' + v); pass++; } else { print('  FAIL: ' + entrada + ' -> ' + v + ' (esperado ' + esperado + ')'); fail++; } };
ck(-5, '00:00');
ck(0, '00:00');
ck(59, '00:59');
ck(3599, '59:59');
ck(3600, '01:00:00');
ck(86399, '23:59:59');
ck(86400, '1d 00:00:00');
ck(1447 * 3600 + 4 * 60 + 14, '60d 07:04:14');
ck(400 * 86400 + 5, '400d 00:00:05');
ck('90', '01:30');
ck(12.9, '00:12');
print('RESULT: ' + pass + ' passed, ' + fail + ' failed');
if (fail) imports.system.exit(1);
" || exit 1
exit $dup
