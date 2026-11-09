#!/bin/bash
# smoke-staff-test-tasks.sh — TAREFAS DE TESTE da impressão (09/11/2026; pedido do Fernando: medir a velocidade e o
# paralelismo das impressoras). Decisões do Ribas: o .staff cria SÓ para a própria sede e o admin para qualquer sede;
# PROIBIDO durante a prova; numeração À PARTE (T1…).
#   · criar: T1…Tn, `test:true`, sede de quem criou; 422 nos limites; 409 com PRINT=0 / sem o módulo baloes;
#   · visibilidade: a outra sede não vê nem age (fila, claim, PDF, arquivo cru); a mesma sede vê; sem escopo vê tudo;
#     o admin escolhe a sede ou "todas";
#   · a folha: PDF com N páginas + rosto, faixa "TESTE — NÃO ENTREGAR" (o tile da faixa existe no cache de letreiros);
#   · a medida: claim + processed de duas estações → resumo com tarefas/min por estação;
#   · durante a prova: criar = 409 test_blocked; a fila apaga as sobras (e audita);
#   · o seq real não pula; o relatório da prova não lista teste; a Central avisa; apagar (escopo) remove os arquivos.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
for b in paps ps2pdf pdfinfo magick; do command -v "$b" >/dev/null 2>&1 || { echo "SKIP: falta '$b' (cadeia de impressão)"; exit 0; }; done
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN"
NOW="$EPOCHSECONDS"; C="$FIX/tt"; P="$C/print-requests"; mkdir -p "$C/var" "$P"
conf(){ printf 'CONTEST_ID=tt\nCONTEST_TYPE=icpc\nLOCALE=pt\nCONTEST_MODULES=sedes,baloes\nCONTEST_START=%s\nCONTEST_END=%s\nPROBS=( x col#pa Alfa A col#pa )\n%s' "$1" "$2" "${3:-}" > "$C/conf"; }
conf $(( NOW + 3600 )) $(( NOW + 7200 ))
for u in tt.admin norte.staff norte2.staff sul.staff solto.staff time-n time-s; do fx_user "$C" "$u" p "$u"
  printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' tt "$u" "$u" "$NOW" > "$SESS/tok-$u"; done
jq -c '.team={name:"Time N",region:"Norte"}' "$C/users/time-n/account.json" > "$C/t" && mv "$C/t" "$C/users/time-n/account.json"
jq -c '.team={name:"Time S",region:"Sul"}'   "$C/users/time-s/account.json" > "$C/t" && mv "$C/t" "$C/users/time-s/account.json"
printf '%s' '{"norte.staff":["region:Norte"],"norte2.staff":["region:Norte"],"sul.staff":["region:Sul"]}' > "$P/staff-filters.json"
printf '7' > "$P/.seq"   # o seq REAL já está no 7: o teste não pode mexer nele

