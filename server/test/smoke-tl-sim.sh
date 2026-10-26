#!/bin/bash
# smoke-tl-sim.sh — a SIMULAÇÃO e a SUGESTÃO do tempo-limite no /problems/calib (lib/tl-sim.sh, 26/10/2026). Com os
# tempos que a calibração mediu (run/calib/<id>/<juiz>.json), o servidor diz como sairia o TL em outras configurações
# (cf do MOJ; resolução, a e b do Kattis), que soluções sairiam erradas em cada uma e qual configuração sugere.
# Casos: o normal (2 juízes, W = o máx entre eles), o teste morto no teto ("não medido"), o conflito (lenta mais rápida
# que a pass), o maior r do Kattis, ajustar o a, ajustar o b, o TLMOD sum e o TLOVERRIDE[default] (nada a sugerir).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
: "${MOJTOOLS_DIR:=$(cd "$ROOT/../../mojtools" 2>/dev/null && pwd)}"; export MOJTOOLS_DIR
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; PROBS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN" "$PROBS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" MOJ_PROBLEMS_DIR="$PROBS" TL_STORE_DIR="$RUN/tl" CALIB_DIR="$RUN/calib"
mkdir -p "$RUN/tl" "$RUN/calib" "$FIX/treino/var"
NOW="$EPOCHSECONDS"
echo '{"col":{"members":["autor"],"admins":[],"public_allowed":true,"title":"Col"}}' > "$FIX/treino/var/orgs.json"
fx_user "$FIX/treino" autor s "Autor"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino autor Autor "$NOW" > "$SESS/aut"
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:-${BODY:0:400}}"; ((fail++)); fi; DBG=""; }

# mk <prob> <conf> : o pacote (só o conf importa aqui) + sols vazias de cada categoria usada
mk(){ local P="$PROBS/col/$1"; mkdir -p "$P/sols/good" "$P/tests/input"; printf '%b' "$2" > "$P/conf"
  printf '{"owner":"autor","public":false,"display_title":"%s"}\n' "$1" > "$P/.moj-meta.json"; printf '1\n' > "$P/tests/input/t1"
  ( cd "$P" && git init -q 2>/dev/null; git add -A && git -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm x ) >/dev/null 2>&1; }
# sol <cat> <file> <lang> <verdict> <etl> <code:time …> : uma solução (JSON) com os testes
sol(){ local cat="$1" f="$2" l="$3" v="$4" e="$5"; shift 5; local ts="" i=0 x
  for x in "$@"; do i=$((i+1)); ts+="${ts:+,}{\"name\":\"t$i\",\"code\":\"${x%%:*}\",\"time\":${x#*:},\"tl\":5}"; done
  printf '{"file":"%s","lang":"%s","category":"%s","verdict":"%s","method":"moj","etl":%s,"tests":[%s]}' "$f" "$l" "$cat" "$v" "$e" "$ts"; }
# host <prob> <juiz> <sol-json…> : o relatório de calibração do juiz
host(){ local p="$1" h="$2"; shift 2; mkdir -p "$CALIB_DIR/col#$p"
  printf '{"host":"%s","checksum":"","at":%s,"log":"x","sols":[%s]}\n' "$h" "$NOW" "$(IFS=,; echo "$*")" > "$CALIB_DIR/col#$p/$h.json"; }
