#!/bin/bash
# shots-ajuda.sh — gera as SCREENSHOTS dos tutoriais de papel (web/contest/ajuda/img/).
#
# Como funciona (a receita "servidor local + stub", sem nginx/fcgiwrap/juiz e sem TOCAR em
# dado real): monta um contest FICTÍCIO num diretório temporário, sobe um servidorzinho HTTP
# que serve a árvore web/ estática e, para /api/v1/*, EXECUTA o router.sh de verdade com
# CONTESTSDIR apontando p/ o fixture — as telas saem com as respostas reais da API, só que
# com dados inventados. Depois captura cada página com firefox --headless --screenshot.
#
# Duas pegadinhas resolvidas aqui:
#   1. TOKEN — as páginas leem o token do localStorage, que o headless não tem. O servidor
#      injeta o token no /shared/api.js servido (só na captura; o arquivo do repo não muda).
#   2. RENDER ASSÍNCRONO — o firefox tira a foto no evento `load`, e as páginas buscam os
#      dados DEPOIS. O servidor injeta um <img> que só termina em SHOT_DELAY_MS, segurando o
#      `load` até o app ter renderizado.
#
# Uso:  bash server/bin/shots-ajuda.sh [--keep] [--only <papel>]
#       --keep  não apaga o fixture (p/ inspecionar/depurar)
#       --only  captura só um papel (comp|staff|cstaff|anim|judge|cjudge — com ou sem o `s_`)
set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1   # raiz do cdmoj
ROOT="$PWD"
OUT="$ROOT/web/contest/ajuda/img"
: "${SHOT_DELAY_MS:=2600}"
: "${SHOT_W:=1280}"
: "${SHOT_H:=900}"
KEEP=0; ONLY=""
while [[ $# -gt 0 ]]; do case "$1" in
  --keep) KEEP=1;; --only) ONLY="${2:-}"; shift;; *) echo "opção desconhecida: $1" >&2; exit 2;;
esac; shift; done

command -v firefox >/dev/null || { echo "firefox não encontrado (headless é obrigatório)" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 não encontrado (servidor de captura)" >&2; exit 1; }

FIX="$(mktemp -d)"; RUNF="$(mktemp -d)"; SESS="$(mktemp -d)"; PROF="$(mktemp -d)"
cleanup(){ [[ -n "${SRV:-}" ]] && kill "$SRV" 2>/dev/null
  (( KEEP )) && { echo ">> fixture mantido em $FIX"; return; }
  rm -rf "$FIX" "$RUNF" "$SESS" "$PROF"; }
trap cleanup EXIT
mkdir -p "$OUT"

# ---------------------------------------------------------------- 1. contest fictício
C="$FIX/demo"; NOW="$EPOCHSECONDS"
mkdir -p "$C/var" "$C/users" "$C/print-requests" "$C/review" "$C/enunciados"
{ printf 'CONTEST_ID=demo\n'
  printf 'CONTEST_NAME=%q\n' "Copa MOJ de Demonstração"
  printf 'CONTEST_TYPE=icpc\nLOCALE=pt\n'
  # FREEZE_TIME é EPOCH ABSOLUTO (não minutos): congela na última hora
  printf 'CONTEST_START=%s\nCONTEST_END=%s\nFREEZE_TIME=%s\n' "$((NOW-7200))" "$((NOW+3600))" "$((NOW-1800))"
  printf 'PRINT=1\nMANUAL_VERDICT=1\nREVIEW_JUDGES=2\n'
  printf 'ROUND=oficial\nROUND_NAME=%q\n' "Prova oficial"
  # PROBS = tuplas de CINCO campos: <source> <problem_id> <nome> <letra> <chave-do-enunciado>
  printf 'PROBS=( demo demo#somatorio %q A demo#somatorio demo demo#labirinto %q B demo#labirinto demo demo#cofre %q C demo#cofre demo demo#tapete %q D demo#tapete )\n' \
    "Somatório curioso" "Labirinto de espelhos" "O cofre do reitor" "Tapete voador"
} > "$C/conf"

# --- contas: 6 times fictícios (2 sedes) + as 5 contas de papel
mk_user(){ # <login> <nome> <sigla> <sede> <bandeira>
  local d="$C/users/$1"; mkdir -p "$d/submissions" "$d/mojlog" "$d/results"
  jq -cn --arg l "$1" --arg n "$2" --arg u "$3" --arg r "$4" --arg f "$5" \
    '{login:$l, password:"demo1234", fullname:$n, email:"", created_at:0, updated_at:0,
      status:"active", uname_changes:[],
      team:{name:$n, univ_short:$u, univ_full:$u, region:$r, flag:$f}}' > "$d/account.json"
  : > "$d/history"
}
mk_user time-alfa    "Os Alfabetizados"    UFPR  "Curitiba" br
mk_user time-beta    "Beta Testers"        UnB   "Curitiba" br
mk_user time-gama    "Gama Radiação"       UFPR  "Curitiba" br
mk_user time-delta   "Delta de Dirac"      USP   "São Paulo" br
mk_user time-epsilon "Épsilon Suficiente"  UNESP "São Paulo" br
mk_user time-zeta    "Zeta Zero"           USP   "São Paulo" ar
for r in sala.staff chefe.cstaff telao.animeitor juri.judge decano.cjudge; do
  d="$C/users/$r"; mkdir -p "$d"
  jq -cn --arg l "$r" '{login:$l, password:"demo1234", fullname:"Equipe da prova", email:"",
     created_at:0, updated_at:0, status:"active", uname_changes:[]}' > "$d/account.json"
  : > "$d/history"
