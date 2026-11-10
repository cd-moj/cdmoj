#!/bin/bash
# smoke-print-html.sh — a FOLHA EM HTML (protótipo de 09/11/2026: lib/print.sh pr_html + /contest/staff/print-html,
# para o contest com PRINT_FORMAT=html; a estação imprime no navegador, sem PDF no servidor).
#   · pedido de texto: 200 text/html com a CSP (cabeçalho E meta), o login, a sede, o nº e o código numerado;
#   · código HOSTIL (`</pre><script>`): sai escapado, nenhum <script> na página;
#   · arquivo em CP1252 (Dev-C++): o acento sai certo (convertido p/ UTF-8);
#   · pedido que não é texto (PDF/imagem): 409 html_unsupported (a estação usa o PDF);
#   · balão: a letra, o SVG do balão na cor da tarefa; primeiro da sede = a estrela DESENHADA (SVG);
#   · tarefa de teste: a faixa "TESTE — NÃO ENTREGAR";
#   · o gate é o do print-pdf: .cstaff 403, staff de outra sede 403, time 403;
#   · o settings grava PRINT_FORMAT (html | pdf apaga a linha) e o /contest/basic diz `print_format`.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" MOJ_JOBS_SYNC=1
NOW="$EPOCHSECONDS"
C="$FIX/ph"; P="$C/print-requests"; mkdir -p "$C/var" "$P"
{ printf 'CONTEST_ID=ph\nCONTEST_TYPE=icpc\nCONTEST_MODULES=sedes,baloes\nLOCALE=pt\nCONTEST_START=%s\nCONTEST_END=%s\nUSER_STORE=v2\n' "$((NOW-3600))" "$((NOW+3600))"
  printf 'PROBS=( cdmoj apc#p1 Um A apc#p1 )\n'; } > "$C/conf"
for u in ph.admin norte.staff sul.staff chefe.cstaff; do fx_user "$C" "$u" p "$u"; done
fx_user "$C" time1 x "Time 1"; fx_user "$C" time2 x "Time 2"
jq -c '.team={name:"Os Ponteiros",region:"Norte",univ_full:"Universidade do Norte"}' "$C/users/time1/account.json" > "$C/t" && mv "$C/t" "$C/users/time1/account.json"
jq -c '.team={name:"Time Sul",region:"Sul"}' "$C/users/time2/account.json" > "$C/t" && mv "$C/t" "$C/users/time2/account.json"
printf '%s' '{"norte.staff":["region:Norte"],"sul.staff":["region:Sul"],"chefe.cstaff":["region:Norte"]}' > "$P/staff-filters.json"
for p in "ph.admin adm" "norte.staff stn" "sul.staff sts" "chefe.cstaff cst" "time1 t1"; do set -- $p
  printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' ph "$1" "$1" "$NOW" > "$SESS/$2"; done
