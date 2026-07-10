#!/bin/bash
# server/judge-gw/judge.sh — Gateway library para julgar uma submissão.
#
# Expõe uma única função:
#   judge_run <contest> <problemid> <lang> <code_b64> <filename>
# que escreve o veredicto (string, ex. "Accepted,100p") em stdout e nada mais
# (logs vão para stderr). O daemon (server/daemons/judged.sh) é o consumidor.
#
# Dois backends, escolhidos por $JUDGE_BACKEND (default "mock"):
#   mock     — determinístico, não precisa de bubblewrap. Serve para testar o
#              pipeline assíncrono inteiro de ponta a ponta.
#   local    — roda mojtools/build-and-test.sh contra um pacote local de problema
#              em $PROBLEMSDIR/<problemid> usando bubblewrap (bwrap). Se o ambiente
#              não suportar (sem bwrap / sem pacote), faz fallback com mensagem clara.
#
# Em produção o julgamento é PULL (INTAKE_MODE=queue): o daemon enfileira e os juízes
# puxam o job no heartbeat — judge_run NÃO é chamado (ver server/judge-gw/PULL.md).
# O backend síncrono "cluster" (master :27000 + push via result-sink) foi removido.
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
: "${PROBLEMSDIR:=/home/ribas/moj/judge/judge/problems}"   # pacotes p/ backend local
: "${MOJTOOLS_DIR:=/home/ribas/moj/mojtools}"

judge_log() { echo "[judge.sh] $*" >&2; }

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
      ( VERDICT_CANON=""; SCORE=0; SCORE_MAX=100; SCORE_KIND=tests; CORRECT=0; TOTALTESTS=0; SCORE_GROUPS=""
        source "$batwork/report.env" 2>/dev/null
        [[ "$SCORE" =~ ^-?[0-9]+$ ]] || SCORE=0; [[ "$SCORE_MAX" =~ ^[0-9]+$ ]] || SCORE_MAX=100
        [[ "$CORRECT" =~ ^[0-9]+$ ]] || CORRECT=0; [[ "$TOTALTESTS" =~ ^[0-9]+$ ]] || TOTALTESTS=0
        # grupos estruturados (subtarefas): só entram se forem JSON array válido
        groups=null
        [[ -n "$SCORE_GROUPS" ]] && jq -e 'type=="array"' <<<"$SCORE_GROUPS" >/dev/null 2>&1 && groups="$SCORE_GROUPS"
        jq -n --arg vc "${VERDICT_CANON:-${verdict%%,*}}" --argjson sc "$SCORE" --argjson sm "$SCORE_MAX" \
           --arg sk "${SCORE_KIND:-tests}" --argjson co "$CORRECT" --argjson to "$TOTALTESTS" \
           --argjson g "$groups" \
           '{verdict_canon:$vc, score:$sc, score_max:$sm, score_kind:$sk, correct:$co, total_tests:$to}
            + (if $g == null then {} else {groups:$g} end)' \
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

# ------------------------------------------------------------------- dispatcher
# judge_run <contest> <problemid> <lang> <code_b64> <filename> -> veredicto em stdout
judge_run() {
  local contest="$1" problemid="$2" lang="$3" code_b64="$4" filename="$5"
  case "$JUDGE_BACKEND" in
    mock)    judge_run_mock    "$contest" "$problemid" "$lang" "$code_b64" "$filename" ;;
    local)   judge_run_local   "$contest" "$problemid" "$lang" "$code_b64" "$filename" ;;
    queue)
      # Pull/queue: a submissão deveria ter sido ENFILEIRADA pelo daemon (intake_enqueue)
      # antes de chegar aqui. Se caiu neste caminho, é bug de fluxo — falha alto.
      judge_log "judge_run chamado com JUDGE_BACKEND=queue (deveria ter enfileirado)"
      echo "Judge Error (queue backend: submissão não enfileirada)"
      ;;
    *)
      judge_log "JUDGE_BACKEND desconhecido: '$JUDGE_BACKEND' (use mock|local|queue)"
      echo "Judge Error (unknown backend)"
      ;;
  esac
}

# Execução direta como CLI (para testes manuais). Sourced => não dispara.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -lt 4 ]]; then
    echo "uso: JUDGE_BACKEND=mock|local $0 <contest> <problemid> <lang> <code_b64> [filename]" >&2
    exit 2
  fi
  judge_run "$1" "$2" "$3" "$4" "${5:-solution}"
fi