done

# --- escopo de sede: o chefe e a equipe enxergam só Curitiba
jq -cn '{"chefe.cstaff":["region:Curitiba"], "sala.staff":["region:Curitiba"]}' \
  > "$C/print-requests/staff-filters.json"
jq -cn '{regions:[{name:"Curitiba"},{name:"São Paulo"}]}' > "$C/var/regions.json" 2>/dev/null || true

# --- fila de impressão: pendentes, uma impressa e os balões automáticos (kind=balloon)
mkpr(){ # <id> <login> <time> <univ> <arquivo> <status> <seq> <kind> <idade_s> [letra] [hex] [cor]
  jq -cn --arg id "$1" --arg l "$2" --arg fn "$3" --arg u "$4" --arg f "$5" --arg s "$6" \
     --argjson q "$7" --arg k "$8" --argjson t "$((NOW-$9))" \
     --arg sh "${10:-}" --arg hex "${11:-}" --arg cn "${12:-}" \
    '{id:$id, seq:$q, login:$l, fullname:$fn, team:$fn, univ:$u, kind:$k, filename:$f,
      mime:"text/plain", size:1200, time:$t, status:$s, pages:1,
      short:$sh, color_hex:$hex, color_name:$cn}' > "$C/print-requests/$1.json"
}
mkpr p1 time-alfa  "Os Alfabetizados" UFPR  "solucao-b.cpp" pending   7 print   240
mkpr p2 time-gama  "Gama Radiação"    UFPR  "rascunho.txt"  pending   8 print   120
mkpr p3 time-beta  "Beta Testers"     UnB   "solucao-a.c"   processed 6 print   900
# uma tarefa JÁ PEGA por mim: o claim MANTÉM status=pending (print-action.sh só permite claim
# sobre pendente) e grava claimed_by/claimed_at — é o estado logo depois de clicar em "Pegar"
mkpr p0 time-alfa  "Os Alfabetizados" UFPR  "main.c"        pending   5 print   300
jq -c --arg by sala.staff --argjson at "$((NOW-30))" '.claimed_by=$by | .claimed_at=$at' \
  "$C/print-requests/p0.json" > "$C/print-requests/p0.tmp" \
  && mv "$C/print-requests/p0.tmp" "$C/print-requests/p0.json"
# fonte real da tarefa (o .src é o que o pr_build_pdf imprime depois da folha de rosto)
cat > "$C/print-requests/p0.src" <<'SRC'
#include <stdio.h>

/* Somatório curioso — solução do time Os Alfabetizados */
int main(void) {
    long long n, soma = 0;
    if (scanf("%lld", &n) != 1) return 1;
    for (long long i = 1; i <= n; i++)
        if (i % 3 == 0 || i % 5 == 0) soma += i;
    printf("%lld\n", soma);
    return 0;
}
SRC
cp "$C/print-requests/p0.src" "$C/print-requests/p1.src"
mkpr b1 time-alfa  "Os Alfabetizados" UFPR  ""              pending   9 balloon  60 A e63946 vermelho
mkpr b2 time-beta  "Beta Testers"     UnB   ""              pending  10 balloon  30 C 2a9d8f verde