call(){ # <path> <method> <token> [query] [body]
  local b="${5:-}"
  OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="contest=ph${4:+&$4}" HTTP_AUTHORIZATION="Bearer $3" \
    CONTENT_LENGTH="${#b}" REMOTE_ADDR=127.0.0.9 TEAM_HOST_LOCK=0 bash "$ROUTER" <<<"$b" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
task(){ # <id> <login> <arquivo> <kind> [campos-json extra]  (o .src vem de $SRCF)
  local extra="${5:-{\}}"
  jq -cn --arg id "$1" --arg l "$2" --arg fn "$3" --arg k "$4" --argjson x "$extra" \
    '{id:$id, seq:42, login:$l, fullname:$l, team:"Os Ponteiros", univ:"Universidade do Norte", kind:$k, filename:$fn,
      mime:"text/x-c", size:10, time:1, status:"pending", pages:0} + $x' > "$P/$1.json"
  [[ "$4" == print ]] && cp "$SRCF" "$P/$1.src"; return 0; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${OUT:0:300}"; ((fail++)); fi; }

echo "== pedido de texto =="
SRCF="$FIX/a.c"; printf '#include <stdio.h>\nint main(void){\n\tputs("oi"); // </pre><script>alert(1)</script>\n}\n' > "$SRCF"
task p1 time1 a.c print
call /contest/staff/print-html GET stn "id=p1"
ck "200 text/html"                                  '[[ "$OUT" == *"Status: 200"* && "$OUT" == *"Content-Type: text/html"* ]]'
ck "CSP no cabeçalho e na página"                   '[[ "$OUT" == *"Content-Security-Policy: default-src '"'"'none'"'"'"* && "$BODY" == *"http-equiv=\"Content-Security-Policy\""* ]]'
ck "o login, o time, a sede e o nº"                 '[[ "$BODY" == *">time1<"* && "$BODY" == *"Os Ponteiros"* && "$BODY" == *"sede: Norte"* && "$BODY" == *"tarefa nº 42"* ]]'
ck "o código numerado"                              '[[ "$BODY" == *"  1 | </span>#include &lt;stdio.h&gt;"* ]]'
ck "código hostil escapado: nenhum <script>"        '[[ "$BODY" != *"<script"* && "$BODY" == *"&lt;script&gt;alert(1)&lt;/script&gt;"* ]]'
ck "o rodapé identifica a folha solta"              '[[ "$BODY" == *"class=\"foot\">time1  -  a.c  -  tarefa #42<"* ]]'
printf 'int main(){ // solu\xe7\xe3o\n}\n' > "$FIX/cp.c"; SRCF="$FIX/cp.c"; task p2 time1 cp.c print
call /contest/staff/print-html GET stn "id=p2"
ck "CP1252 sai em UTF-8"                            '[[ "$BODY" == *"solução"* ]]'
printf '%%PDF-1.4\n%%\xe2\xe3\xcf\xd3\n1 0 obj\n<<>>\nendobj\n' > "$FIX/x.pdf"; SRCF="$FIX/x.pdf"; task p3 time1 x.pdf print
call /contest/staff/print-html GET stn "id=p3"
ck "PDF: 409 html_unsupported (a estação usa o PDF)" '[[ "$OUT" == *"Status: 409"* && "$OUT" == *html_unsupported* ]]'

echo "== balão =="
task b1 time1 "" balloon '{"short":"C","color_hex":"FF0000","color_name":"vermelho","color_lang":"pt","first_site":true}'
call /contest/staff/print-html GET stn "id=b1"
ck "a letra e o balão na cor"                       '[[ "$BODY" == *"class=\"short\">C<"* && "$BODY" == *"fill=\"#FF0000\""* && "$BODY" == *"vermelho"* ]]'
ck "primeiro da sede: a faixa com a estrela em SVG" '[[ "$BODY" == *"PRIMEIRO DA SEDE"* && "$BODY" == *"<polygon fill=\"#B8860B\""* ]]'
task b2 time1 "" balloon '{"short":"D","color_hex":"x<y\"","first_site":false}'
call /contest/staff/print-html GET stn "id=b2"
ck "sem a faixa quando não é o primeiro"            '[[ "$BODY" != *"PRIMEIRO DA SEDE"* ]]'
ck "cor hostil vira só hex"                         '[[ "$BODY" != *"x<y"* ]]'

echo "== tarefa de teste =="
task t1 "" "" balloon '{"test":true,"test_scope":["Norte"],"short":"A","color_hex":"FFFFFF"}'
call /contest/staff/print-html GET stn "id=t1"
ck "a faixa TESTE — NÃO ENTREGAR"                   '[[ "$BODY" == *"TESTE — NÃO ENTREGAR"* && "$BODY" == *"TESTE DE IMPRESSÃO"* ]]'

echo "== o gate do print-pdf =="
call /contest/staff/print-html GET sts "id=p1"; ck "staff de outra sede: 403"  '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/staff/print-html GET cst "id=p1"; ck ".cstaff: 403"              '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/staff/print-html GET t1 "id=p1";  ck "time: 403"                 '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/staff/print-html GET adm "id=p1"; ck "admin: 200"                '[[ "$OUT" == *"Status: 200"* ]]'
call /contest/staff/print-html GET adm "id=../x"; ck "id ruim: 400"            '[[ "$OUT" == *"Status: 400"* ]]'

echo "== a opção do contest =="
call /contest/basic GET adm
ck "basic: print_format pdf (padrão)"               '[[ "$(jq -r .print_format <<<"$BODY")" == pdf ]]'
call /contest/admin/settings POST adm "" '{"print_format":"html"}'
ck "settings html grava PRINT_FORMAT=html"          'grep -q "^PRINT_FORMAT=html$" "$C/conf"'
call /contest/basic GET adm
ck "basic: print_format html"                       '[[ "$(jq -r .print_format <<<"$BODY")" == html ]]'
call /contest/admin/settings POST adm "" '{"print_format":"svg"}'
ck "valor estranho: 422"                            '[[ "$OUT" == *print_format_invalid* ]]'
call /contest/admin/settings POST adm "" '{"print_format":"pdf"}'
ck "pdf apaga a linha"                              '! grep -q "^PRINT_FORMAT=" "$C/conf"'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
