# lib/spool-shard.sh — partição do ESCRITOR por hash(login) (2026-08-30).
#
# O daemon (judged.sh) é o escritor único de history/metrics — e por isso o teto do
# pipeline era 1/(t_intake+t_ingest) ≈ 820 veredictos/min (medido na bancada). Os dados
# são POR USUÁRIO (history/metrics/submissions/results/mojlog independentes), então o
# escritor único vale POR LOGIN, não por instância: K workers, cada um dono da fatia
# hash(login) % K, preservam a exclusão por usuário SEM lock novo. Pontos cross-user já
# eram seguros: placar coalescido sob flock (-n), clog/audit em append O_APPEND, arquivos
# por-id únicos (results globais, review, reconciled), fila do cluster sob flock próprio.
#
# LAYOUT: shard 0 usa o $SPOOLDIR RAIZ (K=1 ⇒ comportamento de sempre, byte a byte);
# shard k>0 usa $SPOOLDIR/s<k>/. Produtores que SABEM o login (submit, offline-submit,
# /judge/result, setverdict) gravam direto no dir do dono; o que cair na raiz sem ser do
# shard 0 (produtor legado, rejudge de admin) é ROTEADO pelo worker 0 (1 mv; p/ result/
# setverdict 1 extração POR ARQUIVO, só no caminho legado). Config-mismatch (API com K
# maior que o daemon) tem rede: o worker 0 varre dirs s<j> com j>=K e devolve à raiz.
#
# ⚠ API e daemon precisam do MESMO JUDGED_SHARDS (env dos dois containers). O default 1
# desliga tudo. Quem consome: submit.sh, contest/offline-submit.sh, judge/result.sh,
# lib/review.sh, contest/set-verdict.sh, daemons/judged.sh — e os LEITORES do spool
# (contagens/inflight) varrem raiz + s*/ (contest-rounds, preflight, index/status,
# ops/queue, treino/admin/queue, alerts, ingest-drain.py).
: "${JUDGED_SHARDS:=1}"

# shard_of_login <login> : ecoa o shard (0..K-1). djb2 sobre os bytes do login — ZERO
# forks (roda no /submit e no laço do reconcile). Login é ASCII validado na porta.
shard_of_login() {
  local s="$1" n="${JUDGED_SHARDS:-1}" h=5381 i c
  if (( n <= 1 )); then printf '0'; return 0; fi
  for (( i=0; i<${#s}; i++ )); do
    printf -v c '%d' "'${s:i:1}"
    h=$(( (h * 33 + c) & 0x7fffffff ))
  done
  printf '%s' $(( h % n ))
}

# spool_shard_dir <login> : ecoa o diretório de spool do DONO do login (cria o s<k> na
# primeira vez). Shard 0 = a raiz $SPOOLDIR — K=1 nunca cria subdiretório nenhum.
spool_shard_dir() {
  local k; k="$(shard_of_login "$1")"
  if [[ "$k" == 0 ]]; then
    printf '%s' "$SPOOLDIR"
  else
    mkdir -p "$SPOOLDIR/s$k" 2>/dev/null
    printf '%s' "$SPOOLDIR/s$k"
  fi
}

# spool_routing_json : ecoa UM objeto JSON com o retrato do ROTEAMENTO do escritor — p/ os
# painéis de admin (aba Fila do treino + Situação do contest). Fonte única; custo fixo e
# baixo (4 find + 2 awk + 1 jq ≈ 7 processos, independente do nº de shards/arquivos):
#   {shards:K, workers:[{shard, alive_age_s, in_submit, in_results, in_other}],
#    orphans:n, queue_depth:n, assigned:n, delivered_5m:n}
# in_submit = submissões aguardando INTAKE no dir do shard (entrada); in_results =
# resultados de juiz aguardando INGEST (a volta); in_other = setverdict/rejulgar/etc;
# alive_age_s = idade do judged.alive[.s<k>] (-1 = nunca bateu — worker do shard MORTO);
# orphans = arquivos em s<j> com j>=K (mismatch de config, o sweep do worker 0 resolve);
# delivered_5m = veredictos que ATERRISSARAM nos últimos 5 min (saída p/ o aluno).
spool_routing_json() {
  local K="${JUDGED_SHARDS:-1}" W; W="$(mktemp -d)"
  # um find + um awk: classifica TODO arquivo do spool por (shard, kind do campo 5 do nome)
  find "$SPOOLDIR" -type f ! -name '.*' -printf '%P\n' 2>/dev/null \
    | awk -v K="$K" -F/ '{
        sh=0; base=$0
        if (NF==2 && $1 ~ /^s[0-9]+$/) { sh=substr($1,2)+0; base=$2 }
        n=split(base, f, ":"); kind=(n>=5 ? f[5] : "?")
        if (sh >= K) { orq++; next }
        if (kind=="submit") sub_[sh]++
        else if (kind=="result") res[sh]++
        else oth[sh]++
      } END {
        for (k=0; k<K; k++) printf "%d\t%d\t%d\t%d\n", k, sub_[k]+0, res[k]+0, oth[k]+0
        printf "ORPH\t%d\n", orq+0
      }' > "$W/counts" 2>/dev/null
  # idade dos alives numa passada (worker morto = arquivo velho/ausente)
  find "${RUNDIR:?}" -maxdepth 1 -name 'judged.alive*' -printf '%f\t%T@\n' 2>/dev/null \
    | awk -v now="$EPOCHSECONDS" '{ split($2,t,"."); printf "%s\t%d\n", $1, now-t[1] }' > "$W/alive"
  local qd asg d5
  qd="$(find "${QUEUEDIR:-$RUNDIR/queue}" -mindepth 2 -maxdepth 2 -name '*.json' 2>/dev/null | wc -l)"
  asg="$(find "${ASSIGNEDDIR:-$RUNDIR/assigned}" -mindepth 2 -maxdepth 2 -name '*.json' 2>/dev/null | wc -l)"
  d5="$(find "${SPOOLDONEDIR:-$RUNDIR/spool/submissions-done}" -maxdepth 1 -name '*:result:*' -newermt '-300 seconds' 2>/dev/null | wc -l)"
  jq -cn --rawfile c "$W/counts" --rawfile a "$W/alive" --argjson k "$K" \
     --argjson qd "${qd//[^0-9]/}" --argjson asg "${asg//[^0-9]/}" --argjson d5 "${d5//[^0-9]/}" '
    ($a | split("\n") | map(select(length>0) | split("\t"))
        | map({key:.[0], value:(.[1]|tonumber)}) | from_entries) as $alive
    | ($c | split("\n") | map(select(length>0) | split("\t"))) as $rows
    | { shards: $k,
        workers: [ $rows[] | select(.[0] != "ORPH")
          | (.[0]|tonumber) as $sh
          | { shard: $sh,
              alive_age_s: (if $sh == 0 then ($alive["judged.alive"] // -1)
                            else ($alive["judged.alive.s\($sh)"] // -1) end),
              in_submit: (.[1]|tonumber), in_results: (.[2]|tonumber), in_other: (.[3]|tonumber) } ],
        orphans: ([ $rows[] | select(.[0] == "ORPH") | (.[1]|tonumber) ] | add // 0),
        queue_depth: $qd, assigned: $asg, delivered_5m: $d5 }'
  rm -rf "$W"
}
