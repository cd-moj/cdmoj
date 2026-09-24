#!/bin/bash
# smoke-sched-width.sh — o ESCALONADOR POR LARGURA (CPUNEEDED / SAMENUMA / testes em paralelo, 24/09/2026).
#
# Os juízes oficiais são slots de 1 CPU. Um job de CPUNEEDED=k ocupa k slots (k_slots = ceil(k/slot_cpus))
# do MESMO juiz; SAMENUMA=y exige que caibam num nó; a memória por slot também limita. O claim é por
# LARGURA (backfill: job estreito passa na frente), o HOLD segura um juiz p/ o largo não morrer de fome,
# o DECLINE devolve o que o agente não conseguiu alocar, o job impossível vira Judge Error, e o par_max
# (testes em paralelo) só cresce com política auto, fila vazia e nada pulado por porta de tempo.
# Tudo sobre a lib (sourced) + o handler /judge/heartbeat pelo router. Juiz LEGADO (sem slot_cpus) no fim.
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
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:0:240}"; ((fail++)); fi; }
source "$ROOT/judge-gw/sched-lib.sh"; sched_init_dirs; mkdir -p "$UPDATESDIR/pending" "$HOLDDIR"

# pacotes: só o conf importa (o servidor lê por regex)
mkp(){ mkdir -p "$MOJ_PROBLEMS_DIR/o/$1"; printf '%s\n' "${2:-}" > "$MOJ_PROBLEMS_DIR/o/$1/conf"; }
mkp plain ''; mkp wide 'CPUNEEDED=4'; mkp numa4 $'CPUNEEDED=4\nSAMENUMA=y'; mkp mem 'MEMLIMITMB=4000'
mkp par $'ALLOWPARALLELTEST=y\nMAXPARALLELTESTS=2'; mkp nopar 'ALLOWPARALLELTEST=n'; mkp big 'CPUNEEDED=40'
mkp wide2 'CPUNEEDED=2'; mkp bad "CPUNEEDED='abc'"
# o juiz do teste tem TODOS os pacotes em cache ("quente": a porta COLD_GRACE é de outro teste)
PROBS='{"o#plain":1,"o#wide":1,"o#numa4":1,"o#mem":1,"o#par":1,"o#nopar":1,"o#big":1,"o#wide2":1,"o#bad":1}'
now=$EPOCHSECONDS
enq(){ # <id> <prob> [prio] [lang] [enq_epoch] -> enfileira
  q_enqueue "$1" "${3:-lista-publica}" "$(jq -cn --arg id "$1" --arg p "o#$2" --arg pr "${3:-lista-publica}" --arg l "${4:-c}" --argjson e "${5:-$now}" \
    '{id:$id, contest:"sp", problem_id:$p, login:"aluno", lang:$l, filename:"a.c", code_b64:"aQ==", priority:$pr, enqueued_at:$e}')"; }
reg(){ # <host> <total> <free> [slot_cpus] [maxnode] [mfg] [status] [age]
  jq -cn --arg h "$1" --argjson t "$2" --argjson f "$3" --arg sc "${4-1}" --argjson mn "${5:-$2}" --argjson mfg "${6:-$3}" \
     --arg st "${7:-ok}" --argjson ls "$((now - ${8:-0}))" \
     --argjson pr "$PROBS" \
     '{host:$h, state:"free", last_seen:$ls, capability:"pos", problems:$pr, langs:["c","cpp"], inv_hash:"ih",
       total_slots:$t, free_slots:$f, mem_kb:67108864, status:$st}
      + (if $sc == "" then {} else {slot_cpus:($sc|tonumber), slots_by_node:{"0":$mn, "1":($t-$mn)}, max_free_group:$mfg} end)' \
    > "$REGISTRYDIR/$1.json"; }
