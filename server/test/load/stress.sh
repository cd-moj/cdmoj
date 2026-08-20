#!/bin/bash
# server/test/load/stress.sh — gerador de carga em UM processo (curl -Z --parallel-max).
#
# POR QUE ESTE EXISTE: o web-poll-bench.sh (2026-07) sobe um `curl` POR REQUISIÇÃO, e num
# servidor cujo gargalo é justamente criar processo isso mede o GERADOR, não a API. Ele
# reportava teto de ~460 req/s; com um gerador de processo único a mesma API entrega
# **2.370 req/s** na rota trivial e ~875 req/s na mistura real de contest. Use este p/ número
# de capacidade; o outro continua útil como carga "cliente burro".
#
#   uso:   source stress.sh; run <n> <conc> <caminho> <rótulo>
#          source stress.sh; mix <n> <conc> <contest> <rótulo>
#   env:   STRESS_BASE (default https://127.0.0.1), STRESS_HOST, STRESS_TOKEN, STRESS_GZIP=1
#
# ⚠ Roda DO HOST do nginx e só faz GET. Contra contest de FIXTURE, nunca contra prova real.
set -u
B="${STRESS_BASE:-https://127.0.0.1}"; H="${STRESS_HOST:-moj.naquadah.com.br}"
_SW="$(mktemp -d)"; trap 'rm -rf "$_SW"' EXIT
# os cabeçalhos vão num ARRAY montado direto (o mapfile de antes é builtin do bash e sumia
# quando o comando era executado por um shell de login não-bash via ssh: o Authorization não
# era enviado e TUDO virava 401 — erro que parecia do servidor e era da bancada)
_HH=()
_hdr_init(){
  _HH=(-H "Host: $H")
  [[ -n "${STRESS_TOKEN:-}" ]] && _HH+=(-H "Authorization: Bearer $STRESS_TOKEN")
  [[ -n "${STRESS_GZIP:-}"  ]] && _HH+=(-H "Accept-Encoding: gzip")
  return 0
}
_go(){ # <conc> <rótulo> — consome $_SW/urls
  local c="$1" lbl="$2" t0 t1 ok er p50 p99 mx
  _hdr_init
  t0=$(date +%s.%N)
  curl -sk -Z --parallel-max "$c" "${_HH[@]}" -K "$_SW/urls" \
       -w '%{http_code} %{time_total}\n' > "$_SW/out" 2>/dev/null
  t1=$(date +%s.%N)
  ok=$(awk 'NF==2 && $1==200' "$_SW/out" | wc -l)
  er=$(awk 'NF==2 && $1!=200' "$_SW/out" | wc -l)
  sort -k2 -g "$_SW/out" | awk 'NF==2{a[++k]=$2} END{if(k)printf "%.3f %.3f %.3f", a[int(k*.5)], a[int(k*.99)], a[k]}' > "$_SW/p"
  read -r p50 p99 mx < "$_SW/p"
  awk -v n="$ok" -v a="$t0" -v b="$t1" -v c="$c" -v e="$er" -v l="$lbl" \
      -v p50="$p50" -v p99="$p99" -v mx="$mx" \
    'BEGIN{printf "  %-24s conc=%-5d %7.0f req/s  p50=%.3f p99=%.3f pior=%.3f  erros=%d\n",l,c,n/(b-a),p50,p99,mx,e}'
}
run(){ # <n> <conc> <caminho> <rótulo>
  local n="$1" c="$2" u="$3" lbl="${4:-$3}" i
  : > "$_SW/urls"
  for ((i=0;i<n;i++)); do printf 'url = "%s%s"\noutput = "/dev/null"\n' "$B" "$u" >> "$_SW/urls"; done
  _go "$c" "$lbl"
}
mix(){ # <n> <conc> <contest> <rótulo> — proporção MEDIDA no esquenta de 15/08/2026:
       # updates 55% · score 29% · basic 8% · history 5% · problems 3%
  local n="$1" c="$2" q="contest=$3" lbl="${4:-mistura}" i r p
  : > "$_SW/urls"
  for ((i=0;i<n;i++)); do
    r=$((RANDOM % 100))
    if   (( r < 55 )); then p="/api/v1/contest/updates?$q&news_since=0&clar_since=0"
    elif (( r < 84 )); then p="/api/v1/contest/score?$q"
    elif (( r < 92 )); then p="/api/v1/contest/basic?$q"
    elif (( r < 97 )); then p="/api/v1/contest/history?$q"
    else                    p="/api/v1/contest/problems?$q"; fi
    printf 'url = "%s%s"\noutput = "/dev/null"\n' "$B" "$p" >> "$_SW/urls"
  done
  _go "$c" "$lbl"
}
stampede(){ # <times> <conc> <contest> — o segundo zero: cada time pede basic+problems+history
  local t="$1" c="$2" q="contest=$3" i p
  : > "$_SW/urls"
  for ((i=0;i<t;i++)); do
    for p in "/api/v1/contest/basic?$q" "/api/v1/contest/problems?$q" "/api/v1/contest/history?$q"; do
      printf 'url = "%s%s"\noutput = "/dev/null"\n' "$B" "$p" >> "$_SW/urls"
    done
  done
  _go "$c" "estampida ${t}x3"
}