# --- placar (TXT cru, como o build.sh gera): cabeçalho + 6 linhas
# FORMATO REAL do placar (updatescore-icpc.sh): 1ª linha = modo; 2ª = header com os DOIS
# marcadores desc:asc na frente; dados separados por ':' e SEM os marcadores. Célula:
# vazia=não tentou · 3/187=resolveu na 3ª tentativa no minuto 187 · 3/-=tentou e não resolveu
# · o `*` final é o FIRST-TO-SOLVE (updatescore-icpc.sh:97 = menor minuto do problema ENTRE os
# times DAQUELE placar), que o score-icpc.js pinta como ★ — o tutorial do competidor explica a
# estrela, então ela tem de aparecer na foto. Ela é por VISÃO: o congelado estrela quem é o
# primeiro no que ele mostra, e por isso o par congelado×completo pode diferir (o D só é
# resolvido depois do congelamento).
SCOL='desc:asc:flag:username:univ short:team name:univ full:A:B:C:D:Total:Penalty:LastAC'
{ printf 'icpc\n%s\n' "$SCOL"
  printf 'br:time-alfa:UFPR:Os Alfabetizados:Univ. Federal do Paraná:1/12*:2/45*:1/78::3:147:78\n'
  printf 'br:time-delta:USP:Delta de Dirac:Universidade de São Paulo:1/20:1/-:1/61*:3/-:2:81:61\n'
  printf 'br:time-beta:UnB:Beta Testers:Universidade de Brasília:1/33:2/-:::1:33:33\n'
  printf 'br:time-epsilon:UNESP:Épsilon Suficiente:Universidade Estadual Paulista:1/40:::2/-:1:40:40\n'
  printf 'br:time-gama:UFPR:Gama Radiação:Univ. Federal do Paraná::1/-:::0:0:0\n'
  printf 'ar:time-zeta:USP:Zeta Zero:Universidade de São Paulo:::::0:0:0\n'
} > "$C/var/placar.txt"
# o placar COMPLETO diverge do congelado em várias células — é EXATAMENTE esse delta que a
# cerimônia abre uma a uma (reveal.js pendingCells), incluindo uma virada de liderança
{ printf 'icpc\n%s\n' "$SCOL"
  printf 'br:time-delta:USP:Delta de Dirac:Universidade de São Paulo:1/20:2/152:1/61*:3/188:4:280:188\n'
  printf 'br:time-alfa:UFPR:Os Alfabetizados:Univ. Federal do Paraná:1/12*:2/45*:1/78:2/171*:4:338:171\n'
  printf 'br:time-beta:UnB:Beta Testers:Universidade de Brasília:1/33:3/166::1/195:3:239:195\n'
  printf 'br:time-epsilon:UNESP:Épsilon Suficiente:Universidade Estadual Paulista:1/40:::2/-:1:40:40\n'
  printf 'br:time-gama:UFPR:Gama Radiação:Univ. Federal do Paraná::2/-:::0:0:0\n'
  printf 'ar:time-zeta:USP:Zeta Zero:Universidade de São Paulo:::::0:0:0\n'
} > "$C/var/placar-full.txt"
# cores dos balões (as células resolvidas saem na cor do balão do problema)
jq -cn '{A:"E63946", B:"264653", C:"2A9D8F", D:"E9C46A"}' > "$C/balloons.json"

