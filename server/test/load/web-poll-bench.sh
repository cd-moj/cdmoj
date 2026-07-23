#!/bin/bash
# server/test/load/web-poll-bench.sh — mede a saturação do WEB TIER (nginx→fcgiwrap→handlers)
# sob o padrão de polling de um contest. Cada "cliente virtual" repete o mix que o contest.js
# faz (contest/score + contest/basic + contest/updates), o mais rápido possível, p/ C clientes
# em paralelo por D segundos. Reporta throughput e p50/p95/p99 — o que importa p/ 1500 usuários.
#
#   uso: web-poll-bench.sh <base-url> <contest> [clients=200] [dur_s=10] [host-header]
#   ex:  web-poll-bench.sh https://127.0.0.1 rto_treino12 300 10 moj.naquadah.com.br
#
# Só GET (read-only). Rode DO HOST do nginx (contorna a rede externa). Precisa de curl.
set -u
BASE="${1:?uso: web-poll-bench.sh <base-url> <contest> [clients] [dur] [host]}"
CONTEST="${2:?falta o contest}"
CLIENTS="${3:-200}"
DUR="${4:-10}"
HOST="${5:-moj.naquadah.com.br}"
CURL=(curl -sk -o /dev/null -w '%{time_total} %{http_code}\n' -H "Host: $HOST")

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# Endpoints PÚBLICOS do polling (score é o mais pesado; basic é o leve). O /contest/updates
# exige auth (401 anônimo) — p/ medi-lo, exporte MOJ_BENCH_TOKEN e adicione o header
# Authorization ao array CURL. Aqui usamos os públicos, representativos do custo dominante.
endpoints=(
  "/api/v1/contest/score?contest=$CONTEST"
  "/api/v1/contest/basic?contest=$CONTEST"
)
[[ -n "${MOJ_BENCH_TOKEN:-}" ]] && { CURL+=(-H "Authorization: Bearer $MOJ_BENCH_TOKEN"); endpoints+=("/api/v1/contest/updates?contest=$CONTEST"); }
worker() {
  local out="$1" deadline="$2" i=0
  while (( $(date +%s) < deadline )); do
    "${CURL[@]}" "$BASE${endpoints[$(( i++ % ${#endpoints[@]} ))]}" 2>/dev/null
  done >> "$out"
}
echo "web-poll-bench: contest=$CONTEST clients=$CLIENTS dur=${DUR}s  mix=score+basic+updates"
deadline=$(( $(date +%s) + DUR ))
for ((c=0; c<CLIENTS; c++)); do worker "$TMP/w$c" "$deadline" & done
wait
cat "$TMP"/w* > "$TMP/all.txt"
total=$(wc -l < "$TMP/all.txt"); errs=$(awk '$2!="200"' "$TMP/all.txt" | wc -l)
awk -v tot="$total" -v errs="$errs" -v dur="$DUR" '
  {a[NR]=$1} END{
    n=asort(a);
    printf "  requisições: %d  (%.0f req/s)  erros(!=200): %d\n", tot, tot/dur, errs;
    printf "  latência (s): p50=%.3f  p95=%.3f  p99=%.3f  max=%.3f\n",
           a[int(n*0.50)], a[int(n*0.95)], a[int(n*0.99)], a[n];
  }' "$TMP/all.txt"
