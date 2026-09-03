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
fx_user "$C" bob b '<script>alert(1)</script> Bob'   # nome HOSTIL (LATAM 2026 teve um assim): tem de sair escapado em HTML e nunca fechar um <script>
fx_user "$C" rp.cstaff s "Chefe de Sede"
# bandeira de ESTADO (br-rj): o código que o relatório antigo imprimia como TEXTO
jq -c '.team={name:"Time Alice",univ_short:"UFRJ",univ_full:"Univ Federal do RJ",flag:"br-rj",region:"Rio"}' "$C/users/alice/account.json" > "$C/u.tmp" && mv "$C/u.tmp" "$C/users/alice/account.json"
jq -c '.team={name:"<script>alert(1)</script> Bob",univ_short:"UFSC",univ_full:"Univ Federal de SC",flag:"br-sc",region:"Floripa </script>"}'  "$C/users/bob/account.json"   > "$C/u.tmp" && mv "$C/u.tmp" "$C/users/bob/account.json"
# foto de time (R5): entra como MINIATURA em fotos/<login>.webp — só no placar ABERTO
convert -size 40x40 xc:red "$C/users/alice/photo.png" 2>/dev/null || printf 'x' > /dev/null
# árvore de sedes: o select de Sede da ESTATÍSTICA espelha o do placar (RTREE embutido)
jq -n '[{name:"Brasil", regex:"^(alice|bob)$", subregions:[{name:"Rio", regex:"^alice$"}, {name:"Floripa </script>", regex:"^bob$"}]}]' > "$C/regions.json"   # sede com "</script>" no nome
# cache do nutellaboot (mínimo): a página mlinux.html do relatório nasce dele — SEM MACs
# shape do relatório 2.0 (pop/ram_bands/ed_*/profiles/pressure/rank_ed); `teams`, `machines`,
# `_rows` na sede são ISCA: nenhum pode vazar p/ o mlinux.html
jq -n '{version:2, collected_at:1788000000, window:{start:1787990000, end:1788010000},
  contest:{start:1787993600, end:1788007000}, link:{mode:"ua", linked:1, teams:1, coverage:100}, skipped:[],
  global:{machines_total:2, seen:2, firewall_off:0, screen_lock:0, alerts:0, disk_high:0, bound:0,
    pop:{seen:2, used:2, linked:1, chosen:1, ranked:1, tm:2, teams:1},
    ram_total_mb:23436, cores_total:12, ram_sum_tm:23436, ram_n_tm:2, ram_avg_sites:11718,
    cpu:{"Intel(R) Core(TM) i5-8400 CPU @ 2.80GHz":1,"12th Gen Intel(R) Core(TM) i7-12700":1}, cpu_tm:{"Intel(R) Core(TM) i5-8400 CPU @ 2.80GHz":1,"12th Gen Intel(R) Core(TM) i7-12700":1},
    ram_bands:{"8":1,"16":1}, ram_bands_all:{"8":1,"16":1},
    editors:{code:130}, editors_total_min:195, editors_machines:{code:2},
    ed_min:{code:150}, ed_min_total:150, ed_adopt:{code:2}, ed_groups:{vscode:2}, ed_count:{"1":2}, profiles:{vscode:2},
    ld_sum:40, ld_n:80, ld_max:1.2, mem_sum:3200, mem_n:80, sw_sum:8000, sw_n:80,
    pressure:{"8|vscode":{n:1, mem_sum:2000, mem_n:40, sw_sum:8000, sw_n:40, sw_max:400, mem0_sum:450, mem0_n:10, mem4_sum:600, mem4_n:10,
                          series:[{t:0, mem_sum:900, mem_n:20, sw_sum:3000, sw_n:20},{t:1800, mem_sum:1100, mem_n:20, sw_sum:5000, sw_n:20}]}},
    rank_ed:{n:1, all:{n:1, ed:{code:1}, grp:{vscode:1}, prof:{vscode:1}}, top30:{n:1, ed:{code:1}, grp:{vscode:1}, prof:{vscode:1}},
             q1:{n:1, ed:{code:1}, grp:{vscode:1}, prof:{vscode:1}}, p10:{n:1, ed:{code:1}, grp:{vscode:1}, prof:{vscode:1}}},
    series:[{t:1787990400, act:2, mem_sum:40, mem_n:2, ld_sum:1.0, ld_n:2, ld_max:0.7, sw_sum:100, sw_n:2, fw_off:0, ed:{code:1}}]},
  by_node:{Brasil:{machines_total:2, seen:2, ram_total_mb:23436, cores_total:12, pop:{seen:2, used:2, linked:1, chosen:1, ranked:1, tm:2, teams:1},
    ram_sum_tm:23436, ram_n_tm:2, ram_avg_sites:11718,
    cpu:{"Intel i5":1,"Intel i7":1}, cpu_tm:{"Intel i5":1,"Intel i7":1}, ram_bands:{"8":1,"16":1}, ram_bands_all:{"8":1,"16":1}, editors:{code:130},
    editors_total_min:195, editors_machines:{code:2}, ed_adopt:{code:2}, ed_groups:{vscode:2}, ed_count:{"1":2}, profiles:{vscode:2},
    pressure:{}, rank_ed:{n:1, all:{n:1,ed:{},grp:{},prof:{}}, top30:{n:1,ed:{},grp:{},prof:{}}, q1:{n:1,ed:{},grp:{},prof:{}}, p10:{n:1,ed:{},grp:{},prof:{}}}, series:[]}},
  sedes:[{id:"26brxrio", name:"Rio", country:"br", fullname:"Rio", teams:["alice"],
    machines_total:2, seen:2, firewall_off:0, screen_lock:0, alerts:0, disk_high:0, bound:0,
    pop:{seen:2, used:2, linked:1, chosen:1, ranked:1, tm:2, teams:1},
    ram_total_mb:23436, cores_total:12, ram_avg_mb:11718, cores_avg:6, ram_sum_tm:23436, ram_n_tm:2,
    cpu:{"Intel i5":1,"Intel i7":1}, cpu_tm:{"Intel i5":1,"Intel i7":1}, ram_bands:{"8":1,"16":1}, ram_bands_all:{"8":1,"16":1}, editors:{code:130},
    editors_total_min:195, editors_machines:{code:2}, ed_adopt:{code:2}, ed_groups:{vscode:2}, ed_count:{"1":2}, profiles:{vscode:2},
    pressure:{}, rank_ed:{n:1, all:{n:1,ed:{code:1},grp:{vscode:1},prof:{vscode:1}}, top30:{n:1,ed:{code:1},grp:{vscode:1},prof:{vscode:1}},
                          q1:{n:1,ed:{code:1},grp:{vscode:1},prof:{vscode:1}}, p10:{n:1,ed:{code:1},grp:{vscode:1},prof:{vscode:1}}},
    _rows:[{l:"alice", pts:40, rank:1, eds:["code"], band:"8", prof:"vscode"}],
    machines:[{mac:"de-ad-be-ef-00-01", processor:"Intel i5", cores:4, mem_mb:7812, team:"alice", chosen:true, used:true,
               editors_time:{code:120,total:150}, fw:true, sl:false, home_pct:10, binding:null}],
    bindings:[], series:[],
    ranks:{geral:{ram:1,cpu:1,ed:1,n:1}, pais:{ram:1,cpu:1,ed:1,n:1}}}]}' > "$C/var/nutella.cache.json"