# --- history dos times: é a fonte de "Todas Submissões" (6 campos, login implícito:
#     tempo:probid:lang:verdict:sub_epoch:subid)
h(){ # <login> <min-desde-o-inicio> <probid> <lang> <verdict> <subid>
  local ep=$((NOW-7200+$2*60))
  printf '%s:%s:%s:%s:%s:%s\n' "$ep" "$3" "$4" "$5" "$ep" "$6" >> "$C/users/$1/history"
}
h time-alfa   12 demo#somatorio C    "Accepted"                  aa01
h time-alfa   31 demo#labirinto C    "Wrong Answer"              aa02
h time-alfa   45 demo#labirinto C    "Accepted"                  aa03
h time-alfa   78 demo#cofre     C++  "Accepted"                  aa04
h time-alfa   95 demo#tapete    C    "Not Answered Yet"          aa05
h time-beta   33 demo#somatorio C    "Accepted"                  bb01
h time-beta   52 demo#labirinto Java "Time Limit Exceeded"       bb02
h time-beta   71 demo#labirinto Java "Not Answered Yet"          bb03
h time-gama   28 demo#labirinto C    "Compilation Error"         cc01
h time-gama   64 demo#cofre     Java "Not Answered Yet"          cc02
h time-delta  20 demo#somatorio C++  "Accepted"                  dd01
h time-delta  61 demo#cofre     C++  "Accepted"                  dd02
h time-delta  88 demo#tapete    Py   "Not Answered Yet"          dd03
h time-epsilon 40 demo#somatorio Py  "Accepted"                  ee01
h time-epsilon 57 demo#labirinto Py  "Runtime Error"             ee02
h time-zeta   26 demo#somatorio C    "Wrong Answer"              ff01

# --- rodadas: um aquecimento arquivado + a prova oficial em andamento
mkdir -p "$C/rounds/aquecimento"
jq -cn --argjson now "$NOW" \
  '{version:1, active:"prova",
    rounds:[{slug:"aquecimento", name:"Aquecimento", kind:"warmup", state:"archived",
             start:($now-86400), end:($now-82800), published:true, problems:2},
            {slug:"prova", name:"Prova oficial", kind:"official", state:"active",
             start:($now-7200), end:($now+3600), problems:4}]}' > "$C/rounds.json"
cp "$C/var/placar.txt" "$C/rounds/aquecimento/placar.txt" 2>/dev/null || true

# --- fila de avaliação do veredicto manual (contrato de write_review_item, judged.sh:217)
mkrev(){ # <id> <login> <cid> <lang> <verdict-computado> <idade> [label1] [v1] [label2] [v2]
  jq -cn --arg id "$1" --arg l "$2" --arg p "$3" --arg lg "$4" --arg v "$5" \
     --argjson at "$((NOW-$6))" --arg l1 "${7:-}" --arg v1 "${8:-}" \
     --arg l2 "${9:-}" --arg v2 "${10:-}" \
    '{id:$id, contest:"demo", login:$l, problem_id:$p, lang:$lg, sub_epoch:$at,
      computed_verdict:$v, report_html:"", created_at:$at, status:"open",
      claimants:[], conflict:(($v1 != "") and ($v2 != "") and ($v1 != $v2)),
      released_at:null, released_by:null,
      votes:([{by:"juri.judge", label:$l1, verdict:$v1},
              {by:"decano.cjudge", label:$l2, verdict:$v2}] | map(select(.verdict != "")))}' \
    > "$C/review/$1.json"
}
mkrev r1 time-alfa  demo#labirinto C    "Wrong Answer" 300
mkrev r2 time-delta demo#somatorio C++  "Accepted"     180
# r5 está RESERVADA pelo juri.judge (claimants com expires_at no futuro) — é o que faz o
# /contest/review/list devolver my_active e a página abrir o PAINEL DE AVALIAÇÃO
mkrev r5 time-epsilon demo#tapete Py "Time Limit Exceeded" 120
jq -c --argjson exp "$((NOW+240))" \
  '.claimants=[{by:"juri.judge", at:('"$NOW"'-60), expires_at:$exp}] | .status="claimed"' \
  "$C/review/r5.json" > "$C/review/r5.tmp" && mv "$C/review/r5.tmp" "$C/review/r5.json"
mkrev r3 time-gama  demo#cofre     Java "Accepted"     900 "1 - YES" "Accepted"
mkrev r4 time-beta  demo#cofre     C    "Accepted"     600 "1 - YES" "Accepted" "5 - NO - Wrong answer" "Wrong Answer"
# opções de veredicto do contest (as 6 padrão do RV_DEFAULT_OPTS)
jq -cn '[{label:"1 - YES", verdict:"Accepted"},
         {label:"2 - NO - Compilation error", verdict:"Compilation Error"},
         {label:"3 - NO - Runtime error", verdict:"Runtime Error"},
         {label:"4 - NO - Time limit exceeded", verdict:"Time Limit Exceeded"},
         {label:"5 - NO - Wrong answer", verdict:"Wrong Answer"},
         {label:"6 - NO - Contact staff", verdict:"Contact Staff"}]' \
  > "$C/final-verdicts.json"

