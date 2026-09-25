#!/bin/bash
# smoke-review-rules.sh — O QUE VAI PARA REVISÃO no veredicto manual (lib/review-rules.sh, v2 OPT-OUT) e a
# tela/API /contest/auto-verdicts (25/09/2026: o Vinícius pediu opt-out do automático; o Daniel Saad, título
# no lugar do id). Prende:
#   · a REGRA, caso a caso, no daemon (auto_allows/should_hold extraídos do judged.sh) E no espelho Python
#     (daemons/ingest-drain.py) — os dois têm de concordar em TODO caso (o Python libera veredicto sozinho
#     no dreno de emergência: discordar dali vaza);
#   · v1 (formato antigo, opt-in) segue valendo como sempre; ausente = tudo automático; ilegível = tudo em
#     revisão; erro do juiz sempre em revisão;
#   · GET: estado, regras na visão v2 (v1 convertido), letra+título na ordem da prova, linguagens do contest;
#   · POST v2 saneado (problema de fora e classe inventada caem; py3 vira py; linguagem esquisita = 422);
#     cliente antigo ({matrix}) ainda grava v1;
#   · "liberar": só o que as regras soltam, sem voto e sem conflito — e o `releasable` bate;
#   · permissões (juiz lê, só admin/chefe grava) e o item `manual` do preflight.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; SPOOL="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$SPOOL" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" SPOOLDIR="$SPOOL" RUNDIR="$RUN"
C="$FIX/rv"; mkdir -p "$C/var" "$C/review"
NOW=$EPOCHSECONDS
{ printf 'CONTEST_ID=rv\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nMANUAL_VERDICT=1\nLANGUAGES="c cpp py3"\n' "$((NOW-3600))" "$((NOW+3600))"
  printf "PROBS=( z col/pz 'Zeta' A 'col#pz' a col/pa 'Árvore Six Seven' B 'col#pa' b col/pb 'Balanço' C 'col#pb' )\n"; } > "$C/conf"
for u in rv.admin j1.judge cj.cjudge aluno1; do fx_user "$C" "$u" p "$u"; done
for s in adm:rv.admin j1:j1.judge cj:cj.cjudge alu:aluno1; do printf 'CONTEST=rv\nLOGIN=%s\nUSERFULLNAME=x\nLOGINAT=1\n' "${s#*:}" > "$SESS/${s%%:*}"; done
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="contest=rv" HTTP_AUTHORIZATION="Bearer ${4:-adm}" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:-${BODY:0:400}}"; ((fail++)); fi; }
J(){ printf '%s' "$BODY" | jq -r "$1" 2>/dev/null; }

# a decisão do DAEMON: as funções de verdade, extraídas do judged.sh
source "$ROOT/api/v1/lib/review-rules.sh"
# (auto_allows é de UMA linha: um intervalo /^auto_allows()/,/^}/ engoliria o should_hold e o
#  imprimiria duas vezes — a 1ª chamada só o redefiniria)
source /dev/stdin <<< "$(sed -n '/^auto_allows() {.*}$/p; /^should_hold()/,/^}/p' "$ROOT/daemons/judged.sh")"
declare -f auto_allows should_hold >/dev/null || { echo "FAIL: funções do daemon não extraídas"; exit 1; }
dhold(){ should_hold rv aluno1 "$1" "$2" "$3" "$3" && echo REV || echo AUTO; }
# o espelho Python
# o script vai por -c: o stdin é dos CASOS (um heredoc aqui roubaria o stdin do python)
PYSRC='
import importlib.util, sys
spec = importlib.util.spec_from_file_location("drain", sys.argv[1]); m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m); m.CONTESTS = sys.argv[2]
for line in sys.stdin:
    prob, lang, v = line.rstrip("\n").split("\t")
    m._conf.clear()
    print("REV" if m.should_hold("rv", "aluno1", prob, lang, v, v) else "AUTO")