# pacote com AUTOR (2 linhas) + documentos: 1 publicado, 1 gerado e NÃO publicado
PKG="$FIX/probs"; mkdir -p "$PKG/col/pa"
printf 'Bruno Ribas\nMaria da Silva\n' > "$PKG/col/pa/author"
mkdir -p "$C/docs"
printf '%%PDF-1.4 caderno\n' > "$C/docs/contest.pt.pdf"
printf '%%PDF-1.4 CADERNO_ENVIADO_TRADUZIDO\n' > "$C/docs/contest.pt.uploaded.pdf"
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
# classificação PUBLICADA (aba 🏅 Classificados + chip ↑BR): alice pela regra 1
jq -cn '{version:1, stages:[{id:"final-br", status:"published", name:"Final Brasileira", venue:"Uberlândia", when:"novembro/2026", region:"Brasil",
  teams:{alice:{via:"regra1", sede:"Rio", place:1, total:2, detail:"#1 geral"}}}]}' > "$C/classification.json"
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
for p in index.html runs.html score-frozen.html clarifications.html statistics.html staff-tasks.html statements/A.html; do
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
ck "bandeira de ESTADO vira SVG embutido"  'grep -q "\.f-br-rj{background-image:url(\"data:image/svg+xml;base64," "$R/index.html" && grep -q "class=\"flag-mini f-br-rj\"" "$R/index.html"'
# o SVG entra UMA vez (era por linha: 458 KB de brasão × N linhas × N placares)
ck "bandeira embutida uma vez por código"  '[[ "$(grep -c "background-image:url(\"data:image/svg" "$R/index.html")" == 2 ]]'
ck "bandeira NÃO sai como texto cru"       '! grep -qE ">br-rj<|>br-sc<" "$R/index.html"'
ck "bandeira com o NOME no title"          'grep -q "title=\"Rio de Janeiro\"" "$R/index.html" && grep -q "aria-label=\"Santa Catarina\"" "$R/index.html"'
ck "placar: coluna de penalidade"          'grep -q ">Penal.<" "$R/index.html"'
ck "problemas: coluna Autor preenchida"    'grep -q ">Autor<" "$R/index.html" && grep -q "Bruno Ribas, Maria da Silva" "$R/index.html"'
ck "runs: cstaff excluído"                 '! grep -q "rp.cstaff" "$R/runs.html"'
ck "estatísticas: mesmas seções do painel" 'grep -q "statsSections" "$R/statistics.html" && grep -q "function barChart" "$R/statistics.html"'
ck "estatísticas: fallback sem JS"         'grep -q "<noscript>" "$R/statistics.html"'
ck "estatísticas: nome do 1º a resolver"   'grep -q "first_solver_name" "$R/statistics.html"'
ck "bundle inlinado sem import/export"     '! grep -qE "^(import|export) " "$R/statistics.html"'
# --- nomes hostis dentro de <script>: o parser de HTML fecha o script no 1º "</script>" ---
ck "nome hostil: escapado no HTML do placar (não executa)" 'grep -q "&lt;script&gt;alert(1)&lt;/script&gt;" "$R/index.html" && ! grep -q "<script>alert(1)" "$R/index.html"'
ck "sede hostil: no RTREE vai como \\u003c (não fecha o script)" 'grep -qF "Floripa \\u003c/script>" "$R/statistics.html" && ! grep -qF "Floripa </script>" "$R/statistics.html"'
# "</script>" em QUALQUER lugar (até num comentário JS ou numa string) fecha o script no parser de
# HTML: o total de "</script>" tem de ser igual ao de tags <script reais (o gerador as põe no
# início da linha; "<script" no meio de comentário dos .js inlinados não abre nada).
_bad=(); for _p in "$R"/*.html; do [[ "$(grep -c "^<script" "$_p")" == "$(grep -o "</script>" "$_p" | wc -l)" ]] || _bad+=("${_p##*/}"); done
ck "toda página: cada </script> fecha uma tag <script real (${_bad[*]:-ok})" '[[ ${#_bad[@]} -eq 0 ]]'
# --- nav CONSISTENTE: toda página mostra as mesmas abas (Máquinas sumia em Classificados/Congelado) ---
_nav0=""; _navbad=(); for _p in "$R"/*.html; do _n="$(grep -o '<nav class="repnav">.*</nav>' "$_p" | sed 's/ class="on"//g')"; [[ -n "$_nav0" ]] || _nav0="$_n"; [[ "$_n" == "$_nav0" ]] || _navbad+=("${_p##*/}"); done
ck "nav: mesmas abas em TODAS as páginas (${_navbad[*]:-ok})" '[[ -n "$_nav0" && ${#_navbad[@]} -eq 0 ]]'
ck "nav: Máquinas e Congelado presentes em classificados.html" 'grep -q "mlinux.html" "$R/classificados.html" && grep -q "score-frozen.html" "$R/classificados.html"'
ck "nav: Máquinas presente em score-frozen.html"            'grep -q "mlinux.html" "$R/score-frozen.html"'
ck "nav: toda aba tem emoji (Classificados incluído)"        '[[ "$(printf "%s" "$_nav0" | grep -o ">[^<]*</a>" | sed "s/^>//; s|</a>$||" | grep -c "^[A-Za-z]")" == 0 ]] && grep -q "🏅 Classificados" "$R/classificados.html"'
ck "documentos: aba com o PUBLICADO"       '[[ -s "$R/documentos.html" ]] && [[ -s "$R/documentos/contest.pt.pdf" ]]'
# a aba só entra na nav se documentos.html já existir quando as outras páginas são escritas
# --- placar não rola para o lado (colgroup + fixed) ---
ck "placar: colgroup completo (N+5 cols)" '[[ "$(grep -o "<col class=\"c-[a-z]*\">" "$R/index.html" | wc -l)" == 7 ]]'
ck "placar: --nprob carimbado na tabela"  'grep -q "table class=\"score m-icpc\" style=\"--nprob:2" "$R/index.html"'
# a classe de MODO escopa ao ICPC o ✓/✗ do celular (no OBI a célula é a NOTA, não um acerto)
ck "placar: classe de modo na tabela"     'grep -q "class=\"score m-icpc\"" "$R/index.html"'
ck "placar: embrulho SEM rolagem"         'grep -q "board-wrap.*table class=\"score m-" "$R/index.html" && ! grep -q "tblwrap.*table class=\"score" "$R/index.html"'
# --- fotos (R4/R5) + renumeração/estrela do recorte (R1/R6) + recortes de estatística (R2) ---
ck "foto: fotos/alice.webp no pacote"      '[[ -s "$R/fotos/alice.webp" ]]'
ck "foto: 📷 relativo no placar aberto"    'grep -q "class=\"tphoto\" href=\"fotos/alice.webp\"" "$R/index.html"'
ck "foto: congelado SEM 📷"                '! grep -q "tphoto" "$R/score-frozen.html"'
ck "foto: é arquivo, nunca data:URI"       '! grep -q "tphoto\" href=\"data:" "$R/index.html"'
ck "recorte: data-place + data-tie na tr"  'grep -q "data-place=\"1\"" "$R/index.html" && grep -q "data-tie=\"" "$R/index.html"'
ck "bandeira: país agregado (data-country=br do br-rj)" 'grep -qE "data-flag=\"br-rj\"[^>]*data-country=\"br\" data-cname=\"[^\"]+\"" "$R/index.html"'
ck "recorte: data-sec (segundos) na célula" 'grep -qE "data-sec=\"[0-9]+\"" "$R/index.html"'
ck "recorte: JS renumera e re-estrela"     'grep -q "rfts" "$R/index.html" && grep -q "data-slice-t" "$R/index.html"'
ck "recorte: ★ global com classe gfts"     'grep -q "fts gfts" "$R/index.html"'
ck "estatísticas: selects sede/país"       'grep -q "id=\"sRegion\"" "$R/statistics.html" && grep -q "id=\"sFlag\"" "$R/statistics.html"'
ck "estatísticas: recortes embutidos"      'grep -q "by_region" "$R/statistics.html"'
ck "estatísticas 2.0: ac_events/top_teams embutidos" \
  'grep -q "ac_events" "$R/statistics.html" && grep -q "top_teams" "$R/statistics.html"'
