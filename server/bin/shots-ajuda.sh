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
  # p/ depurar uma tela vazia é preciso repetir a chamada do router à mão — e aí os TRÊS
  # diretórios importam (CONTESTSDIR, RUNDIR e SESSIONDIR), não só o do contest
  (( KEEP )) && { printf '>> mantidos: CONTESTSDIR=%s RUNDIR=%s SESSIONDIR=%s\n' "$FIX" "$RUNF" "$SESS"; return; }
  rm -rf "$FIX" "$RUNF" "$SESS" "$PROF"; }
trap cleanup EXIT
mkdir -p "$OUT"

# ---------------------------------------------------------------- 1. contest fictício
C="$FIX/demo"; NOW="$EPOCHSECONDS"
mkdir -p "$C/var" "$C/users" "$C/print-requests" "$C/review" "$C/enunciados"
{ printf 'CONTEST_ID=demo\n'
  printf 'CONTEST_NAME=%q\n' "MOJ Demonstration Cup"
  # ⚠ LOCALE=en: as telas dos tutoriais saem em INGLÊS de propósito — o tutorial é lido por
  # quem compete em prova internacional, e captura em PT amarraria a documentação ao Brasil.
  # O texto do tutorial continua bilíngue; o que a foto mostra é a interface em inglês.
  printf 'CONTEST_TYPE=icpc\nLOCALE=en\n'
  # FREEZE_TIME é EPOCH ABSOLUTO (não minutos): congela na última hora
  printf 'CONTEST_START=%s\nCONTEST_END=%s\nFREEZE_TIME=%s\n' "$((NOW-7200))" "$((NOW+3600))" "$((NOW-1800))"
  printf 'PRINT=1\nMANUAL_VERDICT=1\nREVIEW_JUDGES=2\n'
  # célula do placar PINTADA com a cor do balão (o clássico do ICPC) — com a paleta oficial
  # abaixo é o que faz a tela parecer a de uma prova de verdade
  printf 'SCORE_BALLOON_STYLE=fill\n'
  printf 'ROUND=oficial\nROUND_NAME=%q\n' "Main round"
  # PROBS = tuplas de CINCO campos: <source> <problem_id> <nome> <letra> <chave-do-enunciado>
  # OITO problemas, como uma prova de verdade — é o que dá sentido à paleta oficial (A..H) e o
  # que faz o placar ter a largura que ele tem no dia.
  printf 'PROBS=('
  for t in "somatorio:A curious sum:A"          "labirinto:Mirror maze:B" \
           "cofre:The dean's safe:C"            "tapete:Flying carpet:D" \
           "estadio:A full stadium:E"           "bandejao:The cafeteria queue:F" \
           "metro:The city subway:G"            "astrolabio:The astrolabe:H"; do
    IFS=: read -r k n l <<<"$t"
    printf ' demo demo#%s %q %s demo#%s' "$k" "$n" "$l" "$k"
  done
  printf ' )\n'
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
mk_user time-alfa    "Alpha Team"          UFPR  "Curitiba" br
mk_user time-beta    "Beta Testers"        UnB   "Curitiba" br
mk_user time-gama    "Gamma Radiation"     UFPR  "Curitiba" br
mk_user time-delta   "Dirac Delta"         USP   "São Paulo" br
mk_user time-epsilon "Sufficient Epsilon"  UNESP "São Paulo" br
mk_user time-zeta    "Zeta Zero"           USP   "São Paulo" ar
for r in sala.staff chefe.cstaff telao.animeitor juri.judge decano.cjudge; do
  d="$C/users/$r"; mkdir -p "$d"
  jq -cn --arg l "$r" '{login:$l, password:"demo1234", fullname:"Contest crew", email:"",
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
mkpr p1 time-alfa  "Alpha Team"       UFPR  "solution-b.cpp" pending  7 print   240
mkpr p2 time-gama  "Gamma Radiation"  UFPR  "draft.txt"      pending  8 print   120
mkpr p3 time-beta  "Beta Testers"     UnB   "solution-a.c"   processed 6 print  900
# uma tarefa JÁ PEGA por mim: o claim MANTÉM status=pending (print-action.sh só permite claim
# sobre pendente) e grava claimed_by/claimed_at — é o estado logo depois de clicar em "Pegar"
mkpr p0 time-alfa  "Alpha Team"       UFPR  "main.c"         pending  5 print   300
jq -c --arg by sala.staff --argjson at "$((NOW-30))" '.claimed_by=$by | .claimed_at=$at' \
  "$C/print-requests/p0.json" > "$C/print-requests/p0.tmp" \
  && mv "$C/print-requests/p0.tmp" "$C/print-requests/p0.json"
# fonte real da tarefa (o .src é o que o pr_build_pdf imprime depois da folha de rosto)
cat > "$C/print-requests/p0.src" <<'SRC'
#include <stdio.h>

/* A curious sum - solution by Alpha Team */
int main(void) {
    long long n, sum = 0;
    if (scanf("%lld", &n) != 1) return 1;
    for (long long i = 1; i <= n; i++)
        if (i % 3 == 0 || i % 5 == 0) sum += i;
    printf("%lld\n", sum);
    return 0;
}
SRC
cp "$C/print-requests/p0.src" "$C/print-requests/p1.src"
# ⚠ o balão da foto é o do C (VERMELHO) de propósito: o A da paleta oficial é BRANCO, e a folha
# do tutorial do .staff — que fala em "se o desenho diz vermelho" — ficaria branca no branco.
# Os dois times abaixo resolveram mesmo esses problemas (ver o history adiante).
mkpr b1 time-alfa  "Alpha Team"       UFPR  ""               pending  9 balloon  60 C ff0000 red
mkpr b2 time-beta  "Beta Testers"     UnB   ""               pending 10 balloon  30 E ffff00 yellow
# a tela do COMPETIDOR (contest/print/) lista só os pedidos DELE, com o estado de cada um —
# então o time-alfa precisa dos três estados p/ a foto do tutorial fazer sentido
mkpr p4 time-alfa  "Alpha Team"       UFPR  "reading.pdf"    delivered 2 print 1800
mkpr p5 time-alfa  "Alpha Team"       UFPR  "solution-e.py"  printed  4 print   720

# --- backups do competidor (contests/<c>/backups/<login>/<id> + <id>.meta {name,size,time})
bkp(){ # <login> <id> <nome> <bytes> <idade_s>
  local d="$C/backups/$1"; mkdir -p "$d"
  head -c "$4" /dev/zero | tr '\0' 'x' > "$d/$2"
  jq -cn --arg n "$3" --argjson s "$4" --argjson t "$((NOW-$5))" \
    '{name:$n, size:$s, time:$t}' > "$d/$2.meta"
}
bkp time-alfa bk01 "sum-that-worked.c"       2143 5400
bkp time-alfa bk02 "maze-v2.cpp"             4820 2700
bkp time-alfa bk03 "carpet-brute-force.py"   1160  900

# --- placar (TXT cru, como o build.sh gera): cabeçalho + 6 linhas
# FORMATO REAL do placar (updatescore-icpc.sh): 1ª linha = modo; 2ª = header com os DOIS
# marcadores desc:asc na frente; dados separados por ':' e SEM os marcadores. Célula:
# vazia=não tentou · 3/187=resolveu na 3ª tentativa no minuto 187 · 3/-=tentou e não resolveu
# · o `*` final é o FIRST-TO-SOLVE (updatescore-icpc.sh:97 = menor minuto do problema ENTRE os
# times DAQUELE placar), que o score-icpc.js pinta como ★ — o tutorial do competidor explica a
# estrela, então ela tem de aparecer na foto. Ela é por VISÃO: o congelado estrela quem é o
# primeiro no que ele mostra, e por isso o par congelado×completo pode diferir (o D só é
# resolvido depois do congelamento).
# A prova roda do minuto 0 ao 180, "agora" é o minuto 120 e o FREEZE é o 90 — então o
# congelado só pode ter célula com minuto ≤ 90, e o que estiver entre 90 e 120 aparece SÓ no
# completo. É essa a diferença que o competidor vê: o D do time-alfa (minuto 117) está na
# lista de submissões DELE e não está no placar.
SCOL='desc:asc:flag:username:univ short:team name:univ full:A:B:C:D:E:F:G:H:Total:Penalty:LastAC'
# lin <bandeira> <login> <sigla> <time> <univ> <A..H> <total> <penal> <lastac>
# ⚠ com 8 colunas, contar `:` à mão erra (célula vazia no meio é o caso ruim) — daí a função:
# ela ENUMERA as células, então "vazio" é um argumento visível e não um colapso de separador.
lin(){ local IFS=:; printf '%s\n' "$*"; }
UFPR='Univ. Federal do Paraná'; USP='Universidade de São Paulo'; UNB='Universidade de Brasília'
UNESP='Universidade Estadual Paulista'
{ printf 'icpc\n%s\n' "$SCOL"
  #    band login        sigla  time                  univ      A       B      C       D     E       F       G       H    tot pen last
  lin  br time-alfa    UFPR  "Alpha Team"          "$UFPR"  1/12\* 2/45\* 1/78    ""    1/33\* ""      2/-     ""    4 188 78
  lin  br time-delta   USP   "Dirac Delta"         "$USP"   1/20   1/-    1/61\*  3/-   2/70   1/85\*  ""      ""    4 256 85
  lin  br time-beta    UnB   "Beta Testers"        "$UNB"   1/33   2/-    ""      ""    1/52   ""      1/88\*  ""    3 173 88
  lin  br time-epsilon UNESP "Sufficient Epsilon"  "$UNESP" 1/40   ""     ""      2/-   ""     ""      ""      ""    1 40  40
  lin  br time-gama    UFPR  "Gamma Radiation"     "$UFPR"  ""     1/-    ""      ""    1/74   ""      ""      ""    1 74  74
  lin  ar time-zeta    USP   "Zeta Zero"           "$USP"   1/-    ""     ""      ""    ""     ""      ""      ""    0 0   0
} > "$C/var/placar.txt"
# o placar COMPLETO diverge do congelado em várias células — é EXATAMENTE esse delta que a
# cerimônia abre uma a uma (reveal.js pendingCells), incluindo uma virada de liderança
{ printf 'icpc\n%s\n' "$SCOL"
  lin  br time-delta   USP   "Dirac Delta"         "$USP"   1/20   2/104  1/61\*  3/112\* 2/70 1/85\*  ""      ""      6 532 112
  lin  br time-alfa    UFPR  "Alpha Team"          "$UFPR"  1/12\* 2/45\* 1/78    2/117   1/33\* ""    2/-     ""      5 325 117
  lin  br time-beta    UnB   "Beta Testers"        "$UNB"   1/33   2/-    ""      ""      1/52 ""      1/88\*  1/108\* 4 281 108
  lin  br time-epsilon UNESP "Sufficient Epsilon"  "$UNESP" 1/40   ""     ""      2/-     ""   ""      ""      ""      1 40  40
  lin  br time-gama    UFPR  "Gamma Radiation"     "$UFPR"  ""     2/-    ""      ""      1/74 ""      ""      ""      1 74  74
  lin  ar time-zeta    USP   "Zeta Zero"           "$USP"   1/-    ""     ""      ""      ""   ""      ""      ""      0 0   0
} > "$C/var/placar-full.txt"
# cores dos balões: a PALETA OFICIAL do ICPC, na ordem das letras (é a que a organização
# compra e a que o competidor vê amarrada na cadeira). Ela é de propósito o pior caso do
# desenho: A é BRANCO e B é PRETO — no modo `fill` a célula do A só existe por causa do
# contorno do balloonEdge, e a do B inverte o texto p/ branco. Ver [[balao-branco-contorno]].
jq -cn '{A:"FFFFFF", B:"000000", C:"FF0000", D:"800000",
         E:"FFFF00", F:"008000", G:"0000FF", H:"000080"}' > "$C/balloons.json"