'
py(){ python3 -c "$PYSRC" "$ROOT/daemons/ingest-drain.py" "$FIX"; }
CASES="$(for p in 'col#pa' 'col/pa' 'col#pb' 'col#pz' 'col#nope'; do for l in C CPP PY py3 JAVA; do
  for v in Accepted 'Wrong Answer' 'Time Limit Exceeded' 'Memory Limit Exceeded' 'Runtime Error' 'Compilation Error' 'Judge Error' 'Presentation Error'; do
    printf '%s\t%s\t%s\n' "$p" "$l" "$v"; done; done; done)"
diff_rules(){ # <nome> — daemon × Python em todos os casos; ecoa os REV do daemon p/ asserções
  local d p; d="$(while IFS=$'\t' read -r a b c; do dhold "$a" "$b" "$c"; done <<<"$CASES")"
  p="$(printf '%s\n' "$CASES" | py)"
  DBG="$(paste <(printf '%s\n' "$CASES") <(printf '%s\n' "$d") <(printf '%s\n' "$p") | awk -F'\t' '$4!=$5' | head -5)"
  ck "$1: daemon (bash) e ingest-drain (Python) concordam nos $(grep -c . <<<"$CASES") casos" '[[ "$d" == "$p" ]]'
  DAEMON="$(paste <(printf '%s\n' "$CASES") <(printf '%s\n' "$d"))"; DBG=""; }
dec(){ awk -F'\t' -v p="$1" -v l="$2" -v v="$3" '$1==p && $2==l && $3==v {print $4}' <<<"$DAEMON"; }

echo "== regra: sem arquivo (v2 vazio) =="
diff_rules "ausente"
ck "tudo automático; erro do juiz e classe legada em revisão" '[[ "$(dec "col#pa" C "Wrong Answer") $(dec "col#pa" C "Judge Error") $(dec "col#pa" C "Presentation Error")" == "AUTO REV REV" ]]'

echo "== regra: v1 (formato antigo, opt-in) =="
echo '{"col#pa":{"*":["Compilation Error","Accepted"],"cpp":["Wrong Answer"]},"col#pb":{"*":["Presentation Error"]}}' > "$C/auto-verdicts.json"
diff_rules "v1"
ck "v1: listado sai automático (CE, AC; WA só em cpp), o resto revisão" '[[ "$(dec "col#pa" C "Compilation Error") $(dec "col/pa" C Accepted) $(dec "col#pa" CPP "Wrong Answer") $(dec "col#pa" C "Wrong Answer") $(dec "col#pz" C Accepted)" == "AUTO AUTO AUTO REV REV" ]]'
ck "v1: vocabulário legado listado segue automático (como sempre foi)" '[[ "$(dec "col#pb" C "Presentation Error")" == AUTO ]]'

echo "== regra: v2 (opt-out) =="
echo '{"version":2,"review":{"col#pa":["Time Limit Exceeded"],"col#pb":["Accepted","Wrong Answer"]},"langs":[{"lang":"py","problem":"*","verdicts":["Time Limit Exceeded","Wrong Answer"],"to":"review"},{"lang":"PY3","problem":"col#pa","verdicts":["Time Limit Exceeded"],"to":"auto"},{"lang":"cpp","problem":"*","verdicts":["Accepted"],"to":"auto"},{"lang":"cpp","problem":"*","verdicts":["Accepted"],"to":"review"}]}' > "$C/auto-verdicts.json"
diff_rules "v2"
ck "grade: TLE em A revisão, WA em A automático, AC/WA em B revisão, Zeta tudo automático" '[[ "$(dec "col#pa" C "Time Limit Exceeded") $(dec "col#pa" C "Wrong Answer") $(dec "col#pb" C Accepted) $(dec "col#pz" C "Runtime Error")" == "REV AUTO REV AUTO" ]]'
ck "exceção: Python WA em revisão em todo problema; a do problema (py3 = py, TLE auto em A) vence a de todos" '[[ "$(dec "col#pz" PY "Wrong Answer") $(dec "col#pa" py3 "Time Limit Exceeded") $(dec "col#pz" PY "Time Limit Exceeded")" == "REV AUTO REV" ]]'
ck "empate no mesmo nível (cpp AC auto × revisão) = revisão; erro do juiz sempre revisão" '[[ "$(dec "col#pz" CPP Accepted) $(dec "col#pz" C "Judge Error")" == "REV REV" ]]'
printf '{"version":2,' > "$C/auto-verdicts.json"
diff_rules "ilegível"
ck "ilegível: tudo em revisão (na dúvida, segura)" '[[ "$(dec "col#pz" C Accepted)" == REV ]]'