ck "estatísticas: árvore de sedes (RTREE, com nó agregador)" \
  'grep -q "const RTREE=\[{\"n\":\"Brasil\",\"d\":0,\"r\":" "$R/statistics.html"'
# --- mlinux.html (nutellaboot) ---
ck "mlinux: página gerada do cache"        '[[ -s "$R/mlinux.html" ]]'
ck "mlinux: entra na NAV das outras"       'grep -q "mlinux.html" "$R/index.html"'
ck "mlinux: view + dados embutidos"        'grep -q "mlinuxSections" "$R/mlinux.html" && grep -q "NBDATA" "$R/mlinux.html"'
ck "mlinux: hierarquia (RTREE) presente"   'grep -q "const RTREE=" "$R/mlinux.html"'
ck "mlinux: SEM MAC no relatório"          '! grep -q "de-ad-be-ef" "$R/mlinux.html"'
ck "mlinux 2.0: rank_ed/pressure/link e a view nova (cpuInfo) embutidos" 'grep -q "\"rank_ed\"" "$R/mlinux.html" && grep -q "\"pressure\"" "$R/mlinux.html" && grep -q "\"link\"" "$R/mlinux.html" && grep -q "function cpuInfo" "$R/mlinux.html" && grep -q "function multiLineChart" "$R/mlinux.html"'
ck "mlinux 2.0: NADA por time vaza (teams/_rows/machines)" '! grep -q "_rows" "$R/mlinux.html" && ! grep -q "alice" "$R/mlinux.html"'
ck "mlinux 2.0: árvore com view (nós que agregam ficam fora da comparação)" 'grep -q "\"view\":" "$R/mlinux.html"'
ck "mlinux: sem script externo (invariante)" '! grep -qE "<script src=|import |fetch\(" "$R/mlinux.html"'
ck "estatísticas: nó Brasil TEM recorte (agregado por regex)" \
  'grep -qE "\"Brasil\": *\{" "$R/statistics.html"'