# --- clarifications: uma aberta, uma respondida em privado e um AVISO OFICIAL (broadcast),
#     que é a resposta pública que não esperou ninguém perguntar. O asker nunca é exibido.
mkdir -p "$C/clarifications"
mkclar(){ # <id> <login> <problema> <idade> <pergunta> [resposta] [public] [broadcast]
  jq -cn --arg id "$1" --arg l "$2" --arg p "$3" --argjson t "$((NOW-$4))" \
     --arg q "$5" --arg a "${6:-}" --argjson pub "${7:-false}" --argjson bc "${8:-false}" \
    '{id:$id, login:$l, problem:$p, question:$q, time:$t,
      answer:$a, public:$pub, broadcast:$bc,
      answered_by:(if $a=="" then "" else "juri.judge" end),
      answered_at:(if $a=="" then null else $t+120 end), answer_claim:null}' \
    > "$C/clarifications/$1.json"
}
mkclar c1 time-beta B 900 \
  "No problema B, o labirinto pode ter mais de uma saída? O enunciado não diz."
mkclar c2 time-gama A 1800 \
  "O N da entrada cabe em 32 bits?" \
  "Sim — leia o limite na seção Entrada do enunciado." true
mkclar c3 time-alfa general 600 \
  "A prova foi prorrogada?" \
  "A sede de São Paulo teve 20 minutos de prorrogação por queda de energia. As demais sedes seguem o horário original." \
  true true
# notícias públicas do contest (contests/<c>/news.json)
jq -cn --argjson t "$((NOW-2400))" \
  '[{id:"n1", title:"Almoço liberado a partir das 12h",
     text:"O refeitório do bloco C está aberto para os times. Leve o crachá.", date:$t}]' \
  > "$C/news.json"

# --- documentos da prova: o index.json é o que a aba 📄 lista (os tamanhos saem daqui, não do
#     disco), e o config.json diz o que já está PUBLICADO ("<tipo>.<lang>")
mkdir -p "$C/docs"
jq -cn --argjson t "$((NOW-3600))" --arg by decano.cjudge \
  '[{type:"contest",   lang:"pt", html_bytes:184320, pdf_bytes:1638400, generated_at:$t,     by:$by},
    {type:"contest",   lang:"en", html_bytes:181240, pdf_bytes:1601210, generated_at:($t+30), by:$by},
    {type:"info-sheet",lang:"pt", html_bytes:9420,   pdf_bytes:48210,   generated_at:($t-300), by:$by},
    {type:"info-sheet",lang:"en", html_bytes:9210,   pdf_bytes:47880,   generated_at:($t-295), by:$by},
    {type:"times",     lang:"pt", html_bytes:4180,   pdf_bytes:22140,   generated_at:($t-200), by:$by},
    {type:"editorial", lang:"pt", html_bytes:31240,  pdf_bytes:204800,  generated_at:($t+200), by:$by}]' \
  > "$C/docs/index.json"
jq -cn '{caderno_version:"v1.2", cover_note:"Realização: MOJ · Apoio: UnB",
         errata:"Problema C: leia 1 ≤ N ≤ 10^5.",
         published:["info-sheet.pt","info-sheet.en","times.pt"]}' > "$C/docs/config.json"
# o que o COMPETIDOR vê de documento é a seção "Prova" da aba Contest, que sai do
# resources.json (escrito pelo doc_publish) — a aba 📄 é dos papéis de organização
jq -cn --arg c demo '[
  {label:"Info sheet (pt)", url:("/api/v1/contest/doc?contest=" + $c + "&type=info-sheet&lang=pt&fmt=pdf"), type:"info-sheet", lang:"pt"},
  {label:"Info sheet (en)", url:("/api/v1/contest/doc?contest=" + $c + "&type=info-sheet&lang=en&fmt=pdf"), type:"info-sheet", lang:"en"},
  {label:"Folha de time limits (pt)", url:("/api/v1/contest/doc?contest=" + $c + "&type=times&lang=pt&fmt=pdf"), type:"times", lang:"pt"}]'   > "$C/resources.json"