echo "== GET =="
echo '{"col#pa":{"*":["Compilation Error","Accepted","Wrong Answer","Runtime Error"]},"col#pb":{"*":["Compilation Error"]},"col#pz":{"*":["Compilation Error","Accepted","Wrong Answer","Runtime Error"],"cpp":["Time Limit Exceeded"]}}' > "$C/auto-verdicts.json"
call /contest/auto-verdicts GET '' j1; DBG="$BODY"
ck "juiz lê: v1 convertido (B: tudo menos CE vai para revisão; A: TLE/MLE)" '[[ "$(J .state)" == v1 && "$(J ".rules.review[\"col#pb\"] | length")" == 5 && "$(J ".rules.review[\"col#pa\"] | join(\",\")")" == "Time Limit Exceeded,Memory Limit Exceeded" ]]'
ck "…e a exceção v1 por linguagem vira exceção 'sai automático'" '[[ "$(J ".rules.langs | tojson")" == "[{\"lang\":\"cpp\",\"problem\":\"col#pz\",\"to\":\"auto\",\"verdicts\":[\"Time Limit Exceeded\"]}]" ]]'
ck "letra + título na ORDEM da prova; linguagens do contest canônicas; manual ligado" '[[ "$(J "[.items[] | .letter + \":\" + .title] | join(\"|\")")" == "A:Zeta|B:Árvore Six Seven|C:Balanço" && "$(J ".langs | join(\",\")")" == "c,cpp,py" && "$(J .manual_verdict)" == true ]]'
call /contest/auto-verdicts GET '' alu
ck "competidor não lê (403)" '[[ "$OUT" == *"Status: 403"* ]]'

echo "== POST v2 =="
call /contest/auto-verdicts POST '{"rules":{"review":{"col#pa":["Wrong Answer"]}}}' j1
ck "juiz comum não grava (403)" '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/auto-verdicts POST '{"rules":{"review":{"col#pa":["Wrong Answer","Inventado"],"col#fora":["Accepted"],"col#pz":[]},"langs":[{"lang":"PY3","problem":"*","verdicts":["Time Limit Exceeded","Xyz"],"to":"review"},{"lang":"c","problem":"col#fora","verdicts":["Accepted"],"to":"auto"}]}}' cj; DBG="$BODY"
F="$(cat "$C/auto-verdicts.json")"
ck "chefe grava v2 saneado (classe inventada, problema de fora e linha vazia caem; py3 → py)" '[[ "$(jq -c "{version, review, langs}" <<<"$F")" == "{\"version\":2,\"review\":{\"col#pa\":[\"Wrong Answer\"]},\"langs\":[{\"lang\":\"py\",\"problem\":\"*\",\"verdicts\":[\"Time Limit Exceeded\"],\"to\":\"review\"}]}" && "$(jq -r .updated_by <<<"$F")" == cj.cjudge ]]'
call /contest/auto-verdicts POST '{"rules":{"review":{},"langs":[{"lang":"a b","problem":"*","verdicts":["Accepted"],"to":"auto"}]}}' adm
ck "linguagem esquisita → 422" '[[ "$OUT" == *"Status: 422"* ]]'
call /contest/auto-verdicts GET '' cj
ck "GET relê v2 (estado v2)" '[[ "$(J .state)" == v2 && "$(J ".rules.review[\"col#pa\"] | join(\",\")")" == "Wrong Answer" ]]'

echo "== liberar =="
item(){ jq -cn --arg id "$1" --arg p "$2" --arg l "$3" --arg v "$4" --argjson votes "$5" --argjson cf "$6" --arg st "$7" \
  '{id:$id, contest:"rv", login:"aluno1", problem_id:$p, lang:$l, sub_epoch:1, computed_verdict:$v, status:$st,
    claimants:[], votes:$votes, conflict:$cf}' > "$C/review/$1.json"; }
