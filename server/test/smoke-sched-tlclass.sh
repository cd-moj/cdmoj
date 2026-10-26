#!/bin/bash
# smoke-sched-tlclass.sh — o TL da CLASSE DE HARDWARE no job (26/10/2026). Os juízes de produção são idênticos
# (mesmo processador, mesmos núcleos e memória) e mesmo assim calibravam TLs diferentes: o veredicto de quem está
# no limite dependia de qual juiz pegava o envio ("assim parece sorte"). Agora:
#   · o register deriva `hwclass` dos specs (arch|cpu|ncpu|memória em blocos de 4 GiB) — idênticos = a mesma;
#   · o tl-report carimba hosts[h].class no store;
#   · o claim (q_claim/q_claim_id; o heartbeat exporta QC_HWCLASS) põe no job `tl_class` = o máx, por linguagem, entre
#     os juízes da classe de quem reivindica, nas duas metades, com o checksum do store;
#   · sem classe, sem store ou sem juiz da classe no store: o job sai como antes;
#   · /problems/calib mostra hosts[].class e classes[]; o bin/tl-class-backfill.sh carimba store antigo;
#   · a cópia _SCHED_TLMAX_DEF do sched-lib é IGUAL à _TL_MAX_DEF do tl-store.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
: "${MOJTOOLS_DIR:=$(cd "$ROOT/../../mojtools" 2>/dev/null && pwd)}"; export MOJTOOLS_DIR
FIX="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" RUNDIR="$RUN" SPOOLDIR="$RUN/spool/submissions" MOJ_PROBLEMS_DIR="$FIX/problems" \
       JUDGES_CONFIG_FILE="$FIX/treino/var/judges-config.json" SESSIONDIR="$FIX/sess" SWEEP_THROTTLE=0 \
       TL_STORE_DIR="$RUN/tl" CALIB_DIR="$RUN/calib"