# --- history dos times: é a fonte de "Todas Submissões" (6 campos, login implícito:
#     tempo:probid:lang:verdict:sub_epoch:subid)
h(){ # <login> <min-desde-o-inicio> <probid> <lang> <verdict> <subid>
  local ep=$((NOW-7200+$2*60))
  printf '%s:%s:%s:%s:%s:%s\n' "$ep" "$3" "$4" "$5" "$ep" "$6" >> "$C/users/$1/history"
}
# ⚠ o history do time-alfa é a LISTA DE SUBMISSÕES do tutorial do competidor e tem de FECHAR
# com o placar: cada AC aqui é uma célula lá, e o D (minuto 117, depois do freeze) é de
# propósito o par que mostra "resolvi e o placar não conta" — está na lista e não no congelado.
h time-alfa    12 demo#somatorio  C    "Accepted"                 aa01
h time-alfa    31 demo#labirinto  C    "Wrong Answer"             aa02
h time-alfa    33 demo#estadio    C++  "Accepted"                 aa03
h time-alfa    45 demo#labirinto  C    "Accepted"                 aa04
h time-alfa    62 demo#metro      Java "Wrong Answer"             aa05
h time-alfa    78 demo#cofre      C++  "Accepted"                 aa06
h time-alfa    86 demo#metro      Java "Time Limit Exceeded"      aa07
h time-alfa   101 demo#tapete     C    "Wrong Answer"             aa08
h time-alfa   117 demo#tapete     C    "Accepted"                 aa09
h time-alfa   119 demo#astrolabio Py   "Not Answered Yet"         aa10
h time-beta    33 demo#somatorio  C    "Accepted"                 bb01
h time-beta    52 demo#estadio    Java "Accepted"                 bb02
h time-beta    61 demo#labirinto  Java "Time Limit Exceeded"      bb03
h time-beta    74 demo#labirinto  Java "Wrong Answer"             bb04
h time-beta    88 demo#metro      C++  "Accepted"                 bb05
h time-beta   108 demo#astrolabio C++  "Not Answered Yet"         bb06
h time-gama    28 demo#labirinto  C    "Compilation Error"        cc01
h time-gama    74 demo#estadio    Java "Accepted"                 cc02
h time-gama   112 demo#cofre      Java "Not Answered Yet"         cc03
h time-delta   20 demo#somatorio  C++  "Accepted"                 dd01
h time-delta   55 demo#estadio    C++  "Runtime Error"            dd02
h time-delta   61 demo#cofre      C++  "Accepted"                 dd03
h time-delta   70 demo#estadio    C++  "Accepted"                 dd04
h time-delta   85 demo#bandejao   C++  "Accepted"                 dd05
h time-delta  104 demo#labirinto  C++  "Accepted"                 dd06
h time-delta  118 demo#tapete     Py   "Not Answered Yet"         dd07
h time-epsilon 40 demo#somatorio  Py   "Accepted"                 ee01
h time-epsilon 57 demo#tapete     Py   "Runtime Error"            ee02
h time-zeta    26 demo#somatorio  C    "Wrong Answer"             ff01