ck "placar: número em .pv (fonte menor)"  'grep -qE "<td class=\"cell ok\"[^>]*>(<span class=\"fts( gfts)?\">[^<]*</span>)?(<span class=\"bdot\"[^>]*></span>)?<span class=\"pv\">1/70</span>" "$R/index.html"'
# modo 'icon' (padrão): a célula resolvida NÃO depende da cor — fundo neutro + o ponto da cor,
# cujo contorno é o que faz o balão BRANCO existir (ver docs/SCOREBOARD.md)
ck "placar: célula resolvida neutra"      'grep -qE "cell ok\"[^>]*style=\"background:#e2ffe9" "$R/index.html"'
ck "placar: ponto da cor com contorno"    'grep -qE "<span class=\"bdot\" style=\"--bdot:#[0-9A-F]{6};--bdot-edge:#[0-9A-F]{6}\"" "$R/index.html"'
ck "placar: cabeçalho traz o BALÃO"       'grep -q "th class=\"prob\"><svg class=\"balloon-svg\"" "$R/index.html"'
ck "placar: CSS sem nowrap/min-width"     '! grep -qE "table.score td.cell\{[^}]*(nowrap|min-width)" "$R/index.html"'
ck "placar: penalidade sobrevive no celular" 'grep -q "td.cell:not(.tot):not(.pen) .pv { display:none" "$R/index.html" && ! grep -q "table.score td.cell .pv { display:none" "$R/index.html"'
ck "placar: login do time no title"       'grep -q "class=\"team\" title=\"[^\"]*·[^\"]*\"" "$R/index.html" && ! grep -q "<span class=\"u\">" "$R/index.html"'
# --- filtros do placar (bandeira, universidade, sede, busca) ---
ck "filtro: dado na própria linha"        'grep -q "data-flag=\"br-sc\"" "$R/index.html" && grep -q "data-fname=\"Santa Catarina\"" "$R/index.html" && grep -q "data-univ=\"UFSC\"" "$R/index.html" && grep -q "data-region=\"Floripa &lt;/script&gt;\"" "$R/index.html" && grep -q "data-search=\"&lt;script&gt;alert(1)&lt;/script&gt; bob ufsc" "$R/index.html"'
ck "filtro: os 4 controles + contador"    'grep -q "id=\"fFlag\"" "$R/index.html" && grep -q "id=\"fUniv\"" "$R/index.html" && grep -q "id=\"fRegion\"" "$R/index.html" && grep -q "id=\"fQ\"" "$R/index.html" && grep -q "id=\"fCount\"" "$R/index.html"'
ck "filtro: fallback sem JS"              'grep -q "<noscript><style>.fbar{display:none}" "$R/index.html"'
# script inline roda no parse: antes das <section> o querySelectorAll voltava vazio
ck "filtro: script DEPOIS dos placares"   '[[ "$(grep -n "</section>" "$R/index.html" | tail -1 | cut -d: -f1)" -lt "$(grep -n "id=.fbar.\|<script>" "$R/index.html" | grep "<script>" | tail -1 | cut -d: -f1)" ]]'
ck "sem coorte: um placar, sem seletor"   '[[ "$(grep -c "class=\"board-view\"" "$R/index.html")" == 1 ]] && ! grep -q "id=\"fView\"" "$R/index.html" && ! grep -q "class=\"plg\"" "$R/index.html"'
ck "documentos: link na navegação"        'grep -q "documentos.html" "$R/index.html" && grep -q "documentos.html" "$R/statistics.html"'
ck "documentos: NÃO leva o não-publicado"  '[[ ! -e "$R/documentos/editorial.pt.pdf" ]] && ! grep -rq "SEGREDO_DOC_NAO_PUBLICADO" "$R"'
# 2026-08-31: o que o TIME viu — o PDF ENVIADO vence o gerado na cópia do report
ck "documentos: leva o PDF ENVIADO (uploaded vence)" 'grep -q "CADERNO_ENVIADO_TRADUZIDO" "$R/documentos/contest.pt.pdf"'
ck "index: bloco de documentos ACIMA dos problemas"  'grep -q "doclist" "$R/index.html"'
ck "infra: aba REMOVIDA (página e nav)"    '[[ ! -e "$R/infra.html" ]] && ! grep -q "infra.html" "$R/index.html"'
ck "placar: data-login + árvore RTREE embutida" 'grep -q "data-login=" "$R/index.html" && grep -q "var RTREE=" "$R/index.html"'
ck "runs: filtro de sede (frg) + data-login"    'grep -q "id=\"frg\"" "$R/runs.html" && grep -q "data-login=" "$R/runs.html" && grep -q "var RTREE=" "$R/runs.html"'
ck "staff: filtro de sede (srg)"           'grep -q "id=\"srg\"" "$R/staff-tasks.html" && grep -q "var RTREE=" "$R/staff-tasks.html"'
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
ck "EN: runs/clar/staff"         'grep -q "<th>Verdict</th>" "$EN/runs.html" && grep -q "<th>Type</th>" "$EN/staff-tasks.html"'
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

