#!/bin/bash
# ingest-vigia.sh — VIGIA do spool de results (prova da Maratona 29/08). Roda NO HOST como
# o usuário moj, em loop. Quando os results represados no spool passam do limiar, executa o
# ciclo de resgate provado às 19:0x da prova:
#   1. para o daemon bash (o ingestor Python vira o ÚNICO escritor — zero corrida);
#   2. ingest-drain.py (2.033 veredictos em 46 s na estreia; deixa held/edge p/ o bash);
#   3. metrics SÓ dos usuários afetados (ingest-affected.txt), em paralelo (xargs -P8);
#   4. religa o daemon (que trata os deixados) e agenda o build do placar.
# Guardas: lock (1 vigia), cooldown entre ciclos, religa o daemon SEMPRE (trap), log próprio.
# Parar: touch $RUNDIR/ingest-vigia.stop  (ou pkill -f ingest-vigia).
set -u
RUNDIR="${RUNDIR:-/home/moj/moj/run}"
SPOOL="$RUNDIR/spool/submissions"
LIMIAR="${VIGIA_LIMIAR:-250}"
COOLDOWN="${VIGIA_COOLDOWN_S:-120}"
LOG="$RUNDIR/ingest-vigia.log"
STOP="$RUNDIR/ingest-vigia.stop"
API_CT="${VIGIA_API_CT:-systemd-moj-api}"

exec 9>"$RUNDIR/.ingest-vigia.lock"
flock -n 9 || { echo "já há um vigia rodando"; exit 1; }
vlog(){ printf '[vigia %(%H:%M:%S)T] %s\n' -1 "$*" >> "$LOG"; }
vlog "vigia no ar (limiar=$LIMIAR cooldown=${COOLDOWN}s)"

ciclo(){
  vlog "CICLO: $1 results no spool — parando o daemon"
  systemctl --user stop moj-judged 2>>"$LOG"
  # religa SEMPRE, mesmo se o dreno explodir (o daemon parado é o único estado perigoso)
  trap 'systemctl --user start moj-judged 2>>"$LOG"; trap - RETURN' RETURN
  podman exec -i "$API_CT" python3 /data/run/ingest-drain.py >> "$LOG" 2>&1
  # metrics SÓ dos afetados, 8 em paralelo (recompute é por-usuário e independente)
  if [[ -s "$RUNDIR/ingest-affected.txt" ]]; then
    local n; n=$(wc -l < "$RUNDIR/ingest-affected.txt")
    vlog "metrics de $n usuários afetados (P8)"
    podman exec -i "$API_CT" bash -c '
      cd /opt/moj/cdmoj/server/api/v1
      xargs -a /data/run/ingest-affected.txt -n2 -P8 bash -c "
        source lib/common.sh 2>/dev/null; source lib/users.sh
        metrics_recompute \"\$0\" \"\$1\"" ' >> "$LOG" 2>&1
    rm -f "$RUNDIR/ingest-affected.txt"
  fi
  vlog "ciclo concluído — daemon volta"
}

while :; do
  [[ -e "$STOP" ]] && { vlog "stop-file — encerrando"; rm -f "$STOP"; exit 0; }
  n=$(ls "$SPOOL" 2>/dev/null | grep -v "^\." | grep -c ":result:")
  if (( n >= LIMIAR )); then
    ciclo "$n"
    sleep "$COOLDOWN"
  else
    sleep 20
  fi
done
