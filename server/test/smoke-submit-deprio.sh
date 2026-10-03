#!/bin/bash
# smoke-submit-deprio.sh — MENOS PRIORIDADE na prova p/ o time com muitas pendentes (01/10/2026).
# Na prova (CONTEST_PRIORITY prova/super) não há teto de envios; a partir do 6º envio esperando o juiz
# (SUBMIT_DEPRIO_PENDING=5 já pendentes + o que chega), o job entra na MESMA banda com o nome da fila
# adiantado SUBMIT_DEPRIO_DELAY (120) s — como se tivesse chegado depois. Conforme os veredictos saem, o
# próximo volta ao normal. Envio segurado na revisão manual não conta. Lista nunca é adiantada.
# Cobre o daemon (judged.sh --drain), o gêmeo Python (daemons/spool-drain.py) e o escalonador: a ordem
# da fila segue o nome, mas as carências do q_claim (COLD/LANG/POOL) contam a idade REAL (`enq`) — o
# atraso não pode virar "job mais novo" p/ o juiz frio — e a promoção de famintos segue o nome.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" QUEUEDIR="$RUN/queue" \
       SPOOLDIR="$RUN/spool/submissions" SPOOLDONEDIR="$RUN/spool/submissions-done"
unset SUBMIT_DEPRIO_PENDING SUBMIT_DEPRIO_DELAY SUBMIT_MAX_INFLIGHT
mkdir -p "$SPOOLDIR" "$SPOOLDONEDIR"
NOW="$EPOCHSECONDS"
mkc(){ # <id> <prioridade> [linhas extras do conf]
  local C="$FIX/$1"; mkdir -p "$C/var" "$C/enunciados"
  { printf 'CONTEST_ID=%s\nCONTEST_NAME=%s\nCONTEST_TYPE=icpc\nCONTEST_PRIORITY=%s\n' "$1" "$1" "$2"
    printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW-3600))" "$((NOW+3600))"
    printf "PROBS=( x col#pa Alfa A col#pa )\n"; printf '%s' "${3:-}"; } > "$C/conf"
  fx_user "$C" aluno s "Aluno"
  printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' "$1" aluno Aluno "$NOW" > "$SESS/alu-$1"
}
B64C="$(printf 'int main(){return 0;}' | base64 -w0)"
BODYJ="{\"problem_id\":\"col#pa\",\"filename\":\"a.c\",\"code_b64\":\"$B64C\"}"
sub(){ # <contest> -> SID (id da submissão)
  local o; o="$(PATH_INFO=/submit REQUEST_METHOD=POST QUERY_STRING="contest=$1" HTTP_AUTHORIZATION="Bearer alu-$1" \
    bash "$ROUTER" <<<"$BODYJ" 2>/dev/null)"
  SID="$(printf '%s' "$o" | awk 'f{print} /^\r?$/{f=1}' | jq -r '.submission_id // empty' 2>/dev/null)"; }
drain(){ ( cd "$ROOT/daemons" && JUDGE_BACKEND=queue INTAKE_MODE=queue bash judged.sh --drain >/dev/null 2>&1 ); }
# qts <id> -> prefixo (epoch) do nome do job na fila
qts(){ local f; f="$(find "$QUEUEDIR" -mindepth 2 -name "*_$1.json" -print -quit)"; f="${f##*/}"; printf '%s' "${f%%_*}"; }
qenq(){ jq -r .enqueued_at "$(find "$QUEUEDIR" -mindepth 2 -name "*_$1.json" -print -quit)" 2>/dev/null; }
adiantado(){ local t; t="$(qts "$1")"; [[ -n "$t" ]] && (( t - $(qenq "$1") >= ${2:-120} )); }
normal(){ local t; t="$(qts "$1")"; [[ -n "$t" ]] && (( t - $(qenq "$1") <= 2 )); }
verdict(){ sed -i "0,/:$1\$/s/Not Answered Yet/Wrong Answer/" "$FIX/$2/users/aluno/history"; }
pass=0; fail=0; DBG=""
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:0:200}"; ((fail++)); fi; }

