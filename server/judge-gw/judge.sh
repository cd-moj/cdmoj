#!/bin/bash
# server/judge-gw/judge.sh — Gateway library para julgar uma submissão.
#
# Expõe uma única função:
#   judge_run <contest> <problemid> <lang> <code_b64> <filename>
# que escreve o veredicto (string, ex. "Accepted,100p") em stdout e nada mais
# (logs vão para stderr). O daemon (server/daemons/judged.sh) é o consumidor.
#
# Três backends, escolhidos por $JUDGE_BACKEND (default "mock"):
#   mock     — determinístico, não precisa de bubblewrap nem do cluster.
#              Serve para testar o pipeline assíncrono inteiro de ponta a ponta.
#   local    — roda mojtools/build-and-test.sh contra um pacote local de problema
#              em $PROBLEMSDIR/<problemid> usando bubblewrap (bwrap). Se o ambiente
#              não suportar (sem bwrap / sem pacote), faz fallback com mensagem clara.
#   cluster  — envia {"cmd":"run",...} ao escalonador (host:port em $JUDGE_MASTER,
#              default localhost:27000) via nc, obtém o jobid e recebe o veredicto
#              por PUSH (result-sink.sh grava em $RUNDIR/results/<jobid>); se o push
#              não estiver disponível, faz fallback p/ um poll limitado de getresult.
#
# Tudo é file-based e aditivo: NÃO altera api/** nem mojtools/**. Pode ser tanto
# "sourced" (expõe judge_run) quanto executado como CLI para testes manuais:
#   JUDGE_BACKEND=mock bash judge.sh treino p1 C "$(printf 'int main(){}'|base64 -w0)" sol.c

# ------------------------------------------------------------------ config base
# Carrega common.conf se existir (CONTESTSDIR, RUNDIR, ...), respeitando overrides
# de ambiente (o common.conf usa `: "${VAR:=default}"`).
JUDGE_GW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
_COMMON_CONF="$JUDGE_GW_DIR/../etc/common.conf"
[[ -r "$_COMMON_CONF" ]] && source "$_COMMON_CONF"

: "${RUNDIR:=/home/ribas/moj/run}"
: "${JUDGE_BACKEND:=mock}"
: "${JUDGE_MASTER:=localhost:27000}"          # escalonador (cmd run / getresult)
: "${PROBLEMSDIR:=/home/ribas/moj/judge/judge/problems}"   # pacotes p/ backend local
: "${MOJTOOLS_DIR:=/home/ribas/moj/mojtools}"
: "${RESULTSDIR:=$RUNDIR/results}"            # onde o result-sink (push) grava
: "${JUDGE_POLL_MAX:=600}"                    # iterações máx. do fallback de poll
: "${JUDGE_PUSH_WAIT:=86400}"                 # seg. máx. esperando o push (24h)

# Para enviar ao cluster (port from enviar-newcdmoj.sh). Vazio => "qualquer máquina".
: "${MOJCONTESTSERVERS:=}"
: "${CONTEST_END:=}"
: "${CONTEST_TYPE:=}"

judge_log() { echo "[judge.sh] $*" >&2; }

# Divide "host:port" em $1=host $2=port (helper p/ nc).
_jg_host() { echo "${1%:*}"; }
_jg_port() { echo "${1##*:}"; }

# ----------------------------------------------------------------- backend: mock
# Determinístico. Decodifica o base64: se vier vazio => Compilation Error.
# Caso contrário, Accepted,100p. (Suficiente p/ exercitar todo o pipeline.)
judge_run_mock() {
  local code_b64="$4"
  local decoded
  decoded="$(printf '%s' "$code_b64" | base64 -d 2>/dev/null)"
  if [[ -z "${decoded//[$' \t\r\n']/}" ]]; then
    echo "Compilation Error"
    return 0
  fi
  echo "Accepted,100p"
}

