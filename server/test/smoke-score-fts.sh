#!/bin/bash
# FIRST-TO-SOLVE COM CERTEZA — a estrela (`*`) do placar ICPC só pinta quando nenhuma run ainda
# NÃO JULGADA pode roubá-la.
#
# POR QUE EXISTE: até 25/08/2026 o `FTSMIN` era o mínimo puro dos `first_ac_epoch` conhecidos, e
# não olhava run pendente. Então a estrela NASCIA ERRADA e MIGRAVA: o time A submete no minuto 10
# e a run fica na fila; o B submete no 12 e é julgado primeiro ⇒ a estrela aparecia no B e pulava
# para o A quando o AC dele chegava. O placar se autocorrige (é repintado a cada build), mas para
# quem está olhando é confusão — e é a mesma pergunta que decide o balão de "primeiro da sede",
# que é FÍSICO e não se desanuncia.
#
# O caminho exercitado é o de verdade: history -> metrics_recompute -> score/build.sh -> placar.txt
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX"
C="$FIX/fts"; mkdir -p "$C/var"
START=1000

conf(){ { printf 'CONTEST_ID=fts\nCONTEST_TYPE=icpc\nCONTEST_NAME=FTS\n'
          printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$START" 999999999
          printf "PROBS=( cdmoj p/a 'Prob A' A 'p#a' )\n"
          [[ -n "${1:-}" ]] && printf '%s\n' "$1"; } > "$C/conf"; }
conf ""
fx_user "$C" alice x "Alice"
fx_user "$C" bob   x "Bob"

pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: $(tr '\n' '|' < "$C/var/placar.txt")"; ((fail++)); fi; }
build(){ rm -f "$C/var/placar.txt" "$C/var/.metrics-stamp"; bash "$ROOT/score/build.sh" fts >/dev/null 2>&1 || { echo "build.sh FALHOU"; exit 1; }; }
# célula do time no problema A. ⚠ a linha de DADOS não tem as duas colunas-marcador
# (desc/asc) que abrem o cabeçalho: sobra flag:username:univ short:team name:univ full:A:…
# — logo a coluna A é a 6ª, e não a 8ª do cabeçalho (foi o 1º erro deste teste).
cell(){ awk -F: -v u="$1" '$2==u{print $6}' "$C/var/placar.txt"; }
star(){ [[ "$(cell "$1")" == *'*' ]]; }

# alice submete ANTES (t+600) e a run fica na fila; bob submete depois (t+900) e é julgado já.
pend(){ printf '10:p#a:c:Not Answered Yet:%s:a1\n' $(( START + 600 )) > "$C/users/alice/history"; }
ac_alice(){ printf '10:p#a:c:Accepted,100p:%s:a1\n' $(( START + 600 )) > "$C/users/alice/history"; }
wa_alice(){ printf '10:p#a:c:Wrong Answer:%s:a1\n'  $(( START + 600 )) > "$C/users/alice/history"; }
printf '15:p#a:c:Accepted,100p:%s:b1\n' $(( START + 900 )) > "$C/users/bob/history"

echo "== run mais antiga AINDA NA FILA: ninguém leva a estrela =="
pend; build
ck "bob resolveu"                  '[[ -n "$(cell bob)" && "$(cell bob)" != "" ]]'
ck "bob NÃO ganha a estrela"       '! star bob'
ck "alice também não"              '! star alice'

echo "== a run antiga era WA: a estrela vai para quem resolveu =="
wa_alice; build
ck "bob ganha a estrela"           'star bob'
ck "alice (WA) não tem célula ok"  '[[ "$(cell alice)" != *"*" ]]'

echo "== a run antiga era AC: a estrela nasce DIRETO no mais antigo =="
ac_alice; build
ck "alice ganha a estrela"         'star alice'
ck "bob NÃO ganha"                 '! star bob'

echo "== sem pendência nenhuma o comportamento é o de sempre =="
ck "exatamente UMA estrela no A"   '[[ "$(grep -c "[0-9]/[0-9]*\*" "$C/var/placar.txt")" == 1 ]]'