# --- freeze preservado (2026-08-31): finish zera o conf; o report cai no freeze-final ---
mkdir -p "$C/var/frozen-final"
cp "$C"/var/placar*.txt "$C/var/frozen-final/" 2>/dev/null   # o que o finish NOVO preserva
sed -i '/^FREEZE_TIME=/d' "$C/conf"
jq -cn --argjson f "$FZ" '{freeze:$f, cleared_at:0, by:"smoke"}' > "$C/var/freeze-final.json"
FR="$FIX/rfz"; CONTESTSDIR="$FIX" MOJ_PROBLEMS_DIR="$PKG" bash "$ROOT/score/report-gen.sh" rp "$FR" >/dev/null 2>&1
ck "freeze-final: score-frozen.html volta com o conf zerado" '[[ -s "$FR/score-frozen.html" ]]'
ck "freeze-final: index anota o congelamento"  'grep -q "score-frozen.html" "$FR/index.html"'

echo "== publicar relatório (histórico em /relatorio/<c>/) =="
# RUNDIR no fixture (cache do /index/contests) e MOJ_JOBS_SYNC=1 (o job roda inline, sem setsid)
callj(){ PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="$4" HTTP_AUTHORIZATION="Bearer $3" \
  CONTESTSDIR="$FIX" SESSIONDIR="$SESS" MOJ_PROBLEMS_DIR="$PKG" RUNDIR="$FIX/run" MOJ_JOBS_SYNC=1 \
  bash "$ROUTER" <<<"${5:-}" 2>/dev/null | awk 'f{print} /^\r?$/{f=1}'; }