mkdir -p "$FIX/treino/var" "$FIX/sess" "$RUN/secrets" "$RUN/registry" "$RUN/tl" "$SPOOLDIR" "$MOJ_PROBLEMS_DIR/o"
printf 'CONTEST_ID=treino\n' > "$FIX/treino/conf"
printf 'mojw_smoketest' > "$RUN/secrets/worker.token"
echo '{}' > "$JUDGES_CONFIG_FILE"
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:-${BODY:0:300}}"; ((fail++)); fi; DBG=""; }
J(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD=POST QUERY_STRING="${3:-}" HTTP_AUTHORIZATION="Bearer mojw_smoketest" bash "$ROUTER" <<<"$2" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
source "$ROOT/judge-gw/sched-lib.sh"; sched_init_dirs; mkdir -p "$UPDATESDIR/pending" "$HOLDDIR"
source "$ROOT/api/v1/lib/tl-store.sh"

XEON='Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz'
regj(){ # <host> <cpu> <ncpu> <mem_kb> -> POST /judge/register
  J /judge/register "$(jq -cn --arg h "$1" --arg c "$2" --argjson n "$3" --argjson m "$4" \
    '{host:$h, capability:"pos", arch:"x86_64", cpu:$c, ncpu:$n, mem_kb:$m, gpu:null, problems:{"o#pa":"x"},
      langs:["c","cpp","py"], toolchain:{}, inv_hash:"ih", total_slots:4, partition:"cpus:1", topology:[],
      slot_cpus:1, slots_by_node:{"0":4}, smt:false}')"; }
cls(){ jq -r '.hwclass // "null"' "$REGISTRYDIR/$1.json"; }

echo "== register: a classe sai dos specs; idênticos = a mesma =="
regj judge "$XEON" 28 264119008; regj judge-sp1 "$XEON" 28 264118892
regj goiabada "  Intel(R)  Xeon(R) CPU E5-2680 v4   @ 2.40GHz " 28 264118904
regj outro 'AMD EPYC 7302 16-Core Processor' 32 131000000
regj semcpu '' 28 264118904
DBG="$(cls judge) | $(cls goiabada) | $(cls outro)"
ck "o parque de produção: x86_64|Xeon|28|252 (251,9 GiB → bloco de 4)" '[[ "$(cls judge)" == "x86_64|$XEON|28|252" ]]'
ck "memória uns KB diferente e espaços no nome do cpu: a MESMA classe" '[[ "$(cls judge-sp1)" == "$(cls judge)" && "$(cls goiabada)" == "$(cls judge)" ]]'
ck "outro processador: outra classe"            '[[ "$(cls outro)" == "x86_64|AMD EPYC 7302 16-Core Processor|32|128" ]]'
ck "spec faltando: sem classe"                  '[[ "$(cls semcpu)" == null ]]'

echo "== tl-report: carimba hosts[h].class =="
P="$MOJ_PROBLEMS_DIR/o/pa"; mkdir -p "$P/sols/good" "$P/tests/input"; printf 'CALIBRATIONTL=5\n' > "$P/conf"
printf 'int main(){}\n' > "$P/sols/good/a.c"; printf '1\n' > "$P/tests/input/t1"
( cd "$P" && git init -q && git add -A && git -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm init )
PV="$(cd "$MOJTOOLS_DIR" && bash tl-checksum.sh --all-sols "$P")"
rep(){ J /judge/tl-report "$(jq -cn --arg h "$1" --arg c "$PV" --argjson tl "$2" --argjson tk "$3" '{host:$h, id:"o#pa", checksum:$c, tl:$tl, tl_kattis:$tk}')"; }
rep judge     '{"c":".3","py3":"1.1","default":".3"}' '{"c":"1","default":"1"}'
rep judge-sp1 '{"c":".4","py":"1.0","default":".4"}' '{"c":"1","default":"1"}'
rep outro     '{"c":".9","default":".9"}'            '{"c":"2","default":"2"}'
rep semcpu    '{"c":"5","default":"5"}'              '{}'
S="$(cat "$TL_STORE_DIR/o#pa.json")"
ck "classes no store (o juiz sem classe fica sem o campo)" '[[ "$(jq -r ".hosts.judge.class" <<<"$S")" == "$(cls judge)" && "$(jq -r ".hosts.outro.class" <<<"$S")" == "$(cls outro)" && "$(jq -r ".hosts.semcpu.class // \"-\"" <<<"$S")" == - ]]'
STCKS="$(jq -r .checksum <<<"$S")"

echo "== claim: o job leva o TL da classe de quem reivindica =="
now=$EPOCHSECONDS
enq(){ q_enqueue "$1" lista-publica "$(jq -cn --arg id "$1" --arg p "${2:-o#pa}" --argjson e "$now" \
  '{id:$id, contest:"sp", problem_id:$p, login:"aluno", lang:"c", filename:"a.c", code_b64:"aQ==", priority:"lista-publica", enqueued_at:$e}')"; }
claim(){ QC_HWCLASS="$2" QC_SLOT_CPUS=1 QC_TOTAL_SLOTS=4 QC_MEM_KB=264118904 QC_POLICY=off QC_PARALLEL_MAX=4 \
  q_claim "$1" pos '{"o#pa":1,"o#novo":1}' '["c","cpp","py"]' 1; }
enq j1; OUT="$(claim judge "$(cls judge)")"; TC="$(jq -c .tl_class <<<"$OUT")"; DBG="$OUT"
ck "tl_class: a classe, os juízes dela que reportaram e o checksum do store" '[[ "$(jq -r .class <<<"$TC")" == "$(cls judge)" && "$(jq -c ".hosts | sort" <<<"$TC")" == "[\"judge\",\"judge-sp1\"]" && "$(jq -r .checksum <<<"$TC")" == "$STCKS" ]]'
ck "o MÁX entre os idênticos (c = 0,4), sem o outro processador (0,9) nem o sem classe (5)" '[[ "$(jq -r .tl.c <<<"$TC")" == 0.4 && "$(jq -r .tl.default <<<"$TC")" == 0.4 ]]'
ck "py3 legado funde em py pelo máx (1,1 > 1,0); a metade Kattis junto" '[[ "$(jq -r .tl.py <<<"$TC")" == 1.1 && "$(jq -r ".tl.py3 // \"-\"" <<<"$TC")" == - && "$(jq -r .tl_kattis.c <<<"$TC")" == 1 ]]'
ck "o job no assigned/ carrega o campo (o requeue não perde)" '[[ "$(jq -r .tl_class.tl.c "$(find "$ASSIGNEDDIR/judge" -name "*_j1.json")")" == 0.4 ]]'
enq j2; OUT="$(claim outro "$(cls outro)")"; DBG="$OUT"
ck "o outro processador leva o TL da classe DELE"   '[[ "$(jq -r .tl_class.tl.c <<<"$OUT")" == 0.9 && "$(jq -c .tl_class.hosts <<<"$OUT")" == "[\"outro\"]" ]]'
enq j3; OUT="$(claim semcpu '')"; DBG="$OUT"
ck "juiz sem classe (registro antigo): o job sai como antes" '[[ "$(jq -r ".tl_class // \"-\"" <<<"$OUT")" == - && "$(jq -r .tl_method <<<"$OUT")" == moj ]]'
enq j4 'o#novo'; OUT="$(claim judge "$(cls judge)")"; DBG="$OUT"
ck "problema sem store de TL: sem o campo"          '[[ "$(jq -r ".tl_class // \"-\"" <<<"$OUT")" == - && "$(jq -r .id <<<"$OUT")" == j4 ]]'
enq j5; OUT="$(claim novo 'x86_64|Nenhum|1|4')"; DBG="$OUT"
ck "classe sem nenhum juiz no store: sem o campo"   '[[ "$(jq -r ".tl_class // \"-\"" <<<"$OUT")" == - ]]'
enq j6; f="$(find "$QUEUEDIR" -name '*_j6.json')"
OUT="$(QC_HWCLASS="$(cls judge)" QC_SLOT_CPUS=1 QC_TOTAL_SLOTS=4 QC_MEM_KB=264118904 q_claim_id judge-sp1 j6)"; DBG="$OUT"
ck "q_claim_id (o job segurado) também leva"        '[[ "$(jq -r .tl_class.tl.c <<<"$OUT")" == 0.4 ]]'

echo "== heartbeat: exporta a classe do registro p/ o claim =="
rm -rf "$ASSIGNEDDIR"; sched_init_dirs; enq j7
J /judge/heartbeat '{"host":"judge-sp1","state":"free","free_slots":1,"total_slots":4,"inv_hash":"ih","status":"ok","slot_cpus":1,"max_free_group":1,"cfg_hash":""}' 'host=judge-sp1'
DBG="$BODY"
ck "o lote do beat traz o tl_class da classe do juiz" '[[ "$(jq -r ".assigned[0].id" <<<"$BODY")" == j7 && "$(jq -r ".assigned[0].tl_class.tl.c" <<<"$BODY")" == 0.4 ]]'

echo "== /problems/calib: hosts[].class e classes[] =="
fx_user "$FIX/treino" autor s "Autor"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino autor Autor "$now" > "$FIX/sess/aut"
echo '{"o":{"members":["autor"],"admins":[],"public_allowed":true,"title":"O"}}' > "$FIX/treino/var/orgs.json"
printf '{"owner":"autor","public":false,"display_title":"PA"}\n' > "$P/.moj-meta.json"
OUT="$(PATH_INFO=/problems/calib REQUEST_METHOD=GET QUERY_STRING="id=o%23pa" HTTP_AUTHORIZATION="Bearer aut" bash "$ROUTER" 2>/dev/null)"
BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"
ck "hosts[].class"                              '[[ "$(jq -r ".hosts[] | select(.host == \"judge\") | .class" <<<"$BODY")" == "$(cls judge)" ]]'
ck "classes[]: o máx por classe, com os juízes"  '[[ "$(jq -r ".classes[] | select(.class == \"$(cls judge)\") | .tl.c" <<<"$BODY")" == 0.4 && "$(jq -r ".classes | length" <<<"$BODY")" == 2 ]]'
printf 'CALIBRATIONTL=5\nTLMOD[c.sum]=1\n' > "$P/conf"
OUT="$(PATH_INFO=/problems/calib REQUEST_METHOD=GET QUERY_STRING="id=o%23pa" HTTP_AUTHORIZATION="Bearer aut" bash "$ROUTER" 2>/dev/null)"
BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"
ck "classes[].effective = o que o juiz cobra (TLMOD por cima: 0,4 + 1)" '[[ "$(jq -r ".classes[] | select(.class == \"$(cls judge)\") | [.tl.c, .effective.c] | join(\" \")" <<<"$BODY")" == "0.4 1.4" ]]'
printf 'CALIBRATIONTL=5\n' > "$P/conf"

echo "== bin/tl-class-backfill.sh: o store antigo (sem class) ganha a classe do registro =="
jq -c '.hosts |= map_values(del(.class))' "$TL_STORE_DIR/o#pa.json" > "$RUN/x" && mv "$RUN/x" "$TL_STORE_DIR/o#pa.json"
out="$(bash "$ROOT/bin/tl-class-backfill.sh" 2>/dev/null)"; DBG="$out"
ck "dry-run lista e não grava"                   '[[ "$(grep -c "^o#pa" <<<"$out")" == 3 && "$(jq -r ".hosts.judge.class // \"-\"" "$TL_STORE_DIR/o#pa.json")" == - ]]'
bash "$ROOT/bin/tl-class-backfill.sh" --apply >/dev/null 2>&1
ck "--apply carimba; o juiz sem classe segue sem" '[[ "$(jq -r ".hosts.judge.class" "$TL_STORE_DIR/o#pa.json")" == "$(cls judge)" && "$(jq -r ".hosts.semcpu.class // \"-\"" "$TL_STORE_DIR/o#pa.json")" == - ]]'
ck "2ª rodada: nada a fazer"                     '[[ -z "$(bash "$ROOT/bin/tl-class-backfill.sh" 2>/dev/null)" ]]'

echo "== a cópia da regra do máx no sched-lib é LITERAL =="
DBG="$(diff <(printf '%s' "$_SCHED_TLMAX_DEF") <(printf '%s' "$_TL_MAX_DEF"))"
ck "_SCHED_TLMAX_DEF == _TL_MAX_DEF"            '[[ -n "$_SCHED_TLMAX_DEF" && "$_SCHED_TLMAX_DEF" == "$_TL_MAX_DEF" ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