qfiles(){ find "$QUEUEDIR" -mindepth 2 -name '*.json' | wc -l; }
clearq(){ rm -rf "$QUEUEDIR" "$ASSIGNEDDIR" "$HOLDDIR" "$UPDATESDIR"/* "$CMDDIR" "$REGISTRYDIR"/*.json; sched_init_dirs; mkdir -p "$UPDATESDIR/pending" "$HOLDDIR"; rm -f "$QUEUEDIR"/.*-stamp "$HOLDDIR"/.sweep-stamp 2>/dev/null; }
claim(){ # <host> <free> [slot_cpus] [mfg] [total] [policy] [cushion] [share] [pmax] -> linhas de jobs
  QC_SLOT_CPUS="${3:-1}" QC_MAX_FREE_GROUP="${4:-}" QC_TOTAL_SLOTS="${5:-16}" QC_MEM_KB=67108864 \
  QC_POLICY="${6:-off}" QC_CUSHION="${7:-0.25}" QC_SHARE_MAX="${8:-0.5}" QC_PARALLEL_MAX="${9:-4}" \
    q_claim "$1" pos "$PROBS" '["c","cpp"]' "$2"; }

echo "== conf do pacote por regex + cmeta v2 =="
IFS=$'\x01' read -r k nm par m mem < <(sched_pkg_par 'o#numa4')
ck "CPUNEEDED/SAMENUMA lidos"                 '[[ "$k" == 4 && "$nm" == y && "$par" == y && -z "$m" && "$mem" == 0 ]]'
IFS=$'\x01' read -r k nm par m mem < <(sched_pkg_par 'o#par')
ck "ALLOWPARALLELTEST/MAXPARALLELTESTS"        '[[ "$k" == 1 && "$par" == y && "$m" == 2 ]]'
IFS=$'\x01' read -r k nm par m mem < <(sched_pkg_par 'o/mem')
ck "id com / e MEMLIMITMB"                     '[[ "$k" == 1 && "$mem" == 4000 ]]'
IFS=$'\x01' read -r k nm par m mem < <(sched_pkg_par 'o#bad')
ck "valor inválido cai no default"             '[[ "$k" == 1 ]]'
IFS=$'\x01' read -r k nm par m mem < <(sched_pkg_par 'x#naoexiste')
ck "pacote inexistente = defaults"             '[[ "$k" == 1 && "$nm" == n && "$par" == y ]]'
clearq; enq j1 wide
f="$(find "$QUEUEDIR" -name '*_j1.json')"
printf 'o#wide\x01\x01c\x01' > "$f.cmeta"   # sidecar v1 (antigo)
claim h1 2 >/dev/null
DBG="$(cat "$f.cmeta" | tr '\001' '|')"
ck "cmeta v1 é reescrito como v2 com k/enq"    '[[ "$(cut -d$'"'"'\x01'"'"' -f1,6,7 "$f.cmeta")" == $'"'"'v2\x014\x01n'"'"' ]]'

echo "== claim por largura: k_slots ≤ livres; backfill; contagem em slots =="
clearq; enq j1 wide; enq j2 plain; enq j3 plain
out="$(claim h1 2)"; DBG="$out"
ck "2 livres: o largo (4) é PULADO, os dois de 1 passam (backfill)" '[[ "$(jq -r .id <<<"$out" | tr "\n" " ")" == "j2 j3 " ]]'
ck "cada job leva slots=1 e test_cpus=1"       '[[ "$(jq -r .slots <<<"$out" | sort -u)" == 1 && "$(jq -r .test_cpus <<<"$out" | sort -u)" == 1 ]]'
out="$(claim h1 5)"; DBG="$out"
ck "5 livres: o largo sai com slots=4, test_cpus=4, par_max=1" '[[ "$(jq -r ".id,.slots,.test_cpus,.par_max" <<<"$out" | tr "\n" " ")" == "j1 4 4 1 " ]]'
clearq; enq j1 wide; enq j2 wide; enq j3 plain
out="$(claim h1 5)"; DBG="$out"
ck "5 livres, dois largos: 4+1 (o 2º largo não cabe, o de 1 passa)" '[[ "$(jq -r .id <<<"$out" | tr "\n" " ")" == "j1 j3 " && "$(jq -s "map(.slots)|add" <<<"$out")" == 5 ]]'
ck "o job assigned/ carrega os campos"          '[[ "$(jq -r .slots "$(find "$ASSIGNEDDIR/h1" -name "*_j1.json")")" == 4 ]]'
clearq; enq j1 wide2
out="$(claim h1 1 2)"; DBG="$out"
ck "slot_cpus=2: k=2 vira 1 slot"              '[[ "$(jq -r ".slots,.test_cpus" <<<"$out" | tr "\n" " ")" == "1 2 " ]]'

echo "== SAMENUMA × max_free_group; memória por slot =="
clearq; enq j1 numa4; enq j2 wide
out="$(claim h1 8 1 3)"; DBG="$out"
ck "numa4 com maior grupo livre 3: pula; wide (sem numa) passa" '[[ "$(jq -r .id <<<"$out")" == j2 ]]'
out="$(claim h1 4 1 4)"; DBG="$out"
ck "maior grupo 4: numa4 passa com same_numa=true" '[[ "$(jq -r ".id,.same_numa" <<<"$out" | tr "\n" " ")" == "j1 true " ]]'
clearq; enq j1 mem; enq j2 plain
out="$(QC_SLOT_CPUS=1 QC_TOTAL_SLOTS=27 QC_MEM_KB=$((32*1024*1024)) QC_POLICY=off q_claim h1 pos "$PROBS" '[]' 3)"; DBG="$out"
ck "MEMLIMITMB=4000 num slot de ~1 GB (32 GB/27): pula; plain passa" '[[ "$(jq -r .id <<<"$out")" == j2 ]]'
out="$(QC_SLOT_CPUS=1 QC_TOTAL_SLOTS=4 QC_MEM_KB=$((32*1024*1024)) QC_POLICY=off q_claim h1 pos "$PROBS" '[]' 3)"; DBG="$out"
ck "4 slots de 7 GB: cabe"                     '[[ "$(jq -r .id <<<"$out")" == j1 ]]'

echo "== par_max: só política auto + fila vazia + nada pulado por tempo =="
clearq; enq j1 par
out="$(claim h1 8 1 8 8 off)"; DBG="$out"
ck "política off: par_max 1, par_cap = MAXPARALLELTESTS (2)" '[[ "$(jq -r ".par_max,.par_cap,.slots" <<<"$out" | tr "\n" " ")" == "1 2 1 " ]]'
clearq; enq j1 par
out="$(claim h1 8 1 8 8 auto)"; DBG="$out"
ck "auto, 8 livres de 8, colchão 2: par_max 2 (MAXPARALLELTESTS), slots 2" '[[ "$(jq -r ".par_max,.slots" <<<"$out" | tr "\n" " ")" == "2 2 " ]]'
clearq; enq j1 plain
out="$(claim h1 8 1 8 8 auto)"; DBG="$out"
ck "sem MAXPARALLELTESTS: até parallel_max do juiz (4), share 0.5×8=4 slots" '[[ "$(jq -r ".par_max,.slots,.par_cap" <<<"$out" | tr "\n" " ")" == "4 4 4 " ]]'
clearq; enq j1 plain
out="$(claim h1 8 1 8 8 auto 0.25 0.5 2)"; DBG="$out"
ck "parallel_max do juiz = 2 é teto"           '[[ "$(jq -r .par_max <<<"$out")" == 2 ]]'
clearq; enq j1 plain
out="$(claim h1 8 1 8 8 auto 0.25 0.25)"; DBG="$out"
ck "share_max 0.25×8 = 2 slots por job"        '[[ "$(jq -r .par_max <<<"$out")" == 2 ]]'
clearq; enq j1 plain; enq j2 plain
out="$(claim h1 8 1 8 8 auto 0.5)"; DBG="$out"
ck "2 jobs, colchão 4: sobra 2 repartida em rodízio (2 e 2)" '[[ "$(jq -r .par_max <<<"$out" | tr "\n" " ")" == "2 2 " && "$(jq -s "map(.slots)|add" <<<"$out")" == 4 ]]'
clearq; enq j1 nopar
out="$(claim h1 8 1 8 8 auto)"; DBG="$out"
ck "ALLOWPARALLELTEST=n: par_max 1"            '[[ "$(jq -r .par_max <<<"$out")" == 1 ]]'
clearq; enq j1 plain; enq j2 plain; enq j3 plain
out="$(claim h1 2 1 8 8 auto)"; DBG="$out"
ck "fila NÃO esvaziou (2 livres, 3 jobs): par_max 1" '[[ "$(jq -r .par_max <<<"$out" | sort -u)" == 1 ]]'
clearq; enq j1 plain; enq j2 plain "" py "$now"   # py: juiz sem py ⇒ pulado por LANG_GRACE
out="$(claim h1 8 1 8 8 auto)"; DBG="$out"
ck "job pulado por porta de TEMPO (lang): par_max 1" '[[ "$(jq -r .id <<<"$out")" == j1 && "$(jq -r .par_max <<<"$out")" == 1 ]]'
clearq; enq j1 plain; enq j2 wide
out="$(claim h1 3 1 8 8 auto)"; DBG="$out"
ck "job pulado por LARGURA: par_max 1"         '[[ "$(jq -r .par_max <<<"$out")" == 1 ]]'

echo "== decline: epoch novo, backoff do host, Judge Error na 3ª =="
clearq; enq j1 wide; sleep 1
claim h1 4 >/dev/null
r="$(sched_decline_job h1 j1 "corrida")"; DBG="$r"
ck "recusa: requeued"                          '[[ "$r" == requeued ]]'
nf="$(find "$QUEUEDIR" -name '*_j1.json')"
ck "voltou à fila com epoch NOVO e declined.h1" '[[ -n "$nf" && "${nf##*/}" != "${now}_j1.json" && "$(jq -r ".declined.h1" "$nf")" =~ ^[0-9]+$ ]]'
ck "campos de largura saíram do job"           '[[ "$(jq -r ".slots // \"none\"" "$nf")" == none ]]'
out="$(claim h1 8)"; DBG="$out"
ck "h1 pula o job por DECLINE_BACKOFF"         '[[ -z "$out" ]]'
out="$(claim h2 8)"; DBG="$out"
ck "h2 pega normalmente"                       '[[ "$(jq -r .id <<<"$out")" == j1 ]]'
sched_decline_job h2 j1 x >/dev/null; claim h3 8 >/dev/null
r="$(sched_decline_job h3 j1 "corrida")"; DBG="$r"
ck "3ª recusa: judge_error"                    '[[ "$r" == judge_error ]]'
sp="$(find "$SPOOLDIR" -name 'sp:*:j1:scheduler:result:*' | head -1)"; DBG="$sp"
ck "result no spool com host scheduler, Judge Error" '[[ -n "$sp" && "$(jq -r ".verdict_canon" "$sp")" == "Judge Error" && "$(jq -r .verdict "$sp")" == *"recusado por 3"* ]]'
ck "…e o job saiu de assigned/ e da fila"      '[[ -z "$(find "$QUEUEDIR" "$ASSIGNEDDIR" -name "*_j1.json")" ]]'
ck "decline de job desconhecido: notfound"     '[[ "$(sched_decline_job h1 nada x)" == notfound ]]'
r="$(cal_request o 'o#wide' autor)"; QC_SLOT_CPUS=1 QC_FREE=8 upd_claim h1 >/dev/null
ck "decline de calibração: volta p/ pending"   '[[ "$(sched_decline_update h1 "$r")" == requeued && -f "$UPDATESDIR/pending/$r.json" && "$(jq -r ".slots // \"none\"" "$UPDATESDIR/pending/$r.json")" == none ]]'
cid="$(cmd_request h1 calibrate autor 'o#wide')"; c="$(QC_SLOT_CPUS=1 QC_FREE=8 cmd_claim h1)"
ck "decline de comando: reenfileirado com cmdid novo" '[[ "$(sched_decline_command h1 "$c")" == requeued && "$(cmd_pending_count h1)" == 1 && "$(cmd_find_calibrate h1 "o#wide")" != "$cid" ]]'