# ENUNCIADOS: PDF de mentira + HTML de verdade. O HTML é o que a sanfona mostra ao lado do
# editor; sem ele o detalhe abre só com o editor e a tela perde o assunto do tutorial.
for k in somatorio labirinto cofre tapete; do printf '%%PDF-1.4\n' > "$C/enunciados/demo#$k.pdf"; done
mkstmt(){ # <chave> <título> <corpo-html>
  cat > "$C/enunciados/demo#$1.html" <<HTML
<html><body>
<h1 class="moj-title">$2</h1>
$3
<h2>Entrada</h2>
<p>A primeira linha contém um inteiro <em>N</em> (1 ≤ <em>N</em> ≤ 10<sup>5</sup>).</p>
<h2>Saída</h2>
<p>Imprima uma única linha com a resposta.</p>
<h2>Exemplos</h2>
<table class="samples"><tr><th>Entrada</th><th>Saída</th></tr>
<tr><td><pre>10</pre></td><td><pre>23</pre></td></tr>
<tr><td><pre>3</pre></td><td><pre>3</pre></td></tr></table>
</body></html>
HTML
}
mkstmt somatorio "Somatório curioso" \
  "<p>Dado um inteiro <em>N</em>, some todos os múltiplos de 3 ou de 5 menores ou iguais a <em>N</em>. Por exemplo, para <em>N</em> = 10 os múltiplos são 3, 5, 6, 9 e 10 — cuja soma é 33.</p><p>Cuidado com o tamanho da resposta: ela pode não caber num inteiro de 32 bits.</p>"
mkstmt labirinto "Labirinto de espelhos" \
  "<p>Um raio de luz entra pelo canto superior esquerdo de uma sala quadriculada com espelhos. Diga por qual parede ele sai.</p>"
mkstmt cofre "O cofre do reitor" \
  "<p>O cofre abre quando a soma dos dígitos da senha é múltipla de 7. Conte quantas senhas de <em>N</em> dígitos abrem o cofre.</p>"
mkstmt tapete "Tapete voador" \
  "<p>Um tapete retangular cobre parte de um piso quadriculado. Calcule a área descoberta.</p>"

# --- chaves de webcast do telão (contests/<c>/webcast.json — wc_file)
jq -cn --argjson now "$NOW" \
  '{keys:[{id:"a1b2c3d4", key:"mojwc_DEMO0000000000000000000000demo", view:"public",
           label:"Telão do auditório", created_by:"telao.animeitor", created_at:($now-3600),
           revoked_at:null, fetches:412, last_at:($now-20), last_ip:"10.0.0.15"},
          {id:"e5f6a7b8", key:"mojwc_DEMO1111111111111111111111demo", view:"all",
           label:"Transmissão no YouTube", created_by:"telao.animeitor", created_at:($now-1800),
           revoked_at:null, fetches:88, last_at:($now-95), last_ip:"10.0.0.31"}]}' \
  > "$C/webcast.json"

# --- fotos e músicas de alguns times (a galeria fica viva: uns com, outros sem)
PH="$ROOT/server/etc/team-placeholder.webp"
if [[ -s "$PH" ]]; then
  for u in time-alfa time-beta time-delta; do
    cp "$PH" "$C/users/$u/photo.webp"
    cp "$ROOT/server/etc/team-placeholder.thumb.webp" "$C/users/$u/photo.thumb.webp" 2>/dev/null \
      || cp "$PH" "$C/users/$u/photo.thumb.webp"
  done
fi
# uma música própria (o arquivo padrão serve de dublê — é só p/ a tela mostrar "própria")
[[ -s "$ROOT/server/etc/team-placeholder.mp3" ]] && \
  cp "$ROOT/server/etc/team-placeholder.mp3" "$C/users/time-alfa/music.mp3"

# --- sessões (uma por papel)
mksess(){ printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' demo "$1" "$2" "$NOW" > "$SESS/$3"; }
mksess time-alfa        "Os Alfabetizados" s_comp
mksess sala.staff       "Equipe de sala"  s_staff
mksess chefe.cstaff     "Chefe de sede"   s_cstaff
mksess telao.animeitor  "Mesa do telão"   s_anim
mksess juri.judge       "Juiz"            s_judge
mksess decano.cjudge    "Juiz-chefe"      s_cjudge

# --------------------------------------------------- 2. servidor de captura (estático + API)
PORT="$(python3 - <<'PY'
import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()
PY
)"
export SHOT_ROOT="$ROOT" SHOT_FIX="$FIX" SHOT_RUN="$RUNF" SHOT_SESS="$SESS" \
       SHOT_DELAY_MS SHOT_PORT="$PORT"