get(){ OUT="$(PATH_INFO=/problems/calib REQUEST_METHOD=GET QUERY_STRING="id=col%23$1" HTTP_AUTHORIZATION="Bearer aut" bash "$ROUTER" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
row(){ jq -c --argjson v "$2" ".tl_sim.$1.rows[] | select(.${3:-cf} == \$v)" <<<"$BODY"; }

echo "== o caso normal: 2 juízes; W = o máx; pass, lenta medida, lenta morta no teto, wrong fora =="
mk pa 'CALIBRATIONTL=5\n'
G1="$(sol good a.c c Accepted,100p 7.2 AC:0.10 AC:0.45)"; G2="$(sol good b.py py Accepted,100p 7.2 AC:1.00)"
PS="$(sol pass p.c c Accepted,100p 2.8 AC:0.20 AC:0.55)"; S1="$(sol slow s.c c 'Time Limit Exceeded,0p' 3.0 AC:0.10 TLE:2.00)"
S2="$(sol slow k.c c 'Time Limit Exceeded,0p' 2.6 AC:0.10 TLE:2.6)"; WR="$(sol wrong w.c c 'Wrong Answer,0p' 2.6 WA:0.10)"
host pa j1 "$G1" "$G2" "$PS" "$S1" "$S2" "$WR"
host pa j2 "$(sol good a.c c Accepted,100p 7.2 AC:0.10 AC:0.40)" "$(sol good b.py py Accepted,100p 7.2 AC:0.90)" "$PS" "$S1"
get pa
ck "W por linguagem = o máx entre os juízes (c 0,45; py 1; default = o menor W de cada juiz, o máx)" '[[ "$(jq -c ".tl_sim.w" <<<"$BODY")" == "{\"c\":0.45,\"py\":1,\"default\":0.45}" && "$(jq -c ".tl_sim.hosts" <<<"$BODY")" == "[\"j1\",\"j2\"]" ]]'
ck "MOJ: o intervalo de cf (piso pela pass 0,55; teto pela lenta medida 2,0)" '[[ "$(jq -c ".tl_sim.moj.interval | [.min, .min_by, .max, .max_by]" <<<"$BODY")" == "[1.177778,\"pass/p.c\",4.4,\"slow/s.c\"]" ]]'
ck "MOJ cf = 1: a pass sai TLE (TL c = 0,47)"     '[[ "$(row moj 1 | jq -c "[.tl.c, .ok, .fail]")" == "[0.47,false,[\"pass/p.c\"]]" ]]'
ck "MOJ cf = 1,35 (o do conf): tudo certo, marcado como atual" '[[ "$(row moj 1.35 | jq -c "[.tl.c, .ok, .current]")" == "[0.6275,true,true]" ]]'
ck "sugestão MOJ: manter o atual"               '[[ "$(jq -c ".tl_suggest.moj | [.state, .cf, .why]" <<<"$BODY")" == "[\"keep\",1.35,\"current_valid\"]" ]]'
ck "Kattis r = 1 (o do conf): TL c 1 s; lenta 2,0 ≥ 1,5 × 1; a morta no teto 2,6 também decide" '[[ "$(row kattis 1 r | jq -c "[.tl.c, .tl.py, .ok, .unmeasured]")" == "[1,2,true,[]]" ]]'
ck "Kattis r = 0,01: TL c = 0,9 (o menor múltiplo de 0,01 ≥ 2 × 0,45)" '[[ "$(row kattis 0.01 r | jq -c "[.tl.c, .ok]")" == "[0.9,true]" ]]'
ck "sugestão Kattis: o maior r que vale (o do conf)" '[[ "$(jq -c ".tl_suggest.kattis | [.state, .r, .why]" <<<"$BODY")" == "[\"keep\",1,\"current_valid\"]" ]]'

echo "== teste morto no teto que não decide: \"não medido\", não reprova =="
mk pm 'CALIBRATIONTL=5\n'
host pm j1 "$(sol good a.c c Accepted,100p 7.2 AC:0.45)" "$(sol slow k.c c 'Time Limit Exceeded,0p' 1.0 TLE:1.0)"
get pm
ck "Kattis r = 1: TL 1, b × TL = 1,5 > o teto 1,0 — a lenta fica não medida, a linha vale" '[[ "$(row kattis 1 r | jq -c "[.ok, .unmeasured, .fail]")" == "[true,[\"slow/k.c\"],[]]" ]]'

echo "== conflito: a lenta é mais rápida que a pass =="
mk pc 'CALIBRATIONTL=5\n'
host pc j1 "$(sol good a.c c Accepted,100p 7.2 AC:0.45)" "$(sol pass p.c c Accepted,100p 5 AC:2.0)" "$(sol slow s.c c 'Time Limit Exceeded,0p' 5 TLE:1.5)"
get pc
ck "MOJ: conflito, com a pass e a lenta que se cruzam" '[[ "$(jq -c ".tl_suggest.moj | [.state, .pass, .slow]" <<<"$BODY")" == "[\"conflict\",\"pass/p.c\",\"slow/s.c\"]" ]]'
ck "Kattis: conflito (nenhum r, a ou b resolve)" '[[ "$(jq -c ".tl_suggest.kattis | [.state, .pass, .slow]" <<<"$BODY")" == "[\"conflict\",\"pass/p.c\",\"slow/s.c\"]" ]]'

echo "== Kattis: o maior r que vale; ajustar o a; ajustar o b =="
mk pr 'CALIBRATIONTL=5\n'
host pr j1 "$(sol good a.c c Accepted,100p 7.2 AC:0.05)" "$(sol pass p.c c Accepted,100p 5 AC:0.06)" "$(sol slow s.c c 'Time Limit Exceeded,0p' 5 TLE:0.5)"
get pr
ck "W 0,05, lenta 0,5: r 1 e 0,5 reprovam a lenta; o maior que vale é 0,2" '[[ "$(row kattis 1 r | jq -c .fail)" == "[\"slow/s.c\"]" && "$(jq -c ".tl_suggest.kattis | [.state, .r, .why]" <<<"$BODY")" == "[\"change\",0.2,\"largest_r\"]" ]]'
mk pa2 'CALIBRATIONTL=5\nKATTIS_TIME_RESOLUTION=0.1\n'
host pa2 j1 "$(sol good a.c c Accepted,100p 7.2 AC:0.45)" "$(sol pass p.c c Accepted,100p 5 AC:0.55)" "$(sol slow s.c c 'Time Limit Exceeded,0p' 5 TLE:1.0)"
get pa2
ck "nenhum r com a = 2; a = 1,25 (TL 0,6) vale com o r do conf" '[[ "$(jq -c ".tl_suggest.kattis | [.state, .a, .r, .why]" <<<"$BODY")" == "[\"change\",1.25,0.1,\"adjust_a\"]" ]]'
mk pb 'CALIBRATIONTL=5\nKATTIS_TIME_RESOLUTION=0.1\n'
host pb j1 "$(sol good a.c c Accepted,100p 7.2 AC:0.45)" "$(sol pass p.c c Accepted,100p 5 AC:0.85)" "$(sol slow s.c c 'Time Limit Exceeded,0p' 5 TLE:1.25)"
get pb
ck "nem r nem a; b = 1,3 vale (TL 0,9 e 1,3 × 0,9 ≤ 1,25)" '[[ "$(jq -c ".tl_suggest.kattis | [.state, .a, .b, .r, .why]" <<<"$BODY")" == "[\"change\",2,1.3,0.1,\"adjust_b\"]" ]]'

echo "== a regra do servidor: TLMOD sum entra; TLOVERRIDE[default] é final =="
mk pt 'CALIBRATIONTL=5\nTLMOD[c.sum]=1\n'
host pt j1 "$G1" "$PS" "$S1"
get pt
ck "TLMOD[c.sum]=1: cf 1 já dá TL c 1,47 (a pass passa)" '[[ "$(row moj 1 | jq -c "[.tl.c, .ok]")" == "[1.47,true]" ]]'
mk po 'CALIBRATIONTL=5\nTLOVERRIDE[default]=2\n'
host po j1 "$G1" "$PS" "$S1"
get po
ck "TLOVERRIDE[default]: o TL é 2 em toda linha e não há o que sugerir" '[[ "$(row moj 3 | jq -r .tl.c)" == 2 && "$(jq -c ".tl_suggest | [.moj.state, .moj.why, .kattis.state]" <<<"$BODY")" == "[\"none\",\"override\",\"none\"]" && "$(jq -c .tl_sim.overrides <<<"$BODY")" == "[\"default\"]" ]]'

echo "== sem calibração: tl_sim null; com calibração em voo, não calcula =="
mk pv 'CALIBRATIONTL=5\n'
get pv
ck "problema sem relatório de calibração: null (no_data), e a rota responde" '[[ "$(jq -r .success <<<"$BODY")" == true && "$(jq -c "[.tl_sim, .tl_suggest, .tl_sim_state]" <<<"$BODY")" == "[null,null,\"no_data\"]" ]]'
get pa
ck "com dados: tl_sim_state ok"                 '[[ "$(jq -r .tl_sim_state <<<"$BODY")" == ok ]]'
source "$ROOT/judge-gw/sched-lib.sh"; sched_init_dirs; mkdir -p "$UPDATESDIR/pending"; cal_request col "col#pa" autor >/dev/null
get pa
ck "calibração em voo: não calcula (os dados estão pela metade; o editor consulta a cada 4 s)" '[[ "$(jq -r .being_calibrated <<<"$BODY")" == true && "$(jq -c "[.tl_sim, .tl_sim_state]" <<<"$BODY")" == "[null,\"calibrating\"]" ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