echo "== calibração larga: upd_claim/cmd_claim só entregam se cabe =="
clearq; rm -rf "$CMDDIR"; r="$(cal_request o 'o#wide' autor)"
ck "2 livres: calibração de k=4 fica pendente" '[[ -z "$(QC_SLOT_CPUS=1 QC_FREE=2 upd_claim h1)" && -f "$UPDATESDIR/pending/$r.json" ]]'
u="$(QC_SLOT_CPUS=1 QC_FREE=4 upd_claim h1)"; DBG="$u"
ck "4 livres: sai com test_cpus=4 slots=4"     '[[ "$(jq -r ".test_cpus,.slots,.same_numa" <<<"$u" | tr "\n" " ")" == "4 4 false " ]]'
upd_done h1 "$r"; r="$(cal_request o 'o#numa4' autor)"
ck "numa4 com grupo 3: pendente"               '[[ -z "$(QC_SLOT_CPUS=1 QC_FREE=8 QC_MAX_FREE_GROUP=3 upd_claim h1)" ]]'
u="$(QC_SLOT_CPUS=1 QC_FREE=8 QC_MAX_FREE_GROUP=4 upd_claim h1)"
ck "numa4 com grupo 4: sai com same_numa=true" '[[ "$(jq -r .same_numa <<<"$u")" == true ]]'
upd_done h1 "$r"
cmd_request h1 calibrate autor 'o#wide' >/dev/null; cmd_request h1 clearcache autor >/dev/null
c="$(QC_SLOT_CPUS=1 QC_FREE=1 cmd_claim h1)"; DBG="$c"
ck "comando calibrate largo não cabe: o clearcache atrás dele sai" '[[ "$(jq -r .action <<<"$c")" == clearcache && "$(cmd_pending_count h1)" == 1 ]]'
c="$(QC_SLOT_CPUS=1 QC_FREE=4 cmd_claim h1)"; DBG="$c"
ck "com 4 livres o calibrate sai com slots=4"  '[[ "$(jq -r ".action,.slots" <<<"$c" | tr "\n" " ")" == "calibrate 4 " ]]'
rm -rf "$CMDDIR" "$UPDATESDIR/inprogress"; mkdir -p "$UPDATESDIR/inprogress"