# --- rodadas: um aquecimento arquivado + a prova oficial em andamento
mkdir -p "$C/rounds/aquecimento"
jq -cn --argjson now "$NOW" \
  '{version:1, active:"prova",
    rounds:[{slug:"aquecimento", name:"Warm-up", kind:"warmup", state:"archived",
             start:($now-86400), end:($now-82800), published:true, problems:2},
            {slug:"prova", name:"Main round", kind:"official", state:"active",
             start:($now-7200), end:($now+3600), problems:8}]}' > "$C/rounds.json"
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
  "In problem B, can the maze have more than one exit? The statement does not say."
mkclar c2 time-gama A 1800 \
  "Does the N of the input fit in 32 bits?" \
  "Yes — see the bound in the Input section of the statement." true
mkclar c3 time-alfa general 600 \
  "Has the contest been extended?" \
  "The São Paulo site was given 20 extra minutes after a power outage. All other sites keep the original schedule." \
  true true
# notícias públicas do contest (contests/<c>/news.json)
jq -cn --argjson t "$((NOW-2400))" \
  '[{id:"n1", title:"Lunch is open from 12:00",
     text:"The cafeteria in block C is open to the teams. Bring your badge.", date:$t}]' \
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
jq -cn '{caderno_version:"v1.2", cover_note:"Hosted by MOJ · Supported by UnB",
         errata:"Problem C: read 1 <= N <= 10^5.",
         published:["info-sheet.pt","info-sheet.en","times.pt"]}' > "$C/docs/config.json"