call(){ local b="${5:-}"; OUT="$(PATH_INFO="$1" REQUEST_METHOD="${3:-GET}" QUERY_STRING="contest=tt${4:+&$4}" HTTP_AUTHORIZATION="Bearer tok-$2" \
    REMOTE_ADDR=127.0.0.9 CONTENT_LENGTH="${#b}" bash "$ROUTER" <<<"$b" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${OUT:0:240}"; ((fail++)); fi; }
qids(){ call /contest/staff/queue "$1"; jq -r '[.requests[] | select(.test) | .seq] | join(",")' <<<"$BODY"; }

echo "== criar: numeração própria, sede de quem criou =="
call /contest/staff/test-tasks norte.staff POST "" '{"action":"create","count":3,"kind":"mixed","pages":2}'
ck "norte.staff cria 3: T1..T3, sede Norte"     '[[ "$(jq -r .range <<<"$BODY")" == "T1 T3" && "$(jq -c .scope <<<"$BODY")" == "[\"Norte\"]" ]]'
ck "o seq REAL não pulou"                        '[[ "$(cat "$P/.seq")" == 7 ]]'
ck "3 arquivos tst*.json com test:true"          '[[ "$(ls "$P"/tst*.json | wc -l)" == 3 && "$(jq -s "map(select(.test == true)) | length" "$P"/tst*.json)" == 3 ]]'
call /contest/staff/test-tasks norte.staff POST "" '{"action":"create","count":0,"kind":"print","pages":2}';   ck "count 0 = 422"  '[[ "$OUT" == *count_invalid* ]]'
call /contest/staff/test-tasks norte.staff POST "" '{"action":"create","count":201,"kind":"print","pages":2}'; ck "count 201 = 422" '[[ "$OUT" == *count_invalid* ]]'
call /contest/staff/test-tasks norte.staff POST "" '{"action":"create","count":1,"kind":"print","pages":21}';  ck "pages 21 = 422"  '[[ "$OUT" == *pages_invalid* ]]'
call /contest/staff/test-tasks norte.staff POST "" '{"action":"create","count":1,"kind":"x"}';               ck "tipo inválido"   '[[ "$OUT" == *kind_invalid* ]]'
call /contest/staff/test-tasks time-n POST "" '{"action":"create","count":1}';                               ck "time = 403"      '[[ "$OUT" == *staff_required* ]]'
call /contest/staff/test-tasks norte.staff POST "" '{"action":"create","count":1,"kind":"print","pages":1,"site":"Sul"}'
ck "o .staff NÃO escolhe a sede (site ignorado: segue Norte)" '[[ "$(jq -c .scope <<<"$BODY")" == "[\"Norte\"]" ]]'

echo "== visibilidade: a sede de quem criou =="
ck "norte.staff vê T1..T4"                       '[[ "$(qids norte.staff)" == "T1,T2,T3,T4" ]]'
ck "norte2.staff (mesma sede) vê T1..T4"         '[[ "$(qids norte2.staff)" == "T1,T2,T3,T4" ]]'
ck "sul.staff (outra sede) não vê nenhuma"       '[[ -z "$(qids sul.staff)" ]]'
ck "solto.staff (sem escopo) vê todas"           '[[ "$(qids solto.staff)" == "T1,T2,T3,T4" ]]'
T1="$(jq -r 'select(.seq == "T1") | .id' "$P"/tst*.json)"; T2="$(jq -r 'select(.seq == "T2") | .id' "$P"/tst*.json)"
call /contest/staff/print-action sul.staff POST "" "{\"id\":\"$T1\",\"action\":\"claim\"}"; ck "sul.staff não pega T1 (403)"       '[[ "$OUT" == *out_of_scope* ]]'
call /contest/staff/print-pdf sul.staff GET "id=$T1";                                      ck "sul.staff não baixa o PDF (403)"  '[[ "$OUT" == *out_of_scope* ]]'
call /contest/print-file sul.staff GET "id=$T1";                                           ck "sul.staff não baixa o arquivo (403)" '[[ "$OUT" == *forbidden* ]]'
call /contest/staff/test-tasks tt.admin POST "" '{"action":"create","count":1,"kind":"balloon","site":"Sul"}'
ck "admin cria para o Sul: T5"                   '[[ "$(jq -r .range <<<"$BODY")" == "T5 T5" ]] && [[ "$(qids sul.staff)" == "T5" ]]'
call /contest/staff/test-tasks tt.admin POST "" '{"action":"create","count":1,"kind":"balloon"}'
ck "admin \"todas\": T6 aparece para as duas sedes" '[[ "$(qids sul.staff)" == "T5,T6" && "$(qids norte.staff)" == *T6* ]]'
call /contest/staff/test-tasks tt.admin GET
ck "GET do admin lista as sedes do staff-filters" '[[ "$(jq -c .sites <<<"$BODY")" == "[\"Norte\",\"Sul\"]" ]]'

echo "== a folha: rosto + N páginas, faixa de teste =="
PDF="$(mktemp)"; PATH_INFO=/contest/staff/print-pdf REQUEST_METHOD=GET QUERY_STRING="contest=tt&id=$T1" HTTP_AUTHORIZATION="Bearer tok-norte.staff" \
  bash "$ROUTER" 2>/dev/null | python3 -c 'import sys
d=sys.stdin.buffer.read(); i=d.find(b"\r\n\r\n"); sys.stdout.buffer.write(d[i+4:])' > "$PDF"
ck "T1 (impressão de 2 páginas): PDF com 3 páginas (rosto + 2)" '[[ "$(pdfinfo "$PDF" 2>/dev/null | awk "/^Pages/{print \$2}")" == 3 ]]'
ck "o texto das páginas diz o que é"            'pdftotext "$PDF" - 2>/dev/null | grep -q "TESTE DE IMPRESSÃO — NÃO ENTREGAR" && pdftotext "$PDF" - 2>/dev/null | grep -q "página 2 de 2"'
source "$ROOT/api/v1/lib/print.sh" 2>/dev/null
ck "a faixa TESTE — NÃO ENTREGAR foi desenhada (tile em cache)" 'grep -lq . "$RUN"/print-cap/*.png 2>/dev/null && [[ -n "$(_pr_t pt test_band)" ]] && ls "$RUN"/print-cap/ | grep -q .'
call /contest/staff/print-pdf norte.staff GET "id=$T2"; ck "T2 (balão) gera a folha" '[[ "$OUT" == *"application/pdf"* ]]'

echo "== a medida: duas estações =="
for x in "$T1:norte.staff" "$T2:norte2.staff"; do id="${x%%:*}"; who="${x#*:}"
  call /contest/staff/print-action "$who" POST "" "{\"id\":\"$id\",\"action\":\"claim\"}"
  call /contest/staff/print-action "$who" POST "" "{\"id\":\"$id\",\"action\":\"processed\",\"mode\":\"auto\"}"; done
call /contest/staff/test-tasks norte.staff GET
ck "resumo: 2 impressas, por estação"           '[[ "$(jq -r ".summary.printed" <<<"$BODY")" == 2 && "$(jq -r "[.summary.stations[].by] | join(\",\")" <<<"$BODY")" == "norte.staff,norte2.staff" ]]'
ck "resumo: só o que a sede vê (T1..T4 + T6 = 5)" '[[ "$(jq -r ".summary.total" <<<"$BODY")" == 5 ]]'

echo "== a Central avisa; o relatório não lista teste =="
call /contest/admin/preflight tt.admin GET
ck "Central: aviso print_tests"                  '[[ "$(jq -r "[.checks[] | select(.id == \"print_tests\") | .level] | first" <<<"$BODY")" == warn ]]'

echo "== durante a prova: proibido; as sobras somem =="
conf $(( NOW - 60 )) $(( NOW + 3600 ))
call /contest/staff/test-tasks norte.staff POST "" '{"action":"create","count":1,"kind":"print","pages":1}'
ck "criar durante a prova = 409 test_blocked"    '[[ "$OUT" == *"Status: 409"* && "$OUT" == *test_blocked* ]]'
call /contest/staff/test-tasks tt.admin POST "" '{"action":"create","count":1,"kind":"print","pages":1}'
ck "nem o admin cria durante a prova"            '[[ "$OUT" == *test_blocked* ]]'
call /contest/staff/queue norte.staff
ck "a 1ª consulta da fila apaga as sobras"       '[[ "$(ls "$P"/tst* 2>/dev/null | wc -l)" == 0 && "$(jq -r "[.requests[] | select(.test)] | length" <<<"$BODY")" == 0 ]]'
ck "…e audita"                                   'grep -q "staff-test.*purge-at-start n=6" "$C/var/admin-audit.log"'
conf 0 0
call /contest/staff/test-tasks norte.staff POST "" '{"action":"create","count":2,"kind":"print","pages":1}'
ck "contest sem janela (START=0) não bloqueia; o contador segue: T7..T8" '[[ "$(jq -r .range <<<"$BODY")" == "T7 T8" ]]'

echo "== apagar: só o que a sede vê =="
conf $(( NOW + 3600 )) $(( NOW + 7200 ))
call /contest/staff/test-tasks tt.admin POST "" '{"action":"create","count":1,"kind":"balloon","site":"Sul"}'
call /contest/staff/test-tasks norte.staff POST "" '{"action":"delete"}'
ck "norte.staff apaga as 2 dele; a do Sul fica" '[[ "$(jq -r .deleted <<<"$BODY")" == 2 && "$(ls "$P"/tst*.json | wc -l)" == 1 ]]'
ck "nenhum .src/.pdf/.lock órfão do Norte"       '[[ "$(ls "$P"/tst* | wc -l)" -le 3 ]]'
call /contest/staff/test-tasks tt.admin POST "" '{"action":"delete"}'
ck "o admin apaga o resto"                       '[[ "$(jq -r .deleted <<<"$BODY")" == 1 && -z "$(ls "$P"/tst* 2>/dev/null)" ]]'

echo "== sem impressão / sem balões =="
conf $(( NOW + 3600 )) $(( NOW + 7200 )) $'PRINT=0\n'
call /contest/staff/test-tasks norte.staff POST "" '{"action":"create","count":1,"kind":"print"}';   ck "PRINT=0: teste de impressão = 409" '[[ "$OUT" == *print_disabled* ]]'
call /contest/staff/test-tasks norte.staff POST "" '{"action":"create","count":1,"kind":"balloon"}'; ck "PRINT=0: balão segue"            '[[ "$(jq -r .created <<<"$BODY")" == 1 ]]'
sed -i 's/^CONTEST_MODULES=.*/CONTEST_MODULES=sedes/' "$C/conf"
call /contest/staff/test-tasks norte.staff POST "" '{"action":"create","count":1,"kind":"balloon"}'; ck "sem o módulo baloes: 409"        '[[ "$OUT" == *balloons_disabled* ]]'

echo "== o relatório da prova não lista teste =="
conf $(( NOW - 7200 )) $(( NOW - 3600 ))
printf '{"id":"real1","seq":8,"login":"time-n","team":"Time N","kind":"print","filename":"a.c","time":%s,"status":"delivered","pages":1}\n' "$NOW" > "$P/real1.json"
cp "$P"/tst*.json "$RUN/keep.json" 2>/dev/null
if ( cd "$ROOT/score" && CONTESTSDIR="$FIX" bash report-gen.sh tt "$RUN/rep" >/dev/null 2>&1 ) && [[ -s "$RUN/rep/staff-tasks.html" ]]; then
  ck "staff-tasks.html: a real sim, a de teste não" 'grep -q "a.c" "$RUN/rep/staff-tasks.html" && ! grep -q "T[0-9]" <(grep -o "class=\"place\">[^<]*" "$RUN/rep/staff-tasks.html")'
else ck "report-gen gerou staff-tasks.html" false; fi

echo; echo "RESULT: $pass passed, $fail failed"; (( fail == 0 ))
