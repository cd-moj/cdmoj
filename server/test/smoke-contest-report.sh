#!/bin/bash
# Relatório estático da prova (GET /contest/admin/report): gera o tar.gz, confere as
# páginas, o freeze, a canonização de veredicto e — o teste que importa — o NÃO-VAZAMENTO
# (código-fonte plantado, mojlog, senha, asker de clarification, .src de impressão).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; EXT="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$EXT"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"

C="$FIX/rp"; mkdir -p "$C/var" "$C/enunciados" "$C/clarifications" "$C/print-requests"
T0=$(( $(date +%s) - 7200 )); TE=$(( T0 + 18000 )); FZ=$(( T0 + 3600 ))
{ printf 'CONTEST_ID=rp\nCONTEST_TYPE=icpc\nCONTEST_NAME=Prova\\ Smoke\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\nFREEZE_TIME=%s\n' "$T0" "$TE" "$FZ"
  printf "PROBS=( x col#pa Alfa A col#pa x col#pb Beta B col#pb )\n"; } > "$C/conf"
fx_user "$C" rp.admin p "Admin"
fx_user "$C" alice a "Time Alice"
fx_user "$C" bob b "Time Bob"
fx_user "$C" rp.cstaff s "Chefe de Sede"
# bandeira de ESTADO (br-rj): o código que o relatório antigo imprimia como TEXTO
jq -c '.team={name:"Time Alice",univ_short:"UFRJ",flag:"br-rj"}' "$C/users/alice/account.json" > "$C/u.tmp" && mv "$C/u.tmp" "$C/users/alice/account.json"
jq -c '.team={name:"Time Bob",univ_short:"UFSC",flag:"br-sc"}'  "$C/users/bob/account.json"   > "$C/u.tmp" && mv "$C/u.tmp" "$C/users/bob/account.json"
# pacote com AUTOR (2 linhas) + documentos: 1 publicado, 1 gerado e NÃO publicado
PKG="$FIX/probs"; mkdir -p "$PKG/col/pa"
printf 'Bruno Ribas\nMaria da Silva\n' > "$PKG/col/pa/author"
mkdir -p "$C/docs"
printf '%%PDF-1.4 caderno\n' > "$C/docs/contest.pt.pdf"
printf '%%PDF-1.4 SEGREDO_DOC_NAO_PUBLICADO\n' > "$C/docs/editorial.pt.pdf"
jq -cn '{caderno_version:"v1.0",published:["contest.pt"]}' > "$C/docs/config.json"
m(){ echo $(( T0 + $1*60 )); }
{ printf '10:col#pa:C:Accepted,100p:%s:sA1\n' "$(m 10)"
  printf '70:col#pb:CPP:Accepted,100p:%s:sA2\n' "$(m 70)"; } > "$C/users/alice/history"  # pós-freeze
{ printf '40:col#pb:C:Wrong,60p. Pontos | 30 | 0 |:%s:sB1\n' "$(m 40)"
  printf '80:col#pa:C:Not Answered Yet:%s:sB2\n' "$(m 80)"; } > "$C/users/bob/history"
printf '5:col#pa:C:Accepted,100p:%s:sZ1\n' "$(m 5)" > "$C/users/rp.admin/history"        # excluído
printf '6:col#pa:C:Accepted,100p:%s:sS1\n' "$(m 6)" > "$C/users/rp.cstaff/history"       # excluído (cstaff!)
jq -cn --arg id sA1 --argjson f "$(( $(m 10) + 25 ))" \
  '{id:$id, finalized_at:$f, duration_s:4, host:"j1", tests:[{name:"t01"}], report_html:"NAO-DIVULGAR", tl_used:3}' \
  > "$C/users/alice/results/sA1.json"
printf 'int main(){ /* SEGREDO_FONTE_XYZ */ }\n' > "$C/users/alice/submissions/sA1.c"
printf '<html>SEGREDO_LOG_XYZ</html>\n' > "$C/users/alice/mojlog/sA1.html"
jq -cn --argjson t "$(m 20)" '{id:"c1", time:$t, problem:"A", login:"alice", question:"Limite?",
  public:true, answer:"Sim.", answered_by:"zeca.judge", answered_at:($t+60)}' > "$C/clarifications/c1.json"
jq -cn --argjson t "$(m 22)" '{id:"p1", seq:1, login:"alice", fullname:"Time Alice", team:"Time Alice",
  univ:"U", filename:"main.c", mime:"text/x-c", size:9, time:$t, status:"pending", pages:1}' \
  > "$C/print-requests/p1.json"
printf 'SEGREDO_PRINT_XYZ\n' > "$C/print-requests/p1.src"
printf '<!DOCTYPE html><html><body><h1>Alfa</h1></body></html>\n' > "$C/enunciados/col#pa.html"
touch "$C/var/.score-dirty"
printf 'CONTEST=rp\nLOGIN=rp.admin\nLOGINAT=1\n' > "$SESS/adm"
printf 'CONTEST=rp\nLOGIN=alice\nLOGINAT=1\n' > "$SESS/usr"

callf(){ PATH_INFO="$1" REQUEST_METHOD=GET QUERY_STRING="$3" HTTP_AUTHORIZATION="Bearer $2" \
  CONTESTSDIR="$FIX" SESSIONDIR="$SESS" MOJ_PROBLEMS_DIR="$PKG" bash "$ROUTER" </dev/null > "$4" 2>/dev/null; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; ((fail++)); fi; }