# o que o COMPETIDOR vê de documento é a seção "Prova" da aba Contest, que sai do
# resources.json (escrito pelo doc_publish) — a aba 📄 é dos papéis de organização
jq -cn --arg c demo '[
  {label:"Info sheet (en)", url:("/api/v1/contest/doc?contest=" + $c + "&type=info-sheet&lang=en&fmt=pdf"), type:"info-sheet", lang:"en"},
  {label:"Info sheet (pt)", url:("/api/v1/contest/doc?contest=" + $c + "&type=info-sheet&lang=pt&fmt=pdf"), type:"info-sheet", lang:"pt"},
  {label:"Time limits sheet (en)", url:("/api/v1/contest/doc?contest=" + $c + "&type=times&lang=en&fmt=pdf"), type:"times", lang:"en"}]'   > "$C/resources.json"

# ENUNCIADOS: PDF de mentira + HTML de verdade. O HTML é o que a sanfona mostra ao lado do
# editor; sem ele o detalhe abre só com o editor e a tela perde o assunto do tutorial.
for k in somatorio labirinto cofre tapete estadio bandejao metro astrolabio; do
  printf '%%PDF-1.4\n' > "$C/enunciados/demo#$k.pdf"
done
mkstmt(){ # <chave> <título> <corpo-html>
  cat > "$C/enunciados/demo#$1.html" <<HTML
<html><body>
<h1 class="moj-title">$2</h1>
$3
<h2>Input</h2>
<p>The first line contains one integer <em>N</em> (1 &le; <em>N</em> &le; 10<sup>5</sup>).</p>
<h2>Output</h2>
<p>Print a single line with the answer.</p>
<h2>Examples</h2>
<table class="samples"><tr><th>Input</th><th>Output</th></tr>
<tr><td><pre>10</pre></td><td><pre>23</pre></td></tr>
<tr><td><pre>3</pre></td><td><pre>3</pre></td></tr></table>
</body></html>
HTML
}
mkstmt somatorio "A curious sum" \
  "<p>Given an integer <em>N</em>, add up every multiple of 3 or of 5 that is at most <em>N</em>. For example, for <em>N</em> = 10 the multiples are 3, 5, 6, 9 and 10 — adding up to 33.</p><p>Mind the size of the answer: it may not fit in a 32-bit integer.</p>"
