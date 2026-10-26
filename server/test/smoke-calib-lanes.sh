#!/bin/bash
# smoke-calib-lanes.sh — as RAIAS da calibração no escalonador (26/10/2026; pedido do Ribas: a calibração roda as
# soluções do mesmo tipo em paralelo). O claim da calibração (upd_claim e o comando dirigido, cmd_claim) dá
# G = min(CALIB_PAR_MAX, livres ÷ k_slots, a maior fase: #good ou #pass+slow+wrong) grupos, e 1 quando há job na
# fila ou o juiz é legado; carimba par_max/par_cap = G e slots = G × k_slots — e o heartbeat conta esses slots.
# As soluções são contadas com `find`: a API roda SEM glob, e `sols/good/*` daria o padrão literal ("1 solução") —
# por isso a conta passa também pelo router (/judge/heartbeat).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$RUN"' EXIT
export CONTESTSDIR="$FIX" RUNDIR="$RUN" SPOOLDIR="$RUN/spool/submissions" MOJ_PROBLEMS_DIR="$FIX/problems" \
       JUDGES_CONFIG_FILE="$FIX/treino/var/judges-config.json" SESSIONDIR="$FIX/sess" SWEEP_THROTTLE=0
mkdir -p "$FIX/treino/var" "$FIX/sess" "$RUN/secrets" "$RUN/registry" "$SPOOLDIR" "$MOJ_PROBLEMS_DIR/o"
printf 'CONTEST_ID=treino\n' > "$FIX/treino/conf"
printf 'mojw_smoketest' > "$RUN/secrets/worker.token"
echo '{}' > "$JUDGES_CONFIG_FILE"
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:0:300}"; ((fail++)); fi; DBG=""; }
source "$ROOT/judge-gw/sched-lib.sh"; sched_init_dirs; mkdir -p "$UPDATESDIR/pending" "$HOLDDIR"