echo "== prova: 5 pendentes normais, o 6º entra adiantado na MESMA banda =="
mkc pv prova
S=(); for i in 1 2 3 4 5; do sub pv; S+=("$SID"); drain; done
DBG="$(ls "$QUEUEDIR"/*/ 2>/dev/null | tr '\n' ' ')"
ok=1; for s in "${S[@]}"; do normal "$s" || ok=0; done
ck "1º–5º: nome = hora de entrada"            '(( ok == 1 && ${#S[@]} == 5 ))'
sub pv; S6="$SID"; drain
DBG="$(qts "$S6") vs $(qenq "$S6")"
ck "6º pendente: nome adiantado 120 s"          'adiantado "$S6"'
ck "na mesma banda (020-prova)"                 '[[ -n "$(find "$QUEUEDIR/020-prova" -name "*_$S6.json")" ]]'
ck "enqueued_at do job segue REAL"              '(( $(qenq "$S6") >= NOW && $(qenq "$S6") <= EPOCHSECONDS ))'
ck "auditado no log do contest"                 'grep -q "envio-deprio.*id=$S6.*pendentes=6" "$FIX/pv/var/admin-audit.log"'
echo "== veredictos saem ⇒ o próximo volta ao normal =="
verdict "${S[0]}" pv; verdict "${S[1]}" pv          # 6 - 2 = 4 pendentes; o 7º faz 5
sub pv; S7="$SID"; drain
DBG="$(qts "$S7") vs $(qenq "$S7")"
ck "7º com 5 esperando: normal"                 'normal "$S7"'
sub pv; S8="$SID"; drain
ck "8º com 6 esperando: adiantado de novo"      'adiantado "$S8"'
echo "== revisão manual: envio SEGURADO não conta como esperando o juiz =="
mkdir -p "$FIX/pv/review"; printf '{"id":"%s","status":"open"}' "${S[2]}" > "$FIX/pv/review/${S[2]}.json"
DBG="$(grep -c 'Not Answered' "$FIX/pv/users/aluno/history")"
sub pv; S9="$SID"; drain                            # 7 no history, 1 segurado ⇒ 6 esperando: adiantado
ck "7 pendentes, 1 segurado: conta 6 (adiantado)" 'adiantado "$S9" && grep -q "id=$S9.*pendentes=6" "$FIX/pv/var/admin-audit.log"'
printf '{"id":"%s","status":"open"}' "${S[3]}" > "$FIX/pv/review/${S[3]}.json"
printf '{"id":"%s","status":"open"}' "${S[4]}" > "$FIX/pv/review/${S[4]}.json"
sub pv; S10="$SID"; drain                           # 8 no history, 3 segurados ⇒ 5: normal
ck "8 pendentes, 3 segurados: conta 5 (normal)"  'normal "$S10"'
echo "== spool represado: 8 envios antes de o daemon ler o 1º ⇒ só o 6º em diante é adiantado =="
mkc rp prova
B=(); for i in 1 2 3 4 5 6 7 8; do sub rp; B+=("$SID"); done; drain
DBG="$(for s in "${B[@]}"; do printf '%s ' $(( $(qts "$s") - $(qenq "$s") )); done)"
ok=1; for i in 0 1 2 3 4; do normal "${B[i]}" || ok=0; done; for i in 5 6 7; do adiantado "${B[i]}" || ok=0; done
ck "1º–5º normais, 6º–8º adiantados (conta até a linha do envio)" '(( ok == 1 ))'
echo "== super idem; lista nunca; desligar e trocar o atraso pelo env =="
mkc sup super
for i in 1 2 3 4 5 6; do sub sup; drain; done
ck "super: 6º adiantado"                        'adiantado "$SID"'
mkc lst lista-publica 'SUBMIT_MAX_INFLIGHT=0
'
for i in 1 2 3 4 5 6 7; do sub lst; drain; done
ck "lista (teto desligado, 7 pendentes): nunca adiantado" 'normal "$SID" && ! grep -q envio-deprio "$FIX/lst/var/admin-audit.log" 2>/dev/null'
mkc off prova
for i in 1 2 3 4 5 6; do sub off; SUBMIT_DEPRIO_PENDING=0 drain; done
ck "SUBMIT_DEPRIO_PENDING=0 desliga"            'normal "$SID"'
mkc dl prova
for i in 1 2 3 4 5 6; do sub dl; SUBMIT_DEPRIO_DELAY=600 drain; done
ck "SUBMIT_DEPRIO_DELAY=600"                    'adiantado "$SID" 600'

echo "== gêmeo Python (daemons/spool-drain.py): mesma regra =="
pyrun(){ # <id> [env...] -> roda process() do drenador sobre o arquivo de spool DESSE envio
  local b; b="$(find "$SPOOLDIR" -maxdepth 1 -name "*:$1:*" -printf '%f' -quit)"; shift
  env PYTHONDONTWRITEBYTECODE=1 "$@" python3 - "$ROOT/daemons/spool-drain.py" "$b" <<'EOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sd", sys.argv[1]); m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m); sys.exit(0 if m.process(sys.argv[2]) else 1)
EOF
}
mkc py prova
P=(); for i in 1 2 3 4 5 6 7 8 9; do sub py; P+=("$SID"); done     # 9 linhas pendentes, nada drenado
pyrun "${P[5]}"; DBG="$(qts "${P[5]}") vs $(qenq "${P[5]}")"
ck "6º: adiantado 120 s"                        'adiantado "${P[5]}"'
ck "auditado"                                   'grep -q "envio-deprio.*id=${P[5]}.*pendentes=6" "$FIX/py/var/admin-audit.log"'
pyrun "${P[4]}"
ck "5º: normal"                                 'normal "${P[4]}"'
mkdir -p "$FIX/py/review"; for i in 0 1; do printf '{}' > "$FIX/py/review/${P[i]}.json"; done
pyrun "${P[6]}"; DBG="$(qts "${P[6]}") vs $(qenq "${P[6]}")"
ck "7º com 2 segurados ⇒ 5 esperando: normal"   'normal "${P[6]}"'
rm -f "$FIX/py/review/"*.json
pyrun "${P[7]}" SUBMIT_DEPRIO_PENDING=0
ck "SUBMIT_DEPRIO_PENDING=0 desliga"            'normal "${P[7]}"'
pyrun "${P[8]}" SUBMIT_DEPRIO_DELAY=600
ck "SUBMIT_DEPRIO_DELAY=600"                    'adiantado "${P[8]}" 600'
mkc pr prova
B=(); for i in 1 2 3 4 5 6 7 8; do sub pr; B+=("$SID"); done
for i in 7 6 5 4 3 2 1 0; do pyrun "${B[i]}" >/dev/null; done   # do último p/ o 1º, de propósito
DBG="$(for s in "${B[@]}"; do printf '%s ' $(( $(qts "$s") - $(qenq "$s") )); done)"
ok=1; for i in 0 1 2 3 4; do normal "${B[i]}" || ok=0; done; for i in 5 6 7; do adiantado "${B[i]}" || ok=0; done
ck "represado: 1º–5º normais, 6º–8º adiantados" '(( ok == 1 ))'

