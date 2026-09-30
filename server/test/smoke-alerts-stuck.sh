#!/bin/bash
# smoke-alerts-stuck.sh — o alerta de JOB PARADO na fila (lib/alerts.sh, condição queue_stuck).
# Incidente de 30/09/2026: 10 submissões de uma lista ficaram mais de 24 h na fila com os três juízes
# online (MEMLIMITMB=262144 que nenhum juiz comportava) e o mojinho não disse nada — as condições antigas
# só olhavam "sem juiz", "fila grande" e "daemon caído". Afirma:
#   • job na fila há ALERT_STUCK_AFTER+ com juiz online ⇒ alerta com quantos, contest · problema da mais
#     antiga, há quanto tempo e o MOTIVO provável (aqui: a memória, com o teto do maior juiz);
#   • sem juiz online quem fala é o no_judges (o queue_stuck fica quieto); job novo não conta;
#   • enquanto segue parado, não repete antes do ALERT_STUCK_COOLDOWN; destravou ⇒ "voltou a andar";
#   • o motivo reconhece pool offline; job sem sidecar .cmeta usa o enqueued_at do JSON.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
RUN="$(mktemp -d)"; trap 'rm -rf "$RUN"' EXIT
export RUNDIR="$RUN" REGISTRYDIR="$RUN/registry" QUEUEDIR="$RUN/queue" SPOOLDIR="$RUN/spool/submissions" \
       ALERT_EVAL_THROTTLE=0 CONTESTSDIR="$RUN/contests"
mkdir -p "$REGISTRYDIR" "$QUEUEDIR/080-lista-publica" "$SPOOLDIR" "$CONTESTSDIR"
source "$ROOT/api/v1/lib/common.sh" 2>/dev/null
source "$ROOT/api/v1/lib/alerts.sh"
set +o noglob   # o common.sh liga o noglob da API; os globs do teste precisam dele desligado
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:0:300}"; ((fail++)); fi; }
now=$EPOCHSECONDS
judge(){ # <host> <last_seen>
  jq -cn --arg h "$1" --argjson ls "$2" '{host:$h, last_seen:$ls, total_slots:16, slot_cpus:1, mem_kb:67108864, langs:["c","py3"]}' > "$REGISTRYDIR/$1.json"; }
job(){ # <id> <prob> <enq> <memmb> [hosts] [sem-cmeta]
  local f="$QUEUEDIR/080-lista-publica/$((now))_$1.json"
  jq -cn --arg id "$1" --arg p "$2" --argjson e "$3" '{id:$id, contest:"lista-x", problem_id:$p, login:"aluno", lang:"c", enqueued_at:$e}' > "$f"
  # v2 prob need lang hosts k numa par m memmb enq decl (juntados por \x01 — nada de \001 colado a dígito no printf)
  local IFS=$'\x01'; [[ -n "${6:-}" ]] || printf '%s' "v2${IFS}$2${IFS}${IFS}c${IFS}${5:-}${IFS}1${IFS}n${IFS}y${IFS}${IFS}$4${IFS}$3${IFS}" > "$f.cmeta"; }
reset(){ rm -rf "$QUEUEDIR"/*/* "$RUN/alerts"; mkdir -p "$QUEUEDIR/080-lista-publica"; }
stuck_msg(){ cat "$RUN"/alerts/outbox/*-queue_stuck-*.txt 2>/dev/null; }

echo "== job preso por memória, juiz online =="
judge h1 "$now"; reset
job j1 'o#huge' $((now - 2000)) 262144; job j2 'o#plain' $((now - 30)) 1024
alerts_evaluate; DBG="$(stuck_msg)"
ck "alerta: 1 parada (a de 30 s não conta), contest · problema, há 33 min" '[[ "$DBG" == *"<b>1</b> submissão(ões) parada(s)"* && "$DBG" == *"<code>lista-x</code> · <code>o#huge</code>"* && "$DBG" == *"há 33 min"* ]]'
ck "motivo provável: a memória pedida e o teto do maior juiz (64 GB − 4 GB − 64 MB)" '[[ "$DBG" == *"MEMLIMITMB=262144 MB"* && "$DBG" == *"~61376 MB"* ]]'
rm -f "$RUN"/alerts/outbox/*; alerts_evaluate; DBG="$(ls "$RUN/alerts/outbox")"
ck "segue parado: não repete antes do cooldown (1 h)" '[[ -z "$(stuck_msg)" ]]'
rm -f "$QUEUEDIR/080-lista-publica/"*_j1.json*; alerts_evaluate; DBG="$(cat "$RUN"/alerts/outbox/* 2>/dev/null)"
ck "destravou: avisa que a fila voltou a andar" '[[ "$DBG" == *"a fila voltou a andar"* ]]'

echo "== sem juiz online: quem fala é o no_judges =="
judge h1 $((now - 3600)); reset
job j1 'o#huge' $((now - 2000)) 262144
alerts_evaluate; DBG="$(ls "$RUN/alerts/outbox")"
ck "queue_stuck quieto sem juiz online" '[[ -z "$(stuck_msg)" ]]'

echo "== motivos e fontes da idade =="
judge h1 "$now"; reset
job j1 'o#p' $((now - 1000)) 1024 'jx,jy'
alerts_evaluate; DBG="$(stuck_msg)"
ck "pool de juízes offline" '[[ "$DBG" == *"o pool de juízes (jx, jy) está offline"* ]]'
reset; job j1 'o#p' $((now - 5000)) 1024 '' sem-cmeta
alerts_evaluate; DBG="$(stuck_msg)"
ck "job sem sidecar: idade pelo enqueued_at do JSON (1h23m)" '[[ "$DBG" == *"há 1h23m"* ]]'

echo; echo "RESULT: $pass passed, $fail failed"; exit $(( fail > 0 ? 1 : 0 ))