J="$(callj /contest/admin/report-publish GET adm 'contest=rp')"
ck "GET: ainda não publicado, url pronta"        '[[ "$(jq -r .published <<<"$J")" == false && "$(jq -r .url <<<"$J")" == "/relatorio/rp/" ]]'
J="$(callj /contest/admin/report-publish POST usr 'contest=rp' '{"action":"publish"}')"
ck "competidor não publica (403)"                 '[[ "$(jq -r .error.code <<<"$J")" == admin_required ]]'
J="$(callj /contest/admin/report-publish POST adm 'contest=rp' '{"action":"publish"}')"
ck "publish: publicado, job done, ≥7 páginas"     '[[ "$(jq -r .published <<<"$J")" == true && "$(jq -r .job.state <<<"$J")" == done && "$(jq -r .pages <<<"$J")" -ge 7 && "$(jq -r .by <<<"$J")" == rp.admin ]]'
ck "site em contests/rp/relatorio/ (index, statistics)" '[[ -s "$C/relatorio/index.html" && -s "$C/relatorio/statistics.html" && ! -e "$C/relatorio.tmp" ]]'
ck "conf: REPORT_PUBLISHED gravado (invalida o cache da home)" 'grep -q "^REPORT_PUBLISHED=" "$C/conf"'
ck "carimbo em var/, fora do site servido"        '[[ -s "$C/var/report-published.json" ]] && ! ls "$C/relatorio"/.*.json >/dev/null 2>&1'
ck "site publicado: nav consistente também"       '[[ "$(grep -o "<nav class=\"repnav\">.*</nav>" "$C/relatorio/classificados.html" | sed "s/ class=\"on\"//g")" == "$_nav0" ]]'
J="$(callj /index/contests GET '' 'all=1')"
ck "/index/contests: report_url do rp"            '[[ "$(jq -r "[.open[], .upcoming[], .closed.items[]] | .[] | select(.id==\"rp\") | .report_url" <<<"$J")" == "/relatorio/rp/" ]]'
ck "audit: report-publish"                        'grep -q "report-publish" "$C/var/admin-audit.log"'
# rodada ARQUIVADA com relatório (fixture mínimo): publicar/despublicar o relatório dela (symlink)
mkdir -p "$C/rounds/aq/relatorio"; printf '<!DOCTYPE html><html><body>aq</body></html>\n' > "$C/rounds/aq/relatorio/index.html"
jq -cn '{active:"oficial", rounds:[{slug:"aq", name:"Aquecimento", kind:"warmup", start:1, end:2, state:"archived", published:false},
                                    {slug:"oficial", name:"Prova", kind:"official", start:3, end:4, state:"active", published:false}]}' > "$C/rounds.json"