echo "== escalonador: ordem pelo nome, carência pela idade REAL, famintos pelo nome =="
( source "$ROOT/judge-gw/sched-lib.sh"; sched_init_dirs
  rm -rf "$QUEUEDIR"; sched_init_dirs
  now=$EPOCHSECONDS
  job(){ jq -cn --arg id "$1" --argjson e "${2:-$now}" '{id:$id, contest:"pv", problem_id:"o#p", login:"aluno", lang:"c",
           filename:"a.c", code_b64:"aQ==", priority:"prova", enqueued_at:$e}'; }
  q_enqueue a prova "$(job a)"; q_enqueue b prova "$(job b)" 120; q_enqueue c prova "$(job c)"
  claim(){ QC_SLOT_CPUS=1 QC_TOTAL_SLOTS=8 QC_MEM_KB=67108864 QC_POLICY=off q_claim "$1" "" "$2" '["c"]' "$3" | jq -r .id | tr '\n' ' '; }
  r="$(claim hq '{"o#p":1}' 3)"; [[ "$r" == "a c b " ]] && echo "OK1" || echo "XX1 $r"
  # juiz FRIO (sem o pacote): COLD_GRACE (8 s) pela idade real — o adiantado de 10 s atrás passa
  rm -rf "$QUEUEDIR" "$ASSIGNEDDIR"; sched_init_dirs
  q_enqueue velho prova "$(job velho $((now-10)))" 120; q_enqueue novo prova "$(job novo)"
  r="$(claim hf '{}' 2)"; [[ "$r" == "velho " ]] && echo "OK2" || echo "XX2 $r"
  # famintos (STARVE_SECS=300) pelo NOME: o adiantado com 310 s reais ainda não é promovido; o normal é
  rm -rf "$QUEUEDIR" "$ASSIGNEDDIR"; sched_init_dirs
  # o nome leva o EPOCHSECONDS da chamada (pode ter virado o segundo desde `now`): acha o arquivo, não adivinha
  qf(){ find "$QUEUEDIR/020-prova" -maxdepth 1 -name "*_$1.json" -print -quit; }
  q_enqueue fn prova "$(job fn $((now-310)))"; mv "$(qf fn)" "$QUEUEDIR/020-prova/$((now-310))_fn.json"
  q_enqueue fa prova "$(job fa $((now-310)))" 120; mv "$(qf fa)" "$QUEUEDIR/020-prova/$((now-190))_fa.json"
  rm -f "$QUEUEDIR/.starve-stamp"; q_promote_starved
  [[ -n "$(find "$QUEUEDIR/000-super" -name '*_fn.json')" && -n "$(find "$QUEUEDIR/020-prova" -name '*_fa.json')" ]] \
    && echo "OK3" || echo "XX3 $(find "$QUEUEDIR" -name '*.json' | sed "s|$QUEUEDIR/||" | tr '\n' ' ')"
  # q_enqueue sem atraso / atraso lixo = nome na hora
  rm -rf "$QUEUEDIR"; sched_init_dirs; q_enqueue z prova "$(job z)" abc
  [[ -n "$(find "$QUEUEDIR/020-prova" -name "${now}_z.json" -o -name "$((now+1))_z.json")" ]] && echo "OK4" || echo "XX4"
) > "$RUN/sched.out" 2>&1
DBG="$(tr '\n' ' ' < "$RUN/sched.out")"
ck "ordem: a, c, b (o adiantado vai atrás do que chegou depois)" 'grep -q "^OK1" "$RUN/sched.out"'
ck "juiz frio: carência pela idade real (atraso não é idade)"    'grep -q "^OK2" "$RUN/sched.out"'
ck "promoção de famintos segue o nome"                         'grep -q "^OK3" "$RUN/sched.out"'
ck "atraso inválido = sem atraso"                              'grep -q "^OK4" "$RUN/sched.out"'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
