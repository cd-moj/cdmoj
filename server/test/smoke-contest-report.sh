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
jq -c '.team={name:"Time Alice",univ_short:"UFRJ",univ_full:"Univ Federal do RJ",flag:"br-rj",region:"Rio"}' "$C/users/alice/account.json" > "$C/u.tmp" && mv "$C/u.tmp" "$C/users/alice/account.json"
jq -c '.team={name:"Time Bob",univ_short:"UFSC",univ_full:"Univ Federal de SC",flag:"br-sc",region:"Floripa"}'  "$C/users/bob/account.json"   > "$C/u.tmp" && mv "$C/u.tmp" "$C/users/bob/account.json"
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
# --- placar não rola para o lado (colgroup + fixed) ---
ck "placar: colgroup completo (N+5 cols)" '[[ "$(grep -o "<col class=\"c-[a-z]*\">" "$R/index.html" | wc -l)" == 7 ]]'
ck "placar: --nprob carimbado na tabela"  'grep -q "table class=\"score\" style=\"--nprob:2" "$R/index.html"'
ck "placar: embrulho SEM rolagem"         'grep -q "board-wrap.*table class=\"score\"" "$R/index.html" && ! grep -q "tblwrap.*table class=\"score\"" "$R/index.html"'
ck "placar: número em .pv (fonte menor)"  'grep -qE "<td class=\"cell ok\"[^>]*>(<span class=\"fts\">[^<]*</span>)?<span class=\"pv\">1/70</span>" "$R/index.html"'
ck "placar: CSS sem nowrap/min-width"     '! grep -qE "table.score td.cell\{[^}]*(nowrap|min-width)" "$R/index.html"'
ck "placar: penalidade sobrevive no celular" 'grep -q "td.cell:not(.tot):not(.pen) .pv { display:none" "$R/index.html" && ! grep -q "table.score td.cell .pv { display:none" "$R/index.html"'
ck "placar: login do time no title"       'grep -q "class=\"team\" title=\"[^\"]*·[^\"]*\"" "$R/index.html" && ! grep -q "<span class=\"u\">" "$R/index.html"'
# --- filtros do placar (bandeira, universidade, sede, busca) ---
ck "filtro: dado na própria linha"        'grep -q "data-flag=\"br-sc\"" "$R/index.html" && grep -q "data-fname=\"Santa Catarina\"" "$R/index.html" && grep -q "data-univ=\"UFSC\"" "$R/index.html" && grep -q "data-region=\"Floripa\"" "$R/index.html" && grep -q "data-search=\"time bob ufsc" "$R/index.html"'
ck "filtro: os 4 controles + contador"    'grep -q "id=\"fFlag\"" "$R/index.html" && grep -q "id=\"fUniv\"" "$R/index.html" && grep -q "id=\"fRegion\"" "$R/index.html" && grep -q "id=\"fQ\"" "$R/index.html" && grep -q "id=\"fCount\"" "$R/index.html"'
ck "filtro: fallback sem JS"              'grep -q "<noscript><style>.fbar{display:none}" "$R/index.html"'
# script inline roda no parse: antes das <section> o querySelectorAll voltava vazio
ck "filtro: script DEPOIS dos placares"   '[[ "$(grep -n "</section>" "$R/index.html" | tail -1 | cut -d: -f1)" -lt "$(grep -n "id=.fbar.\|<script>" "$R/index.html" | grep "<script>" | tail -1 | cut -d: -f1)" ]]'
ck "sem coorte: um placar, sem seletor"   '[[ "$(grep -c "class=\"board-view\"" "$R/index.html")" == 1 ]] && ! grep -q "id=\"fView\"" "$R/index.html" && ! grep -q "class=\"plg\"" "$R/index.html"'
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