python3 "$ROOT/server/bin/shots-server.py" & SRV=$!
for i in $(seq 1 40); do
  curl -sf "http://127.0.0.1:$PORT/__ping" >/dev/null 2>&1 && break; sleep 0.25
done

# ⚠ Imagens RECORTADAS À MÃO: o enquadramento delas não sai de um `--window-size` (o recorte
# começa no MEIO da página, sem topbar). A captura cheia é PIOR que a que está no repo, e uma
# rodada sem `--only` as sobrescrevia EM SILÊNCIO — aconteceu em 22/08/2026 com a staff-pega.png
# (as linhas da fila com os botões Pegar/Imprimir), que voltou a 900px de página inteira. Estas
# são puladas; p/ refazer de propósito, `SHOTS_REGERAR_RECORTADAS=1` e recorte de novo.
RECORTADAS=' staff-pega.png '

# shot <arquivo.png> <papel> <caminho-da-página> [altura]
# O `sess=` diz ao servidor de captura QUAL sessão usar ao chamar o router (é o papel logado).
# aceita `--only judge` e `--only s_judge`: o comentário de uso sempre disse "papel", mas a
# comparação era com o nome da SESSÃO — quem lia a ajuda não capturava nada e nem sabia por quê
shot(){
  local name="$1" role="$2" path="$3" h="${4:-$SHOT_H}"
  [[ -n "$ONLY" && "$role" != "$ONLY" && "$role" != s_"$ONLY"* ]] && return 0
  if [[ "$RECORTADAS" == *" $name "* && -z "${SHOTS_REGERAR_RECORTADAS:-}" ]]; then
    printf '  %-32s %s\n' "$name" "pulada (recorte à mão — ver RECORTADAS)"; return 0
  fi
  local out="$OUT/$name" sep='?'; [[ "$path" == *\?* ]] && sep='&'
  rm -rf "$PROF"; mkdir -p "$PROF"   # perfil limpo: sem --profile o firefox serve do CACHE
  MOZ_HEADLESS=1 timeout 120 firefox --headless --profile "$PROF" \
    --window-size "$SHOT_W,$h" --screenshot "$out" \
    "http://127.0.0.1:$PORT${path}${sep}c=demo&sess=$role" >/dev/null 2>&1
  local sz; sz="$(stat -c%s "$out" 2>/dev/null || echo 0)"
  printf '  %-32s %8s bytes\n' "$name" "$sz"
  (( sz > 8000 )) || echo "    ⚠ pequena demais — a tela provavelmente não renderizou"
}

echo ">> capturando (porta $PORT, delay ${SHOT_DELAY_MS}ms)"
# ---- competidor -----------------------------------------------------------------------
# A sanfona é um <span class="prob-left"> com listener de clique: por TEXTO o ?click= não a
# acha (ele só varre button/.btn/a/summary), por isso o ?clickcss=.
shot comp-contest.png      s_comp    /contest/                                    1500
# a PRIMEIRA tela que o competidor vê. O "papel" é uma sessão que NÃO EXISTE: o token não
# resolve, a API responde 401 e o app cai no formulário de login — que é o que se quer fotografar.
shot comp-login.png        s_comp_deslogado /contest/                              760
OCULTA='%23newsSection,%23resourcesSection,%23userSection,%23mySubsSection'
# só a FAIXA de notificação (banner + topbar + nav com o badge de clarification): esconde o
# conteúdo todo e corta na altura da nav. É a ilustração de "como é uma notificação" — recortar
# a foto da página inteira daria o mesmo pixel, mas exigiria um editor de imagem no caminho.
shot comp-notify.png       s_comp    "/contest/?hide=$OCULTA,%23problemsSection"   215
# nas fotos de DETALHE o topo (faixa de notificação + topbar + nav) só rouba altura: o leitor
# já viu a página inteira na seção 2 e aqui o que importa é a seção fotografada.
CROMO='.notify-banner,.topbar,.quicknav'
shot comp-problemas.png    s_comp    "/contest/?hide=$OCULTA,$CROMO"               400
shot comp-sanfona.png      s_comp    "/contest/?clickcss=.prob-left&times=1&hide=$OCULTA,$CROMO" 840
shot comp-submissoes.png   s_comp    "/contest/?hide=%23newsSection,%23resourcesSection,%23problemsSection,%23userSection,$CROMO" 460
shot comp-placar.png       s_comp    /contest/score/                               700
shot comp-clarification.png s_comp   /contest/clarification/                       960
# a MESMA sanfona com o editor DESLIGADO (SHOWEDITOR=0) — é o caso da Maratona SBC, em que a
# prova roda em máquina controlada e o time compila no ambiente dela, não no navegador
if [[ -z "$ONLY" || "s_$ONLY" == s_comp || "$ONLY" == s_comp ]]; then
  cp "$C/conf" "$C/conf.bak"; printf 'SHOWEDITOR=0
