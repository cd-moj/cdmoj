#!/bin/bash
# server/judge-gw/result-sink.sh — Listener de RESULTADO POR PUSH.
#
# PROBLEMA QUE RESOLVE — o double-poll. Hoje o veredicto volta assim:
#   web/corrige.sh  --getresult-->  master(:27000)  --getresult-->  worker
# em loop de 0.5s por até 24h (enviar-newcdmoj.sh::pega-resultado-newcdmoj).
# Aqui invertemos: quando o worker TERMINA, ele (ou o master) faz UM POST do
# veredicto para este sink, que grava o arquivo onde o backend cluster do
# judge.sh está esperando: $RUNDIR/results/<jobid> (e também <corr>, se vier).
# O daemon/gateway acorda na hora — zero polling no caminho feliz.
#
# Protocolo (1 linha JSON por conexão):
#   {"cmd":"result","jobid":"<id>","verdict":"Accepted,100p"}
#   {"cmd":"result","corr":"<corr>","verdict":"Wrong Answer,0p"}   # alternativa
# Resposta: {"ok":true,"jobid":"<id>"} (uma linha).
#
# ESCOLHA DE TRANSPORTE: socat (presente neste ambiente) como primário — faz fork
# por conexão e passa stdin/stdout ao handler de forma limpa. Fallback: ncat -l -k
# (Ncat) com --exec; e, em último caso, um loop com `nc -l` clássico. Sem broker,
# sem DB — fiel a bash + arquivos, como o resto do cluster.
#
# Uso:
#   bash result-sink.sh                 # escuta em $RESULT_SINK_PORT (default 28000)
#   RESULT_SINK_PORT=28001 bash result-sink.sh
#   bash result-sink.sh --handler       # (interno) processa UMA conexão de stdin
#
# Teste manual:
#   bash result-sink.sh &                # sobe o sink
#   printf '{"cmd":"result","jobid":"abc","verdict":"Accepted,100p"}\n' | nc localhost 28000
#   cat "$RUNDIR/results/abc"            # -> Accepted,100p

set -u

SINK_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
SERVER_DIR="$(cd "$SINK_DIR/.." && pwd)"
_COMMON_CONF="$SERVER_DIR/etc/common.conf"
[[ -r "$_COMMON_CONF" ]] && source "$_COMMON_CONF"

: "${RUNDIR:=/home/ribas/moj/run}"
: "${RESULTSDIR:=$RUNDIR/results}"
: "${RESULT_SINK_HOST:=0.0.0.0}"
: "${RESULT_SINK_PORT:=28000}"

mkdir -p "$RESULTSDIR" 2>/dev/null

slog() { echo "[result-sink $(date +%H:%M:%S)] $*" >&2; }

# Handler de UMA conexão: lê 1 linha JSON de stdin, grava o veredicto, responde.
# Escrita atômica (mv) p/ o leitor (judge.sh) nunca ler um arquivo pela metade.
handle_conn() {
  local line jobid corr verdict
  IFS= read -r line || return 0
  [[ -z "$line" ]] && return 0

  jobid="$(jq -r '.jobid // empty'   2>/dev/null <<<"$line")"
  corr="$( jq -r '.corr  // empty'   2>/dev/null <<<"$line")"
  verdict="$(jq -r '.verdict // empty' 2>/dev/null <<<"$line")"

  if [[ -z "$verdict" || ( -z "$jobid" && -z "$corr" ) ]]; then
    printf '{"ok":false,"error":"need verdict and (jobid or corr)"}\n'
    slog "rejeitado: $line"
    return 0
  fi

  # grava em ambas as chaves disponíveis (jobid e corr) p/ casar com o gateway.
  local key tmp
  for key in "$jobid" "$corr"; do
    [[ -z "$key" ]] && continue
    # sanitiza a chave (sem / nem ..): é id/hash, mas defensivo.
    case "$key" in */*|*..*) slog "chave suspeita ignorada: $key"; continue ;; esac
    tmp="$RESULTSDIR/.$key.$$"
    printf '%s' "$verdict" > "$tmp" && mv -f "$tmp" "$RESULTSDIR/$key"
  done

  printf '{"ok":true,"jobid":"%s","corr":"%s"}\n' "$jobid" "$corr"
  slog "push recebido jobid=$jobid corr=$corr verdict=$verdict"
}

serve() {
  slog "ouvindo em $RESULT_SINK_HOST:$RESULT_SINK_PORT -> grava em $RESULTSDIR/"
  local self; self="$(readlink -f "$0")"

  if command -v socat >/dev/null 2>&1; then
    slog "transporte: socat (fork por conexão)"
    exec socat -T 15 \
      TCP-LISTEN:"$RESULT_SINK_PORT",bind="$RESULT_SINK_HOST",reuseaddr,fork \
      EXEC:"bash $self --handler"
  elif ncat --version >/dev/null 2>&1 || nc --version 2>&1 | grep -qi ncat; then
    slog "transporte: ncat -l -k --exec"
    exec ncat -l -k "$RESULT_SINK_HOST" "$RESULT_SINK_PORT" \
      --exec "bash $self --handler"
  else
    slog "transporte: loop com 'nc -l' (sem fork persistente; reabre a cada conexão)"
    while true; do
      nc -l "$RESULT_SINK_PORT" -c "bash $self --handler" 2>/dev/null \
        || nc -l -p "$RESULT_SINK_PORT" -e bash 2>/dev/null \
        || { slog "nc -l indisponível; abortando"; exit 1; }
    done
  fi
}

case "${1:-}" in
  --handler) handle_conn ;;
  ""|--serve) serve ;;
  -h|--help) sed -n '2,40p' "$0" ;;
  *) echo "uso: $0 [--serve|--handler]" >&2; exit 2 ;;
esac
