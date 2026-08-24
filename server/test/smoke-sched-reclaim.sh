#!/bin/bash
# smoke-sched-reclaim.sh — QUEM PERDE O JOB, E QUANDO. Cobre o `q_reconcile` do escalonador.
#
#   bash server/test/smoke-sched-reclaim.sh
#
# POR QUE EXISTE: no ensaio da Maratona (24/08/2026) uma submissão levou 915 s para receber
# veredicto — a correção em si tinha levado 67 s. O job era de um problema de 737 MB / 362
# testes; o `ASSIGN_TTL` era de 120 s e o servidor REVOGAVA a posse no meio do trabalho (o
# agente não tem como dizer "ainda estou nisso": o heartbeat só manda state/free_slots). O job
# voltava p/ a fila, outro juiz pegava do zero, e o trabalho era refeito — visto no `judge` e
# no `judge-sp1` com dois minutos de diferença. Nada disso tinha teste.
#
# O que este arquivo fixa, e que é o contrato do escalonador:
#   1. juiz VIVO com job recente  -> a posse é dele (não devolve);
#   2. juiz VIVO passado do teto  -> devolve (rede de segurança p/ posse perdida em silêncio);
#   3. juiz MORTO                 -> devolve NA HORA, independente da idade do job;
#   4. agente que REINICIA        -> devolve tudo (sched_requeue_host), sem esperar teto nenhum.
# O caso (1) com um job de 3 minutos é exatamente o que quebrava antes.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; ((fail++)); fi; }

export RUNDIR="$FIX/run" CONTESTSDIR="$FIX/contests"
source "$ROOT/judge-gw/sched-lib.sh"
sched_init_dirs; mkdir -p "$UPDATESDIR/pending"

now=$EPOCHSECONDS
beat(){ # <host> <idade-do-heartbeat-em-s>
  mkdir -p "$REGISTRYDIR"
  jq -cn --arg h "$1" --argjson t "$((now - $2))" \
    '{host:$h, state:"free", free_slots:6, total_slots:6, last_seen:$t}' > "$REGISTRYDIR/$1.json"
}
poe(){ # <host> <id> <idade-da-reivindicação-em-s>  -> cria o job atribuído
  mkdir -p "$ASSIGNEDDIR/$1"
  jq -cn --arg i "$2" --argjson a "$((now - $3))" \
    '{id:$i, kind:"submission", priority:"prova", assigned_at:$a}' \
    > "$ASSIGNEDDIR/$1/$((now - $3))_$2.json"
}
tem(){ [[ -f "$ASSIGNEDDIR/$1/$(cd "$ASSIGNEDDIR/$1" && ls | grep -F "$2" | head -1)" ]] 2>/dev/null; }
naFila(){ find "$QUEUEDIR" -name "*$1*.json" 2>/dev/null | grep -q .; }
solta(){ rm -f "$QUEUEDIR/.reconcile-stamp"; }   # o reconcile é auto-throttled em 15s

echo "== o teto vale para juiz VIVO, e tem de caber a correção inteira =="
ck "ASSIGN_TTL >= 600s (job pesado: 737 MB, 362 testes, download incluso)" '(( ASSIGN_TTL >= 600 ))'
ck "ASSIGN_TTL não é menor que o da calibração sem motivo" '(( ASSIGN_TTL >= UPD_TTL/2 ))'

beat vivo 5
poe vivo j-recente 30
solta; q_reconcile
ck "juiz vivo, job de 30s: a posse continua dele" '! naFila j-recente'

# 3 minutos: o caso REAL do incidente — com o teto antigo (120s) isto voltava p/ a fila
poe vivo j-tresmin 180
solta; q_reconcile
ck "juiz vivo, job de 3min: NÃO é revogado (era o bug)" '! naFila j-tresmin'

poe vivo j-velho $((ASSIGN_TTL + 60))
solta; q_reconcile
ck "juiz vivo, job passado do teto: volta p/ a fila" 'naFila j-velho'

echo "== juiz MORTO devolve na hora, sem esperar teto =="
beat morto 300                     # heartbeat velho: passou do REG_TTL
poe morto j-morto 10               # job recém-reivindicado
solta; q_reconcile
ck "juiz sem heartbeat: job volta mesmo recém-reivindicado" 'naFila j-morto'

echo "== agente que reinicia devolve tudo (register boot:true) =="
beat rebooter 5
poe rebooter j-boot1 10
poe rebooter j-boot2 20
sched_requeue_host rebooter
ck "requeue_host devolve os dois"  'naFila j-boot1 && naFila j-boot2'
ck "e o dir do host fica vazio"    '[[ -z "$(ls -A "$ASSIGNEDDIR/rebooter" 2>/dev/null)" ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