' >> "$C/conf"
  shot comp-sem-editor.png s_comp "/contest/?clickcss=.prob-left&times=1&hide=$OCULTA,$CROMO" 700
  mv -f "$C/conf.bak" "$C/conf"
fi
shot staff-fila.png        s_staff   /contest/staff/
shot staff-pega.png        s_staff   /contest/staff/
shot staff-telao.png       s_staff   /contest/animeitor/       1100
shot cstaff-fila.png       s_cstaff  /contest/staff/
shot cstaff-etiquetas.png  s_cstaff  /contest/badges/          1100
shot cstaff-telao.png      s_cstaff  /contest/animeitor/       1100
shot cstaff-placar.png     s_cstaff  /contest/score/
shot animeitor-telao.png   s_anim    /contest/animeitor/       1250
shot animeitor-placar.png  s_anim    /contest/score/
shot animeitor-cerimonia.png s_anim  "/contest/score/reveal.html?click=Step&times=4" 1000
shot judge-fila.png        s_judge   /contest/judge/
shot judge-avaliando.png   s_judge   /contest/judge/
shot judge-todas.png       s_judge   /contest/allsubmissions/  1000
shot judge-clarification.png s_judge /contest/clarification/   1250
shot cjudge-todas.png      s_cjudge  /contest/allsubmissions/  1000
shot cjudge-clarification.png s_cjudge "/contest/clarification/?click=editar resposta&times=1" 1500
shot cjudge-painel.png     s_cjudge  /contest/chief/           1100
shot cjudge-docs.png       s_cjudge  "/contest/chief/?click=Documentos&times=2" 1000
shot rodadas.png           s_staff   /contest/rounds/          800

# ---------------------------------------------------------------- PDFs de exemplo
# O que SAI NA IMPRESSORA: a folha de rosto do pedido (página 1) e a folha do balão. As duas
# são geradas pelas funções REAIS do lib/print.sh sobre o fixture; a página 1 vira PNG p/ o
# tutorial mostrar o papel de verdade (paps/magick/soffice/pdfunite/pdftoppm no host).
if [[ -z "$ONLY" ]] && command -v pdftoppm >/dev/null; then
  echo ">> PDFs de exemplo"
  ( set +u
    export CONTESTSDIR="$FIX" RUNDIR="$RUNF" SESSIONDIR="$SESS"
    source "$ROOT/server/api/v1/lib/print.sh" 2>/dev/null
    for pair in "p1:pdf-impressao-p1" "b1:pdf-balao"; do
      id="${pair%%:*}"; name="${pair##*:}"
      if [[ "$id" == b1 ]]; then pdf="$(pr_build_balloon demo "$id" 2>/dev/null)"
      else pdf="$(pr_build_pdf demo "$id" 2>/dev/null)"; fi
      if [[ -s "$pdf" ]]; then
        pdftoppm -png -r 100 -f 1 -l 1 -singlefile "$pdf" "$OUT/$name" 2>/dev/null
        printf '  %-32s %8s bytes\n' "$name.png" "$(stat -c%s "$OUT/$name.png" 2>/dev/null || echo 0)"
      else echo "  ⚠ $name: PDF não foi gerado (falta paps/magick/soffice?)"; fi
    done )
fi

echo ">> pronto: $OUT"
