#!/bin/bash
# ensaio-sonda.sh <saida.tsv> [intervalo=10] [duração_s=3600] [contest] — SONDA do lado do servidor no ENSAIO DE ESCRITA
# (ensaio-fixture.sh/ensaio-injetor.py). Mede o que ficou INVISÍVEL na Maratona de 29/08 (a esteira represou 35 min
# antes de alguém notar): profundidade do spool por shard, fila por banda, jobs reivindicados, veredictos gravados,
# CPU do judged e da API (cgroups dos quadlets), load, 5xx do nginx e o batimento do judged. Só LÊ.
# Roda no HOST de produção como root (precisa do log do nginx e dos cgroups do usuário moj). Ctrl-C/kill encerra.
set -u
OUT="${1:?uso: ensaio-sonda.sh <saida.tsv> [intervalo_s] [duração_s] [contest]}"; IV="${2:-10}"; DUR="${3:-3600}"; EC="${4:-}"
W="${MOJ_WORKROOT:-/home/moj/moj}"; R="$W/run"
U="$(id -u moj 2>/dev/null || echo 1003)"
CG="/sys/fs/cgroup/user.slice/user-$U.slice/user@$U.service/app.slice"
LOG="${NGINX_LOG:-/var/log/nginx/moj.access.log}"
cnt(){ find "$1" -maxdepth 1 -type f -name "${2:-*}" 2>/dev/null | wc -l; }
cpu_us(){ awk '/^usage_usec/ {print $2}' "$CG/$1/cpu.stat" 2>/dev/null || echo 0; }
printf 'epoch\tspool_s0\tspool_s1\tq_prova\tq_lpriv\tq_lpub\tq_outras\tassigned\tdone_total\tjudged_cpu_pct\tapi_cpu_pct\tload1\tnginx_5xx\tnginx_req\tjudged_alive_age\tslots_livres\tbaloes\n' > "$OUT"
end=$(( EPOCHSECONDS + DUR ))
pj="$(cpu_us moj-judged.service)"; pa="$(cpu_us moj-api.service)"; pt="$EPOCHREALTIME"
# o nginx é lido INCREMENTALMENTE (offset em bytes): ler o log inteiro a cada 10 s seria a sonda pesando no servidor
off="$(stat -c %s "$LOG" 2>/dev/null || echo 0)"
while (( EPOCHSECONDS < end )); do
  sleep "$IV"
  s0="$(cnt "$R/spool/submissions")"; s1="$(cnt "$R/spool/submissions/s1")"
  qp="$(cnt "$R/queue/020-prova" '*.json')"; ql="$(cnt "$R/queue/040-lista-privada" '*.json')"
  qu="$(cnt "$R/queue/080-lista-publica" '*.json')"
  qo=$(( $(cnt "$R/queue/000-super" '*.json') + $(cnt "$R/queue/060-rejulgar" '*.json') ))
  asg="$(find "$R/assigned" -mindepth 2 -maxdepth 2 -name '*.json' 2>/dev/null | wc -l)"
  dn="$(cnt "$R/spool/submissions-done")"
  nj="$(cpu_us moj-judged.service)"; na="$(cpu_us moj-api.service)"; nt="$EPOCHREALTIME"
  read -r jp ap < <(awk -v pj="$pj" -v nj="$nj" -v pa="$pa" -v na="$na" -v pt="$pt" -v nt="$nt" \
    'BEGIN { dt = (nt - pt) * 1e6; if (dt <= 0) dt = 1; printf "%.1f %.1f\n", 100*(nj-pj)/dt, 100*(na-pa)/dt }')
  pj="$nj"; pa="$na"; pt="$nt"
  l1="$(cut -d' ' -f1 /proc/loadavg)"
  sz="$(stat -c %s "$LOG" 2>/dev/null || echo 0)"; (( sz < off )) && off=0     # rotação
  read -r n5 nr < <(tail -c +"$((off + 1))" "$LOG" 2>/dev/null | head -c "$((sz - off))" \
    | awk '{ n++; if ($9 ~ /^5/) c++ } END { print c+0, n+0 }')
  off="$sz"
  al=-1; [[ -f "$R/judged.alive" ]] && al=$(( EPOCHSECONDS - $(stat -c %Y "$R/judged.alive") ))
  fs="$(find "$R/registry" -maxdepth 1 -name '*.json' -newermt "-60 seconds" -exec jq -r '.free_slots // 0' {} + 2>/dev/null \
        | awk '{ s += $1 } END { print s+0 }')"
  # tarefas de balão do contest do ensaio (nascem no 1º AC de cada time, na carga da fila do staff — escrita leve;
  # o PDF só no print, que o ensaio não faz)
  bl=0; [[ -n "$EC" ]] && bl="$(cnt "$W/contests/$EC/print-requests" '*.json')"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$EPOCHSECONDS" "$s0" "$s1" "$qp" "$ql" "$qu" "$qo" \
    "$asg" "$dn" "$jp" "$ap" "$l1" "$n5" "$nr" "$al" "$fs" "$bl" >> "$OUT"
done