echo "== HOLD: juiz segurado p/ o largo faminto =="
clearq; rm -f "$REGISTRYDIR"/*.json
reg h1 8 1 1 8 1; reg h2 8 2 1 8 2   # dois juízes cheios (1 e 2 livres de 8)
enq j1 wide "" c "$((now-30))"; enq j2 plain
hold_sweep
DBG="$(ls "$HOLDDIR"; cat "$HOLDDIR"/*.json 2>/dev/null)"
ck "hold criado no juiz com MAIS livres (h2)"   '[[ -f "$HOLDDIR/h2.json" && ! -f "$HOLDDIR/h1.json" && "$(jq -r ".job,.k_slots" "$HOLDDIR/h2.json" | tr "\n" " ")" == "j1 4 " ]]'
ck "hold_get devolve o hold vivo"              '[[ "$(hold_get h2 | jq -r .job)" == j1 ]]'
rm -f "$HOLDDIR/.sweep-stamp"; reg h3 8 8 1 8 8; hold_sweep
ck "juiz que CABE o job agora: nenhum hold novo" '[[ "$(ls "$HOLDDIR"/*.json | wc -l)" == 1 ]]'
rm -f "$REGISTRYDIR/h3.json" "$HOLDDIR/.sweep-stamp"; enq j3 wide "" c "$((now-30))"; hold_sweep
ck "1 hold por juiz: o 2º largo pega o h1"     '[[ -f "$HOLDDIR/h1.json" && "$(jq -r .job "$HOLDDIR/h1.json")" == j3 ]]'
clearq; enq j1 wide "" c "$((now-30))"; enq j4 wide "" c "$((now-30))"; enq j9 plain prova; reg h1 8 1 1 8 1; reg h2 8 2 1 8 2
rm -f "$HOLDDIR/.sweep-stamp"; hold_sweep
ck "banda prova não vazia: no máx 1 hold"       '[[ "$(ls "$HOLDDIR"/*.json | wc -l)" == 1 ]]'
clearq; enq j1 wide "" c "$((now-5))"; reg h1 8 1 1 8 1; rm -f "$HOLDDIR/.sweep-stamp"; hold_sweep
ck "pendente há < HOLD_AFTER: sem hold"         '[[ -z "$(ls "$HOLDDIR"/*.json 2>/dev/null)" ]]'
clearq; enq j1 numa4 "" c "$((now-30))"; reg h1 6 2 1 3 2; rm -f "$HOLDDIR/.sweep-stamp"; hold_sweep; DBG="$(ls "$HOLDDIR")"
ck "SAMENUMA sem nó com 4 slots (3+3): juiz não é candidato" '[[ -z "$(ls "$HOLDDIR"/*.json 2>/dev/null)" ]]'
clearq; enq j1 wide "" c "$((now-30))"; reg h1 8 2 "" 8 2; rm -f "$HOLDDIR/.sweep-stamp"; hold_sweep; DBG="$(ls "$HOLDDIR"; cat "$REGISTRYDIR"/*.json)"
ck "juiz LEGADO (sem slot_cpus) nunca é segurado" '[[ -z "$(ls "$HOLDDIR"/*.json 2>/dev/null)" ]]'
clearq; enq j1 wide "" c "$((now-30))"; reg h1 8 2 1 8 2 draining; rm -f "$HOLDDIR/.sweep-stamp"; hold_sweep
ck "juiz drenando não é segurado"               '[[ -z "$(ls "$HOLDDIR"/*.json 2>/dev/null)" ]]'
# liberação: job reivindicado em outro lugar / TTL
clearq; enq j1 wide "" c "$((now-30))"; reg h1 8 2 1 8 2; rm -f "$HOLDDIR/.sweep-stamp"; hold_sweep
claim h9 8 >/dev/null
ck "job reivindicado por outro juiz: hold_get poda" '[[ -z "$(hold_get h1)" && ! -f "$HOLDDIR/h1.json" ]]'
clearq; enq j1 wide "" c "$((now-30))"; reg h1 8 2 1 8 2; rm -f "$HOLDDIR/.sweep-stamp"; hold_sweep
jq -c '.since = 1' "$HOLDDIR/h1.json" > "$HOLDDIR/t" && mv "$HOLDDIR/t" "$HOLDDIR/h1.json"
ck "hold vencido (TTL): podado"                 '[[ -z "$(hold_get h1)" ]]'
# entrega pelo heartbeat: segurado ⇒ nada; cabe ⇒ recebe o job segurado
clearq; enq j1 wide "" c "$((now-30))"; enq j2 plain; reg h1 8 2 1 8 2; rm -f "$HOLDDIR/.sweep-stamp"; hold_sweep
r="$(cal_request o 'o#plain' autor)"
hb(){ # <host> <free> [slot_cpus] [mfg] [cfg_hash]
  OUT="$(PATH_INFO=/judge/heartbeat REQUEST_METHOD=POST QUERY_STRING="host=$1" HTTP_AUTHORIZATION="Bearer mojw_smoketest" bash "$ROUTER" \
    <<<"{\"host\":\"$1\",\"state\":\"free\",\"free_slots\":$2,\"total_slots\":8,\"inv_hash\":\"ih\",\"status\":\"ok\",\"slot_cpus\":${3:-1},\"max_free_group\":${4:-$2},\"cfg_hash\":\"${5:-}\"}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
hb h1 2; DBG="$BODY"
ck "heartbeat SEGURADO (2 livres): holding, sem job, sem update" '[[ "$(jq -r ".holding,.assigned,.update" <<<"$BODY" | tr "\n" " ")" == "true null null " ]]'
ck "…e a calibração ficou pendente"            '[[ -f "$UPDATESDIR/pending/$r.json" ]]'
hb h1 5; DBG="$BODY"
ck "5 livres: recebe o job SEGURADO (4 slots) + o de 1 no mesmo lote" '[[ "$(jq -r ".assigned[].id" <<<"$BODY" | tr "\n" " ")" == "j1 j2 " && "$(jq -r "has(\"holding\")" <<<"$BODY")" == false ]]'
ck "registry: free_slots = 5 − 4 − 1 = 0, slot_cpus e max_free_group gravados" '[[ "$(jq -r ".free_slots,.slot_cpus,.max_free_group" "$REGISTRYDIR/h1.json" | tr "\n" " ")" == "0 1 5 " ]]'
ck "hold sumiu"                                 '[[ ! -f "$HOLDDIR/h1.json" ]]'

echo "== infactível: sem juiz vivo com k CPUs ⇒ Judge Error pelo spool =="
clearq; rm -f "$REGISTRYDIR"/*.json "$SPOOLDIR"/sp:* 2>/dev/null; reg h1 8 8 1 8 8
enq j1 big "" c "$((now-200))"; enq j2 wide "" c "$((now-200))"
rm -f "$QUEUEDIR/.infeasible-stamp"; infeasible_sweep
sp="$(find "$SPOOLDIR" -name 'sp:*:j1:scheduler:result:*' | head -1)"; DBG="$sp"
ck "k=40 com juiz de 8: Judge Error no spool, job fora da fila" '[[ -n "$sp" && "$(jq -r .verdict "$sp")" == *"nenhum juiz com 40 CPU(s)"* && -z "$(find "$QUEUEDIR" -name "*_j1.json")" ]]'
ck "k=4 cabe no juiz de 8: continua na fila"   '[[ -n "$(find "$QUEUEDIR" -name "*_j2.json")" ]]'
clearq; rm -f "$REGISTRYDIR"/*.json; enq j1 big "" c "$((now-200))"; rm -f "$QUEUEDIR/.infeasible-stamp"; infeasible_sweep
ck "NENHUM juiz vivo: espera (não é infactível)" '[[ -n "$(find "$QUEUEDIR" -name "*_j1.json")" ]]'
clearq; rm -f "$SPOOLDIR"/sp:*; reg h1 6 6 1 3 6; enq j1 numa4 "" c "$((now-200))"; rm -f "$QUEUEDIR/.infeasible-stamp"; infeasible_sweep
sp="$(find "$SPOOLDIR" -name 'sp:*:j1:scheduler:result:*' | head -1)"; DBG="sp=$sp"
ck "SAMENUMA=y com maior nó 3: Judge Error cita o nó" '[[ -n "$sp" && "$(jq -r .verdict "$sp")" == *"num nó NUMA"* ]]'
clearq; rm -f "$SPOOLDIR"/sp:*; reg h1 8 8 "" 8 8; enq j1 wide2 "" c "$((now-200))"; rm -f "$QUEUEDIR/.infeasible-stamp"; infeasible_sweep
sp="$(find "$SPOOLDIR" -name 'sp:*:j1:scheduler:result:*' | head -1)"; DBG="sp=$sp fila=$(find "$QUEUEDIR" -name '*.json') rows=$(_reg_rows | tr '\001' '|')"
ck "só juiz LEGADO vivo (não serve k>1): Judge Error" '[[ -n "$sp" ]]'
rm -f "$SPOOLDIR"/sp:* 2>/dev/null

echo "== juiz LEGADO (heartbeat sem slot_cpus): só k=1, sem campos novos =="
clearq; rm -f "$REGISTRYDIR"/*.json; reg h1 8 8 ""
enq j1 wide; enq j2 plain
out="$(QC_SLOT_CPUS= q_claim h1 pos "$PROBS" '[]' 8)"; DBG="$out"
ck "largo pulado, plain sai SEM test_cpus/slots" '[[ "$(jq -r .id <<<"$out")" == j2 && "$(jq -r "has(\"test_cpus\"),has(\"slots\")" <<<"$out" | tr "\n" " ")" == "false false " ]]'
OUT="$(PATH_INFO=/judge/heartbeat REQUEST_METHOD=POST QUERY_STRING="host=h1" HTTP_AUTHORIZATION="Bearer mojw_smoketest" bash "$ROUTER" \
    <<<'{"host":"h1","state":"free","free_slots":8,"total_slots":8,"inv_hash":"ih","status":"ok"}' 2>/dev/null)"
BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; DBG="$BODY $(cat "$REGISTRYDIR/h1.json")"
ck "heartbeat legado: lote sem campos de largura; registry sem slot_cpus" '[[ "$(jq -r ".assigned|length" <<<"$BODY")" == 0 && "$(jq -r ".slot_cpus // \"none\"" "$REGISTRYDIR/h1.json")" == none ]]'

echo "== /judge/decline pelo router =="
clearq; reg h1 8 8 1 8 8; enq j5 plain; claim h1 8 >/dev/null
OUT="$(PATH_INFO=/judge/decline REQUEST_METHOD=POST QUERY_STRING="host=h1" HTTP_AUTHORIZATION="Bearer mojw_smoketest" bash "$ROUTER" \
    <<<'{"host":"h1","reason":"sem 1 cpu livre","id":"j5"}' 2>/dev/null)"
BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; DBG="$BODY"
ck "decline via API: requeued"                  '[[ "$(jq -r .result <<<"$BODY")" == requeued && -n "$(find "$QUEUEDIR" -name "*_j5.json")" ]]'
OUT="$(PATH_INFO=/judge/decline REQUEST_METHOD=POST QUERY_STRING="host=h1" HTTP_AUTHORIZATION="Bearer mojw_smoketest" bash "$ROUTER" <<<'{"host":"h1","reason":"x"}' 2>/dev/null)"
ck "sem id/reqid/command: 400"                  'grep -q "decline_empty" <<<"$OUT"'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