mkstmt labirinto "Mirror maze" \
  "<p>A ray of light enters the top-left corner of a grid room full of mirrors. Tell which wall it leaves through.</p>"
mkstmt cofre "The dean's safe" \
  "<p>The safe opens when the digits of the password add up to a multiple of 7. Count how many <em>N</em>-digit passwords open it.</p>"
mkstmt tapete "Flying carpet" \
  "<p>A rectangular carpet covers part of a tiled floor. Compute the area left uncovered.</p>"
mkstmt estadio "A full stadium" \
  "<p>The crowd comes in through <em>N</em> turnstiles, each letting one person through every 4 seconds. Tell when the last fan sits down.</p>"
mkstmt bandejao "The cafeteria queue" \
  "<p>Each student takes a different time to be served. Reorder the queue so that the total waiting time is minimum.</p>"
mkstmt metro "The city subway" \
  "<p>Given the subway lines and their interchanges, tell the least number of train changes between two stations.</p>"
# ⚠ O H (astrolabio) fica SEM `.html` DE PROPÓSITO — só o `.pdf` acima. É a prova que
# distribui apenas o caderno em PDF: a sanfona dele abre com o TEMPO LIMITE (e o editor, se
# estiver ligado) e mais nada, e o enunciado sai pelo link PDF. Caso REAL e ilustrado no
# tutorial do competidor: dar um `mkstmt astrolabio` aqui é o que faria a foto voltar a mentir.