mkp(){ # <prob> <conf> <#good> <#pass> <#slow> <#wrong>
  local P="$MOJ_PROBLEMS_DIR/o/$1" i d n
  mkdir -p "$P/sols/good" "$P/sols/pass" "$P/sols/slow" "$P/sols/wrong"; printf '%s\n' "$2" > "$P/conf"
  for d in good:$3 pass:$4 slow:$5 wrong:$6; do n="${d#*:}"; for (( i=1; i<=n; i++ )); do : > "$P/sols/${d%%:*}/s$i.c"; done; done
}
mkp muitas '' 3 1 2 2        # 3 good, 5 nas outras
mkp uma '' 1 0 0 0           # 1 good e nada mais
mkp larga 'CPUNEEDED=2' 3 1 2 2
now=$EPOCHSECONDS
clean(){ rm -rf "$UPDATESDIR"/pending/* "$UPDATESDIR"/inprogress/* "$CMDDIR" "$QUEUEDIR" "$ASSIGNEDDIR"; sched_init_dirs; mkdir -p "$UPDATESDIR/pending"; }
uclaim(){ # <prob> <livres> [slot_cpus] [CALIB_PAR_MAX] -> o update reivindicado
  clean; cal_request o "o#$1" autor >/dev/null
  CALIB_PAR_MAX="${4:-4}" QC_SLOT_CPUS="${3-1}" QC_FREE="$2" QC_MAX_FREE_GROUP="$2" upd_claim h1; }
enq(){ q_enqueue j1 lista-publica "$(jq -cn --argjson e "$now" '{id:"j1", contest:"sp", problem_id:"o#uma", login:"aluno", lang:"c", filename:"a.c", code_b64:"aQ==", priority:"lista-publica", enqueued_at:$e}')"; }

echo "== upd_claim: G = min(teto, livres ÷ k_slots, maior fase) =="
OUT="$(uclaim muitas 8)"; DBG="$OUT"
ck "3 good + 5 outras, 8 livres: G = 4 (o teto), slots 4" '[[ "$(jq -c "[.par_max, .par_cap, .slots, .test_cpus]" <<<"$OUT")" == "[4,4,4,1]" ]]'
OUT="$(uclaim muitas 2)"; DBG="$OUT"
ck "2 livres: G = 2"                             '[[ "$(jq -c "[.par_max, .slots]" <<<"$OUT")" == "[2,2]" ]]'
OUT="$(uclaim uma 8)"; DBG="$OUT"
ck "1 good e nada mais: 1 grupo (sem par_max)"   '[[ "$(jq -c "[.par_max, .slots]" <<<"$OUT")" == "[null,1]" ]]'
OUT="$(uclaim muitas 8 1 1)"; DBG="$OUT"
ck "CALIB_PAR_MAX=1 desliga"                     '[[ "$(jq -c "[.par_max, .slots]" <<<"$OUT")" == "[null,1]" ]]'
OUT="$(uclaim larga 8)"; DBG="$OUT"
ck "CPUNEEDED=2 (k_slots 2), 8 livres: G = 4, slots 8" '[[ "$(jq -c "[.par_max, .slots, .test_cpus]" <<<"$OUT")" == "[4,8,2]" ]]'
OUT="$(uclaim larga 5)"; DBG="$OUT"
ck "CPUNEEDED=2, 5 livres: G = 2, slots 4"       '[[ "$(jq -c "[.par_max, .slots]" <<<"$OUT")" == "[2,4]" ]]'
clean; cal_request o "o#muitas" autor >/dev/null; enq
OUT="$(CALIB_PAR_MAX=4 QC_SLOT_CPUS=1 QC_FREE=8 QC_MAX_FREE_GROUP=8 upd_claim h1)"; DBG="$OUT"
ck "job na fila: 1 grupo (a calibração não toma slot de quem espera veredicto)" '[[ "$(jq -c "[.par_max, .slots]" <<<"$OUT")" == "[null,1]" ]]'
OUT="$(uclaim muitas 8 '')"; DBG="$OUT"
ck "juiz legado (sem slot_cpus): sem os campos"  '[[ "$(jq -c "[.par_max, .slots]" <<<"$OUT")" == "[null,null]" ]]'

echo "== cmd_claim (a calibração dirigida): a mesma regra =="
clean; cmd_request h1 calibrate autor "o#muitas" >/dev/null
OUT="$(CALIB_PAR_MAX=4 QC_SLOT_CPUS=1 QC_FREE=8 QC_MAX_FREE_GROUP=8 cmd_claim h1)"; DBG="$OUT"
ck "comando dirigido: G = 4, slots 4"            '[[ "$(jq -c "[.action, .par_max, .slots]" <<<"$OUT")" == "[\"calibrate\",4,4]" ]]'

echo "== pelo router (sem glob): o heartbeat dá G e conta os slots =="
clean; cal_request o "o#muitas" autor >/dev/null
jq -cn --argjson ls "$now" '{host:"h1", state:"free", last_seen:$ls, capability:"pos", problems:{}, langs:["c"], inv_hash:"ih",
  total_slots:8, free_slots:8, mem_kb:67108864, slot_cpus:1, slots_by_node:{"0":8}, max_free_group:8}' > "$REGISTRYDIR/h1.json"
OUT="$(PATH_INFO=/judge/heartbeat REQUEST_METHOD=POST QUERY_STRING="host=h1" HTTP_AUTHORIZATION="Bearer mojw_smoketest" bash "$ROUTER" \
  <<<'{"host":"h1","state":"free","free_slots":8,"total_slots":8,"inv_hash":"ih","status":"ok","slot_cpus":1,"max_free_group":8,"cfg_hash":""}' 2>/dev/null)"
BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; DBG="$BODY"
ck "o update sai com par_max 4 (contou as soluções sem glob)" '[[ "$(jq -c "[.update.par_max, .update.slots]" <<<"$BODY")" == "[4,4]" ]]'
ck "…e o registro conta os 4 slots ocupados (livres 8 → 4)" '[[ "$(jq -r .free_slots "$REGISTRYDIR/h1.json")" == 4 ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