# ---------------------------------------------------------------- backend: local
# Roda build-and-test.sh (bubblewrap) contra $PROBLEMSDIR/<problemid>.
# Guardado: se faltar bwrap, o script, ou o pacote do problema, faz fallback claro.
judge_run_local() {
  local problemid="$2" lang="$3" code_b64="$4" filename="$5"
  local bat="$MOJTOOLS_DIR/build-and-test.sh"
  local pkg="$PROBLEMSDIR/$problemid"

  if ! command -v bwrap >/dev/null 2>&1; then
    judge_log "backend=local: 'bwrap' (bubblewrap) ausente — fallback"
    echo "Judge Error (no sandbox: bwrap not installed)"
    return 0
  fi
  if [[ ! -x "$bat" && ! -r "$bat" ]]; then
    judge_log "backend=local: build-and-test.sh não encontrado em $bat — fallback"
    echo "Judge Error (build-and-test.sh missing)"
    return 0
  fi
  if [[ ! -d "$pkg" ]]; then
    judge_log "backend=local: pacote do problema ausente em $pkg — fallback"
    echo "Judge Error (problem package not found: $problemid)"
    return 0
  fi

  local work src verdict rc
  work="$(mktemp -d)"
  src="$work/${filename:-solution}"
  if ! printf '%s' "$code_b64" | base64 -d > "$src" 2>/dev/null; then
    judge_log "backend=local: base64 inválido"
    rm -rf "$work"
    echo "Compilation Error"
    return 0
  fi
  # build-and-test.sh imprime na ÚLTIMA linha o veredicto final (ex. "Accepted,100p").
  # lowercase a linguagem como o cluster faz.
  local llang
  llang="$(printf '%s' "$lang" | tr '[:upper:]' '[:lower:]')"
  local out batwork
  out="$(bash "$bat" "$llang" "$src" "$pkg" y 2>/dev/null)"
  rc=$?
  batwork="$(printf '%s\n' "$out" | head -n1)"   # 1ª linha do stdout = workdir
  verdict="$(printf '%s\n' "$out" | tail -n1)"   # última linha = veredicto
  # captura o report.html auto-contido gerado pelo build-and-test.sh, se a API
  # pediu (JUDGE_REPORT_OUT). build-and-test.sh não limpa o próprio workdir.
  if [[ -n "$batwork" && -d "$batwork" && -f "$batwork/run-trace.log" ]]; then
    if [[ -n "${JUDGE_REPORT_OUT:-}" && -f "$batwork/report.html" ]]; then
      mkdir -p "$(dirname "$JUDGE_REPORT_OUT")" 2>/dev/null
      cp -f "$batwork/report.html" "$JUDGE_REPORT_OUT" 2>/dev/null
    fi
    # sidecar com o veredicto ESTRUTURADO (do report.env), p/ o daemon montar results/<id>.json
    # igual ao backend real (consistência dev=prod: canônico/score/correct/total p/ o resumo).
    if [[ -n "${JUDGE_REPORT_OUT:-}" && -f "$batwork/report.env" ]]; then
      ( VERDICT_CANON=""; SCORE=0; SCORE_MAX=100; SCORE_KIND=tests; CORRECT=0; TOTALTESTS=0
        source "$batwork/report.env" 2>/dev/null
        [[ "$SCORE" =~ ^-?[0-9]+$ ]] || SCORE=0; [[ "$SCORE_MAX" =~ ^[0-9]+$ ]] || SCORE_MAX=100
        [[ "$CORRECT" =~ ^[0-9]+$ ]] || CORRECT=0; [[ "$TOTALTESTS" =~ ^[0-9]+$ ]] || TOTALTESTS=0
        jq -n --arg vc "${VERDICT_CANON:-${verdict%%,*}}" --argjson sc "$SCORE" --argjson sm "$SCORE_MAX" \
           --arg sk "${SCORE_KIND:-tests}" --argjson co "$CORRECT" --argjson to "$TOTALTESTS" \
           '{verdict_canon:$vc, score:$sc, score_max:$sm, score_kind:$sk, correct:$co, total_tests:$to}' \
           > "${JUDGE_REPORT_OUT%.html}.meta.json" 2>/dev/null )
    fi
    rm -rf "$batwork"
  fi
  rm -rf "$work"
  if [[ -z "$verdict" ]]; then
    judge_log "backend=local: build-and-test.sh não retornou veredicto (rc=$rc)"
    echo "Judge Error (no verdict from sandbox)"
    return 0
  fi
  echo "$verdict"
}