echo "== pendência de quem NÃO resolveu também segura (é ela que pode roubar) =="
# bob tem o AC; alice só tem uma run em julgamento, mais ANTIGA — a estrela espera.
pend; build
ck "estrela retida"                '! star bob'
# ...e uma pendência MAIS NOVA que o AC não segura nada
printf '99:p#a:c:Not Answered Yet:%s:a9\n' $(( START + 1200 )) > "$C/users/alice/history"; build
ck "pendência mais NOVA não segura" 'star bob'

echo "== congelado: run PÓS-freeze não segura a estrela da visão congelada =="
# freeze aos +1000: o AC de bob (+900) é pré-freeze; a pendência de alice (+1200) é pós.
conf "FREEZE_TIME=$(( START + 1000 ))"
build
ck "estrela pintada no congelado"  '[[ "$(grep -c "[0-9]/[0-9]*\*" "$C/var/placar.txt")" == 1 ]]'
# já uma pendência PRÉ-freeze segura
printf '99:p#a:c:Not Answered Yet:%s:a8\n' $(( START + 300 )) > "$C/users/alice/history"
build
ck "pendência pré-freeze segura"   '[[ "$(grep -c "[0-9]/[0-9]*\*" "$C/var/placar.txt")" == 0 ]]'

echo "== metrics VELHO (sem o campo) é desconhecido, não 'sem pendência' =="
# É o estado logo depois de um deploy que acrescenta o campo. O consumidor não pode confundir
# "não há pendente" com "ainda não sei": segura a estrela — e o build.sh evita essa janela
# recomputando em massa quando a lib/users.sh é mais nova que o carimbo.
wa_alice; build                                     # estado com estrela em bob
ck "estrela presente antes"        'star bob'
for m in "$C"/users/*/metrics.json; do jq -c "(.by_problem[]?) |= del(.pending_min_epoch, .frozen)" "$m" > "$m.t" && mv "$m.t" "$m"; done
printf '10:p#a:c:Not Answered Yet:%s:a1\n' $(( START + 600 )) > "$C/users/alice/history"
for m in "$C"/users/*/metrics.json; do jq -c "(.by_problem[]?) |= (.pending = true | del(.pending_min_epoch))" "$m" > "$m.t" && mv "$m.t" "$m"; done
rm -f "$C/var/placar.txt"; bash "$ROOT/score/build.sh" fts >/dev/null 2>&1   # SEM apagar o stamp
ck "campo ausente segura a estrela" '! star bob'
# e o recompute em massa (build.sh com a lib mais nova que o carimbo) volta a decidir pelo DADO:
# com a run antiga ainda na fila a estrela segue retida — agora pelo motivo certo, não por
# ignorância — e volta assim que a run é julgada como não-AC.
build
ck "recomputado: segue retido (run na fila)" '! star bob'
wa_alice; build
ck "julgada como WA: a estrela volta"        'star bob'

echo "== recompute em massa alcança PARTICIPANTE COMPARTILHADO (USERS_FROM) =="
# Bug antigo, achado ao levar isto p/ produção: o laço usava `list_users`, que enumera quem tem
# account.json LOCAL — e em contest com USERS_FROM o participante compartilhado tem dir local SEM
# account.json de propósito. No ensaio-times-2026 eram 12 de 79. Consequência silenciosa: editar
# o FREEZE_TIME não refazia a visão congelada desses times. Hoje o laço enumera quem tem HISTORY.
conf ""
mkdir -p "$C/users/carol"                       # dir local, SEM account.json (o do treino é a fonte)
printf '10:p#a:c:Accepted,100p:%s:c1\n' $(( START + 300 )) > "$C/users/carol/history"
rm -f "$C/users/carol/metrics.json"
build
ck "metrics do compartilhado foi gerado" '[[ -s "$C/users/carol/metrics.json" ]]'
ck "…e traz o campo novo"                'jq -e ".by_problem[\"p#a\"]|has(\"pending_min_epoch\")" "$C/users/carol/metrics.json" >/dev/null'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