RESP="$FIX/resp.bin"
callf /contest/admin/report adm 'contest=rp' "$RESP"
ck "200 + application/gzip" 'head -c 200 "$RESP" | grep -q "Status: 200" && head -c 200 "$RESP" | grep -q "application/gzip"'
# corpo binário = depois da linha em branco dos headers CGI (contagem de bytes em C)
off=0
while IFS= read -r hline; do
  off=$(( off + ${#hline} + 1 ))
  [[ "$hline" == $'\r' || -z "$hline" ]] && break
done < <(LC_ALL=C head -c 1000 "$RESP")
tail -c +$(( off + 1 )) "$RESP" > "$FIX/rel.tar.gz"
ck "tar.gz íntegro"          'tar -tzf "$FIX/rel.tar.gz" >/dev/null 2>&1'
tar -xzf "$FIX/rel.tar.gz" -C "$EXT" 2>/dev/null
R="$EXT/relatorio-rp"
for p in index.html runs.html score-frozen.html clarifications.html statistics.html staff-tasks.html infra.html statements/A.html; do
  ck "página $p" '[[ -s "$R/'"$p"'" ]]'
done
ck "index: placar ABERTO mostra AC pós-freeze (1/70)"  'grep -q "1/70" "$R/index.html"'
ck "frozen: NÃO mostra o AC pós-freeze"                '! grep -q "1/70" "$R/score-frozen.html"'
ck "runs: veredicto canonizado (Wrong Answer)"         'grep -q ">Wrong Answer<" "$R/runs.html"'
# o score cru não pode aparecer NO CONTEÚDO (o CSS do MOJ, inlinado desde a reforma visual,
# tem "260px"/"760px" — casar o arquivo inteiro era falso-positivo). Olha só o texto das células.
ck "runs: sem a string crua com score (60p)"           '! grep -qE ">[^<]*60p" "$R/runs.html"'
ck "runs: pendente intacto"                            'grep -q "Not Answered Yet" "$R/runs.html"'
ck "runs: privilegiado excluído (rp.admin)"            '! grep -q "rp.admin" "$R/runs.html"'
# --- não-vazamento (o que importa) ---
ck "sem código-fonte plantado"      '! grep -rq "SEGREDO_FONTE_XYZ" "$R"'
ck "sem mojlog plantado"            '! grep -rq "SEGREDO_LOG_XYZ" "$R"'
ck "sem .src de impressão"          '! grep -rq "SEGREDO_PRINT_XYZ" "$R" && [[ -z "$(find "$R" -name "*.src")" ]]'
ck "sem report_html dos results"    '! grep -rq "NAO-DIVULGAR" "$R"'
ck "sem password"                   '! grep -rq "password" "$R"'
ck "clarifications: asker anônimo"  '! grep -q "alice" "$R/clarifications.html"'
ck "clarifications: sem answered_by" '! grep -rq "zeca.judge" "$R"'
ck "offline: sem script externo/ESM/fetch" '! grep -rqE "<script src=|import |fetch\(" "$R"'
# --- reforma visual/conteúdo (2026-08) ---
ck "visual MOJ: topbar + ui.css inlinado"  'grep -q "class=\"topbar\"" "$R/index.html" && grep -q "linear-gradient(105deg" "$R/index.html"'
ck "bandeira de ESTADO vira SVG embutido"  'grep -q "flag-mini\" src=\"data:image/svg+xml;base64," "$R/index.html"'
ck "bandeira NÃO sai como texto cru"       '! grep -qE ">br-rj<|>br-sc<" "$R/index.html"'
ck "bandeira com o NOME no title"          'grep -q "alt=\"Rio de Janeiro\"" "$R/index.html" && grep -q "alt=\"Santa Catarina\"" "$R/index.html"'
ck "placar: coluna de penalidade"          'grep -q ">Penal.<" "$R/index.html"'
ck "problemas: coluna Autor preenchida"    'grep -q ">Autor<" "$R/index.html" && grep -q "Bruno Ribas, Maria da Silva" "$R/index.html"'
ck "runs: cstaff excluído"                 '! grep -q "rp.cstaff" "$R/runs.html"'
ck "estatísticas: mesmas seções do painel" 'grep -q "statsSections" "$R/statistics.html" && grep -q "function barChart" "$R/statistics.html"'
ck "estatísticas: fallback sem JS"         'grep -q "<noscript>" "$R/statistics.html"'
ck "estatísticas: nome do 1º a resolver"   'grep -q "first_solver_name" "$R/statistics.html"'
ck "bundle inlinado sem import/export"     '! grep -qE "^(import|export) " "$R/statistics.html"'
ck "documentos: aba com o PUBLICADO"       '[[ -s "$R/documentos.html" ]] && [[ -s "$R/documentos/contest.pt.pdf" ]]'
# a aba só entra na nav se documentos.html já existir quando as outras páginas são escritas
ck "documentos: link na navegação"        'grep -q "documentos.html" "$R/index.html" && grep -q "documentos.html" "$R/statistics.html"'
ck "documentos: NÃO leva o não-publicado"  '[[ ! -e "$R/documentos/editorial.pt.pdf" ]] && ! grep -rq "SEGREDO_DOC_NAO_PUBLICADO" "$R"'
# --- gates ---
callf /contest/admin/report usr 'contest=rp' "$FIX/r2.bin"
ck "não-admin → 403" 'head -c 100 "$FIX/r2.bin" | grep -q "Status: 403"'
( exec 9>"$C/var/.report.lock"; flock 9; sleep 4 ) &
LOCKPID=$!; sleep 0.5
callf /contest/admin/report adm 'contest=rp' "$FIX/r3.bin"
ck "geração concorrente → 429 busy" 'head -c 100 "$FIX/r3.bin" | grep -q "Status: 429"'
wait "$LOCKPID" 2>/dev/null

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