# -------------------------------------------------------------- backend: cluster
# Constrói o JSON {"cmd":"run",...} (portado de enviar-newcdmoj.sh) e o envia ao
# escalonador via nc. Recebe o jobid; depois espera o veredicto por PUSH (arquivo
# $RESULTSDIR/<jobid> escrito pelo result-sink). Se o push não chegar / sink não
# estiver de pé, faz fallback p/ poll limitado de getresult no master.
judge_run_cluster() {
  local contest="$1" problemid="$2" lang="$3" code_b64="$4" filename="$5"
  local host port
  host="$(_jg_host "$JUDGE_MASTER")"; port="$(_jg_port "$JUDGE_MASTER")"

  if ! command -v nc >/dev/null 2>&1; then
    judge_log "backend=cluster: 'nc' ausente — não dá p/ falar com o master"
    echo "Judge Error (nc missing)"
    return 0
  fi

  local llang reqjson jobid corr
  llang="$(printf '%s' "$lang" | tr '[:upper:]' '[:lower:]')"
  # jobid de correlação ponta-a-ponta (mesma string no push de volta).
  corr="$(printf '%s%s%s%s' "$contest" "$problemid" "$EPOCHSECONDS" "$RANDOM" \
            | sha256sum | cut -c1-32)"

  # JSON do "run": mesmos campos que enviar-newcdmoj.sh, + corr p/ rastreio e
  # result_sink p/ o master saber pra onde empurrar (se suportar push).
  reqjson="$(jq -cn \
    --arg contest "$contest" \
    --arg servers "$MOJCONTESTSERVERS" \
    --arg cend "$CONTEST_END" \
    --arg ctype "$CONTEST_TYPE" \
    --arg prob "$problemid" \
    --arg lang "$llang" \
    --arg fname "${filename:-solution}" \
    --arg fb64 "$code_b64" \
    --arg corr "$corr" \
    --arg sink "${RESULT_SINK:-}" \
    '{cmd:"run", contest_servers:$servers, contest_end:$cend, type:$ctype,
      problemid:$prob, language:$lang, filename:$fname, fileb64:$fb64,
      corr:$corr, result_sink:$sink, metadata:$corr}')"

  judge_log "backend=cluster: enviando run p/ $host:$port (corr=$corr)"
  local resp
  resp="$(printf '%s\n' "$reqjson" | timeout 60 nc "$host" "$port" 2>/dev/null)"
  jobid="$(printf '%s' "$resp" | jq -r '.jobid // empty' 2>/dev/null)"
  if [[ -z "$jobid" ]]; then
    judge_log "backend=cluster: master não devolveu jobid (resp=$resp) — sem servidor?"
    echo "No_Servers"
    return 0
  fi
  judge_log "backend=cluster: jobid=$jobid (corr=$corr)"

  # 1) Caminho PUSH: o result-sink grava $RESULTSDIR/<corr> ou <jobid>.
  #    Esperamos por qualquer um dos dois (o master pode ecoar corr ou jobid).
  mkdir -p "$RESULTSDIR" 2>/dev/null
  local waited=0 verdict=""
  local f_corr="$RESULTSDIR/$corr" f_job="$RESULTSDIR/$jobid"
  # só tentamos esperar o push se houver um sink configurado/observável
  if [[ -d "$RESULTSDIR" ]]; then
    while (( waited < JUDGE_PUSH_WAIT )); do
      if [[ -s "$f_corr" ]]; then verdict="$(<"$f_corr")"; rm -f "$f_corr"; break; fi
      if [[ -s "$f_job"  ]]; then verdict="$(<"$f_job")";  rm -f "$f_job";  break; fi
      # Se não há sink rodando, não faz sentido esperar 24h — cai p/ poll após grace.
      if [[ -z "${RESULT_SINK:-}" ]] && (( waited >= ${JUDGE_PUSH_GRACE:-3} )); then
        break
      fi
      sleep 0.5
      ((waited++))
    done
  fi
  if [[ -n "$verdict" ]]; then
    judge_log "backend=cluster: veredicto via PUSH: $verdict"
    echo "$verdict"
    return 0
  fi

  # 2) Fallback: poll limitado de getresult (o double-poll que estamos
  #    substituindo — fica só como rede de segurança).
  judge_log "backend=cluster: sem push, fallback p/ poll de getresult"
  local count=0 inicio=$EPOCHSECONDS status=""
  while (( count < JUDGE_POLL_MAX )) && (( EPOCHSECONDS - inicio < JUDGE_PUSH_WAIT )); do
    status="$(printf '{ "cmd": "getresult", "jobid": "%s" }\n' "$jobid" \
                | timeout 30 nc "$host" "$port" 2>/dev/null \
                | jq -r '.status // empty' 2>/dev/null | tr '/' ',')"
    [[ -n "$status" && "$status" != "On queue" && "$status" != "Running" ]] && break
    sleep 0.5
    ((count++))
  done
  [[ "$status" == "On queue" || "$status" == "Running" ]] && status=""
  [[ "$status" == "Presentation Error" ]] && status="Accepted"
  if [[ -z "$status" ]]; then
    echo "Judge Error (no result)"
    return 0
  fi
  judge_log "backend=cluster: veredicto via poll: $status"
  echo "$status"
}

# ------------------------------------------------------------------- dispatcher
# judge_run <contest> <problemid> <lang> <code_b64> <filename> -> veredicto em stdout
judge_run() {
  local contest="$1" problemid="$2" lang="$3" code_b64="$4" filename="$5"
  case "$JUDGE_BACKEND" in
    mock)    judge_run_mock    "$contest" "$problemid" "$lang" "$code_b64" "$filename" ;;
    local)   judge_run_local   "$contest" "$problemid" "$lang" "$code_b64" "$filename" ;;
    cluster) judge_run_cluster "$contest" "$problemid" "$lang" "$code_b64" "$filename" ;;
    *)
      judge_log "JUDGE_BACKEND desconhecido: '$JUDGE_BACKEND' (use mock|local|cluster)"
      echo "Judge Error (unknown backend)"
      ;;
  esac
}

# Execução direta como CLI (para testes manuais). Sourced => não dispara.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -lt 4 ]]; then
    echo "uso: JUDGE_BACKEND=mock|local|cluster $0 <contest> <problemid> <lang> <code_b64> [filename]" >&2
    exit 2
  fi
  judge_run "$1" "$2" "$3" "$4" "${5:-solution}"
fi