# --- TEMPO LIMITE calibrado (run/tl/<id>.json): é o que a sanfona mostra como "⏱ Tempo limite",
# um chip por linguagem. Sem isto o detalhe abre sem o bloco — e a foto do problema SÓ-PDF, que
# existe justamente p/ mostrar "abriu e só tem o tempo limite", não mostraria nada.
# ⚠ NÃO adianta gravar só o run/tl: o TL só é servido quando o CHECKSUM do arquivo bate com o
# do pacote — e checksum vazio é recusado de propósito (`tl_store_served_for`: sem checksum não
# se prova que aquele TL é desta versão do problema). Sem pacote no fixture, quem fecha a conta
# é o ÍNDICE DE DONOS (contests/treino/var/problem-owners.json), que carimba o `tl_checksum` e
# é EXATAMENTE de onde a rota do contest o lê em produção — ver "a fronteira do repositório de
# problemas" no CLAUDE.md. Então o fixture escreve os DOIS lados com o mesmo valor.
mkdir -p "$RUNF/tl" "$FIX/treino/var"
CKS_IDX=()
tlf(){ # <chave> <c/c++> <java> <python>
  local cks; cks="$(printf 'demo#%s' "$1" | md5sum | cut -c1-16)"
  CKS_IDX+=("$(jq -cn --arg id "demo#$1" --arg c "$cks" \
    '{id:$id, repo:"demo", prob:$id, title:$id, public:false, html:true,
      owner:"decano.cjudge", collaborators:[], collections:[], tl_checksum:$c}')")
  jq -cn --arg id "demo#$1" --argjson now "$NOW" --arg cks "$cks" \
     --arg c "$2" --arg j "$3" --arg p "$4" \
    '{id:$id, checksum:$cks, updated_at:$now,
      hosts:{cpu1:{tl:{default:$c, c:$c, cpp:$c, java:$j, py:$p}, at:$now}}}' \
    > "$RUNF/tl/demo#$1.json"
}
tlf somatorio 1.0000 2.0000 3.0000
tlf labirinto 2.0000 4.0000 6.0000
tlf cofre     1.0000 2.0000 3.0000
tlf tapete    3.0000 6.0000 9.0000
tlf estadio   1.0000 2.0000 3.0000
tlf bandejao  2.0000 4.0000 6.0000
tlf metro     2.0000 4.0000 6.0000
tlf astrolabio 1.0000 2.0000 3.0000
printf '%s\n' "${CKS_IDX[@]}" | jq -s --argjson now "$NOW" \
  '{generated_at:$now, count:length, problems:.}' > "$FIX/treino/var/problem-owners.json"

