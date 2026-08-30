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
