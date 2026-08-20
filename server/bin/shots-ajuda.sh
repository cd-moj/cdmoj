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
#       --only  captura só um papel (staff|cstaff|animeitor|judge|cjudge)
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
  printf 'CONTEST_START=%s\nCONTEST_END=%s\nFREEZE_TIME=60\n' "$((NOW-7200))" "$((NOW+3600))"
  printf 'PRINT=1\nMANUAL_VERDICT=1\nREVIEW_JUDGES=2\n'
  printf 'PROBS=( a demo#somatorio "Somatório curioso" b demo#labirinto "Labirinto de espelhos" c demo#cofre "O cofre do reitor" d demo#tapete "Tapete voador" )\n'
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
mk_user time-beta    "Beta Testers"        UTFPR "Curitiba" br
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
mkpr p3 time-beta  "Beta Testers"     UTFPR "solucao-a.c"   processed 6 print   900
mkpr b1 time-alfa  "Os Alfabetizados" UFPR  ""              pending   9 balloon  60 A e63946 vermelho
mkpr b2 time-beta  "Beta Testers"     UTFPR ""              pending  10 balloon  30 C 2a9d8f verde

# --- placar (TXT cru, como o build.sh gera): cabeçalho + 6 linhas
{ printf 'icpc\n'
  printf '#\tTime\tUniv\tBandeira\tSede\tA\tB\tC\tD\tTot\tPen\tguest\n'
  printf '1\tOs Alfabetizados\tUFPR\tbr\tCuritiba\t1/12\t2/45\t1/78\t-\t3\t147\t\n'
  printf '2\tDelta de Dirac\tUSP\tbr\tSão Paulo\t1/20\t-\t1/61\t3/-\t2\t81\t\n'
  printf '3\tBeta Testers\tUTFPR\tbr\tCuritiba\t1/33\t2/-\t-\t-\t1\t33\t\n'
  printf '4\tÉpsilon Suficiente\tUNESP\tbr\tSão Paulo\t1/40\t-\t-\t-\t1\t40\t\n'
  printf '5\tGama Radiação\tUFPR\tbr\tCuritiba\t-\t1/-\t-\t-\t0\t0\t\n'
  printf '6\tZeta Zero\tUSP\tar\tSão Paulo\t-\t-\t-\t-\t0\t0\t\n'
} > "$C/var/placar.txt"
cp "$C/var/placar.txt" "$C/var/placar-full.txt"

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

# shot <arquivo.png> <papel> <caminho-da-página> [altura]
# O `sess=` diz ao servidor de captura QUAL sessão usar ao chamar o router (é o papel logado).
shot(){
  local name="$1" role="$2" path="$3" h="${4:-$SHOT_H}"
  [[ -n "$ONLY" && "$role" != "$ONLY" ]] && return 0
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
shot staff-fila.png       s_staff   /contest/staff/
shot staff-telao.png      s_staff   /contest/animeitor/       1100
shot cstaff-fila.png      s_cstaff  /contest/staff/
shot cstaff-etiquetas.png s_cstaff  /contest/badges/          1100
shot cstaff-telao.png     s_cstaff  /contest/animeitor/       1100
shot cstaff-placar.png    s_cstaff  /contest/score/
shot animeitor-telao.png  s_anim    /contest/animeitor/       1250
shot animeitor-placar.png s_anim    /contest/score/
shot judge-fila.png       s_judge   /contest/judge/
shot cjudge-painel.png    s_cjudge  /contest/chief/           1100

echo ">> pronto: $OUT"