item aaaa0001 'col#pz' CPP 'Wrong Answer' '[]' false open            # Zeta WA: agora automático → libera
item aaaa0002 'col#pa' C 'Wrong Answer' '[]' false open              # A WA: segue em revisão
item aaaa0003 'col#pz' CPP 'Accepted' '[{"judge":"j1.judge","verdict":"Accepted"}]' false open   # com voto
item aaaa0004 'col#pz' C 'Runtime Error' '[]' true open              # em conflito
item aaaa0005 'col#pz' C 'Judge Error' '[]' false open               # erro do juiz
item aaaa0006 'col#pz' PY 'Time Limit Exceeded' '[]' false open      # py TLE: exceção → revisão
item aaaa0007 'col#pz' C 'Accepted' '[]' false released              # já liberado
item aaaa0008 'col#pb' C 'Time Limit Exceeded,30p. Pontos' '[]' false open   # sufixo de pontos: TLE automático → libera
call /contest/auto-verdicts GET '' cj; DBG="$BODY"
ck "releasable = 2 (sem voto, sem conflito, e as regras soltam; o sufixo de pontos não atrapalha)" '[[ "$(J .releasable)" == 2 ]]'
call /contest/auto-verdicts POST '{"action":"release"}' j1
ck "juiz comum não libera (403)" '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/auto-verdicts POST '{"action":"release"}' cj; DBG="$BODY"
ck "chefe libera 2; 5 seguem na fila" '[[ "$(J .released) $(J .left)" == "2 5" ]]'
ck "os 2 viram released com o veredicto computado; os outros intactos" '[[ "$(jq -r .status "$C/review/aaaa0001.json") $(jq -r .released_verdict "$C/review/aaaa0008.json") $(jq -r .status "$C/review/aaaa0002.json") $(jq -r .status "$C/review/aaaa0003.json") $(jq -r .status "$C/review/aaaa0004.json") $(jq -r .status "$C/review/aaaa0005.json") $(jq -r .status "$C/review/aaaa0006.json")" == "released Time Limit Exceeded,30p. Pontos open open open open open" ]]'
ck "o setverdict foi p/ o spool (o daemon aplica no history)" '[[ "$(grep -rl "aaaa0001" "$SPOOL" 2>/dev/null | wc -l)" -ge 1 ]]'
ck "auditado" 'grep -q "review-auto-release.*liberadas=2" "$C/var/admin-audit.log"'

echo "== cliente antigo e preflight =="
call /contest/auto-verdicts POST '{"matrix":{"col#pa":{"*":["Accepted"]}}}' adm
ck "POST {matrix} ainda grava v1" '[[ "$(jq -c . "$C/auto-verdicts.json")" == "{\"col#pa\":{\"*\":[\"Accepted\"]}}" ]]'
PF(){ call /contest/admin/preflight GET '' adm; printf '%s' "$BODY" | jq -r '.checks[] | select(.id=="manual") | "\(.level)|\(.label)|\(.label_en // "")|\(.detail)"'; }
rm -f "$C/auto-verdicts.json"; M="$(PF)"; DBG="$M"
ck "preflight: manual ligado e nada em revisão → warn bilíngue" '[[ "$M" == "warn|Veredicto manual ligado, mas nada vai para revisão|Manual verdict is on, but nothing goes to review|"* ]]'
echo '{"version":2,"review":{"col#pa":["Wrong Answer","Accepted"]},"langs":[{"lang":"py","problem":"*","verdicts":["Accepted"],"to":"review"}]}' > "$C/auto-verdicts.json"; M="$(PF)"; DBG="$M"
ck "preflight: conta o que vai para revisão (2 + 1 exceção, 2 juízes)" '[[ "$M" == "ok|Veredicto manual LIGADO|Manual verdict ON|2 combinação(ões)"*"+ 1 exceção"*"2 juiz(es)"* ]]'
printf 'x' > "$C/auto-verdicts.json"; M="$(PF)"; DBG="$M"
ck "preflight: regras ilegíveis → warn" '[[ "$M" == "warn|Regras de revisão ilegíveis|"* ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