# --- i18n: o mesmo relatório com o contest em inglês -------------------------------------
printf 'LOCALE=en\n' >> "$C/conf"
EN="$FIX/ren"; CONTESTSDIR="$FIX" MOJ_PROBLEMS_DIR="$PKG" bash "$ROOT/score/report-gen.sh" rp "$EN" >/dev/null 2>&1
ck "EN: chrome traduzido"        'grep -q ">🏆 Scoreboard<" "$EN/index.html" && grep -q ">📊 Statistics<" "$EN/index.html"'
ck "EN: índice traduzido"        'grep -q "<dt>Contest</dt>" "$EN/index.html" && grep -q "<th>Author</th>" "$EN/index.html"'
ck "EN: placar traduzido"        'grep -q "<th>Team</th>" "$EN/index.html" && grep -q "<th>Pen.</th>" "$EN/index.html"'
ck "EN: runs/clar/staff/infra"   'grep -q "<th>Verdict</th>" "$EN/runs.html" && grep -q "<th>Type</th>" "$EN/staff-tasks.html" && grep -q "Judging infrastructure" "$EN/infra.html"'
ck "EN: documentos traduzidos"   'grep -q "Problem set" "$EN/documentos.html" && grep -q "<th>Language</th>" "$EN/documentos.html"'
ck "EN: html lang=en"            'grep -q "<html lang=\"en\">" "$EN/index.html"'
ck "EN: filtros traduzidos"      'grep -q "<label>Flag: <select id=\"fFlag\">" "$EN/index.html" && grep -q "<label>Site: <select id=\"fRegion\">" "$EN/index.html" && grep -q "data-tpl=\"Showing %s of %s teams\"" "$EN/index.html"'
ck "EN: sem PT vazando"          '! grep -qE "<dt>Competição</dt>|<th>Equipe</th>|Tarefas do staff|>Bandeira:|>Sede:" "$EN/index.html" "$EN/staff-tasks.html"'
ck "EN: estatística em inglês"   'grep -q "\"en\"" "$EN/statistics.html"'

# --- COORTES: um placar por visão (o build.sh gera um TXT por coorte) --------------------
# O relatório não pode filtrar o TXT pronto (a estrela de first-to-solve é mínimo global —
# lib/cohorts.sh): o seletor TROCA de placar. `all` == `public` aqui (as duas coortes são
# públicas) ⇒ dedup por conteúdo deixa 3 placares.
sed -i '/^LOCALE=en$/d' "$C/conf"
jq -cn '{version:1, results_released:false, cohorts:[
   {id:"ind", name:"Individual", regex:"^alice", public:true, ranking:true, default:true, sees:["ind"]},
   {id:"tim", name:"Times", regex:"^bob", public:true, ranking:true, sees:["tim"]}]}' > "$C/cohorts.json"
CO="$FIX/rco"; CONTESTSDIR="$FIX" MOJ_PROBLEMS_DIR="$PKG" bash "$ROOT/score/report-gen.sh" rp "$CO" >/dev/null 2>&1
ck "coorte: um placar por visão"      '[[ "$(grep -c "class=\"board-view\"" "$CO/index.html")" == 3 ]] && grep -q "data-view=\"ind\"" "$CO/index.html" && grep -q "data-view=\"tim\"" "$CO/index.html"'
ck "coorte: só o 1º placar visível"   '[[ "$(grep -c "class=\"board-view\" data-view=\"[a-z]*\" data-label=\"[^\"]*\" hidden" "$CO/index.html")" == 2 ]]'
ck "coorte: seletor com o NOME dela"  'grep -q "id=\"fView\"" "$CO/index.html" && grep -q "<option value=\"ind\">Individual</option>" "$CO/index.html" && grep -q "<option value=\"tim\">Times</option>" "$CO/index.html"'
ck "coorte: dedup de placar idêntico" '! grep -q "data-view=\"all\"" "$CO/index.html"'
ck "coorte: posição na coorte + geral" 'grep -q "#<span class=\"plg\">Geral</span>" "$CO/index.html" && grep -qE "<td class=\"place\">1<span class=\"plg\"[^>]*>2</span>" "$CO/index.html"'
ck "coorte: placar geral sem 2ª posição" 'awk "/data-view=\"public\"/,/<\/section>/" "$CO/index.html" | grep -q "<td class=\"place\">1</td>"'
ck "coorte: congelado também tem visões" '[[ "$(grep -c "class=\"board-view\"" "$CO/score-frozen.html")" == 3 ]]'
ck "coorte: segue offline"            '! grep -rqE "<script src=|import |fetch\(" "$CO"'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