# --- chaves de webcast do telão (contests/<c>/webcast.json — wc_file)
jq -cn --argjson now "$NOW" \
  '{keys:[{id:"a1b2c3d4", key:"mojwc_DEMO0000000000000000000000demo", view:"public",
           label:"Auditorium screen", created_by:"telao.animeitor", created_at:($now-3600),
           revoked_at:null, fetches:412, last_at:($now-20), last_ip:"10.0.0.15"},
          {id:"e5f6a7b8", key:"mojwc_DEMO1111111111111111111111demo", view:"all",
           label:"YouTube stream", created_by:"telao.animeitor", created_at:($now-1800),
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
mksess time-alfa        "Alpha Team"      s_comp
mksess sala.staff       "Room staff"      s_staff
mksess chefe.cstaff     "Site chief"      s_cstaff
mksess telao.animeitor  "Big-screen desk" s_anim
mksess juri.judge       "Judge"           s_judge
mksess decano.cjudge    "Chief judge"     s_cjudge

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

# (Não há mais imagem recortada à mão: a staff-pega.png, que era um recorte das linhas da fila,
# passou a sair do próprio `?hide=` — ver a captura dela lá embaixo. Enquadramento que só existe
# fora do script é enquadramento que a próxima rodada sobrescreve em silêncio.)

# shot <arquivo.png> <papel> <caminho-da-página> [altura]
# O `sess=` diz ao servidor de captura QUAL sessão usar ao chamar o router (é o papel logado).
# aceita `--only judge` e `--only s_judge`: o comentário de uso sempre disse "papel", mas a
# comparação era com o nome da SESSÃO — quem lia a ajuda não capturava nada e nem sabia por quê
shot(){
  local name="$1" role="$2" path="$3" h="${4:-$SHOT_H}"
  [[ -n "$ONLY" && "$role" != "$ONLY" && "$role" != s_"$ONLY"* ]] && return 0
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
shot comp-contest.png      s_comp    /contest/                                    2130
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
# ⚠ com OITO problemas, a sanfona aberta precisa aparecer SOZINHA: sem isso a foto vira uma
# lista de linhas fechadas com um pedaço do enunciado no fim. `n+2` deixa só o 1º (A) e
# `-n+7` deixa só o 8º (H). O `+` do CSS é `%2B` na URL — na querystring, `+` é ESPAÇO.
SO_A='%23problemList%20.prob-item%3Anth-child(n%2B2)'
SO_H='%23problemList%20.prob-item%3Anth-child(-n%2B7)'
CLICK_H='%23problemList%20.prob-item%3Anth-child(8)%20.prob-left'
shot comp-problemas.png    s_comp    "/contest/?hide=$OCULTA,$CROMO"               720
shot comp-sanfona.png      s_comp    "/contest/?clickcss=.prob-left&times=1&hide=$OCULTA,$CROMO,$SO_A" 840
# a MESMA sanfona num problema que só tem PDF (o H): abre com o tempo limite e o editor, e o
# enunciado sai pelo link PDF. É a prova que distribui só o caderno — a maioria das maratonas.
shot comp-sanfona-pdf.png  s_comp    "/contest/?clickcss=$CLICK_H&times=1&hide=$OCULTA,$CROMO,$SO_H" 640
shot comp-submissoes.png   s_comp    "/contest/?hide=%23newsSection,%23resourcesSection,%23problemsSection,%23userSection,$CROMO" 740
shot comp-placar.png       s_comp    /contest/score/                               700
shot comp-clarification.png s_comp   /contest/clarification/                       960
# as duas telas de serviço do competidor: pedir impressão do código e guardar arquivo no servidor
shot comp-impressao.png    s_comp    /contest/print/                               720
shot comp-backup.png       s_comp    /contest/backup/                              700
# a MESMA sanfona com o editor DESLIGADO (SHOWEDITOR=0) — é o caso da Maratona SBC, em que a
# prova roda em máquina controlada e o time compila no ambiente dela, não no navegador
if [[ -z "$ONLY" || "s_$ONLY" == s_comp || "$ONLY" == s_comp ]]; then
  cp "$C/conf" "$C/conf.bak"; printf 'SHOWEDITOR=0
' >> "$C/conf"
  shot comp-sem-editor.png s_comp "/contest/?clickcss=.prob-left&times=1&hide=$OCULTA,$CROMO,$SO_A" 620
  mv -f "$C/conf.bak" "$C/conf"
fi
shot staff-fila.png        s_staff   /contest/staff/
# só as LINHAS da fila (sem topbar, título e intro): é a foto do "peguei a tarefa", e a
# tela inteira não cabe nela sem virar ilustração de outra coisa
FILA_SO='.topbar,.quicknav,h1,.container%20%3E%20p.muted,.container%20%3E%20a.btn,.pr-auto'
shot staff-pega.png        s_staff   "/contest/staff/?hide=$FILA_SO"           300
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
# ⚠ o ?click= casa por TEXTO do botão, e a interface do fixture está em INGLÊS (LOCALE=en):
# rótulo em português aqui = clique que não acontece e foto da tela errada, em silêncio.
shot cjudge-clarification.png s_cjudge "/contest/clarification/?click=edit answer&times=1" 1500
shot cjudge-painel.png     s_cjudge  /contest/chief/           1100
shot cjudge-docs.png       s_cjudge  "/contest/chief/?click=Documents&times=2" 1000
shot rodadas.png           s_staff   /contest/rounds/                              560

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