J="$(callj /contest/admin/report-publish GET adm 'contest=rp')"
ck "GET lista a rodada arquivada com relatório (public=false)" '[[ "$(jq -c ".rounds | map({slug, public})" <<<"$J")" == "[{\"slug\":\"aq\",\"public\":false}]" ]]'
J="$(callj /contest/admin/report-publish POST adm 'contest=rp' '{"action":"publish-round","round":"oficial"}')"
ck "rodada ativa não é publicável (409)"           '[[ "$(jq -r .error.code <<<"$J")" == not_archived ]]'
J="$(callj /contest/admin/report-publish POST adm 'contest=rp' '{"action":"publish-round","round":"aq"}')"
ck "publish-round: symlink relatorio-rodadas/aq → rounds/aq/relatorio" '[[ "$(jq -r ".rounds[0].public" <<<"$J")" == true && -L "$C/relatorio-rodadas/aq" && "$(cat "$C/relatorio-rodadas/aq/index.html")" == *aq* ]]'
ck "audit: report-publish-round"                    'grep -q "report-publish-round	slug=aq" "$C/var/admin-audit.log"'
J="$(callj /contest/admin/report-publish POST adm 'contest=rp' '{"action":"publish"}')"
ck "republicar: troca atômica, continua publicado" '[[ "$(jq -r .published <<<"$J")" == true && -s "$C/relatorio/index.html" && ! -e "$C/relatorio.old" ]]'
ck "index publicada linka a rodada pública (rodada/aq/)" 'grep -q "href=\"rodada/aq/\">Aquecimento</a>" "$C/relatorio/index.html"'
ck "tar.gz offline NÃO linka rodada (sem destino)"   '! grep -q "rodada/aq/" "$R/index.html"'
J="$(callj /contest/admin/report-publish POST adm 'contest=rp' '{"action":"unpublish-round","round":"aq"}')"
ck "unpublish-round: symlink some, arquivo da rodada fica" '[[ "$(jq -r ".rounds[0].public" <<<"$J")" == false && ! -e "$C/relatorio-rodadas/aq" && -s "$C/rounds/aq/relatorio/index.html" ]]'
J="$(callj /contest/admin/report-publish POST adm 'contest=rp' '{"action":"unpublish"}')"
ck "unpublish: site, carimbo e conf somem"        '[[ "$(jq -r .published <<<"$J")" == false && ! -e "$C/relatorio" && ! -e "$C/var/report-published.json" ]] && ! grep -q "^REPORT_PUBLISHED=" "$C/conf"'
J="$(callj /index/contests GET '' 'all=1')"
ck "/index/contests: sem report_url depois"       '[[ "$(jq -r "[.open[], .upcoming[], .closed.items[]] | .[] | select(.id==\"rp\") | .report_url // \"none\"" <<<"$J")" == none ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
