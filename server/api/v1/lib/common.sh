# lib/common.sh — utilidades base da API MOJ (sourced pelo router e handlers).
# Carrega config e fornece helpers de resposta (CGI), JSON, validação.

set -o noglob   # ids podem conter chars de glob; evita expansão acidental

# --- config ---------------------------------------------------------------
_LIBDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${MOJ_CONF:=$_LIBDIR/../../../etc/common.conf}"
[[ -f "$MOJ_CONF" ]] && source "$MOJ_CONF"
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
: "${SESSIONDIR:=/home/ribas/moj/run/sessions}"
: "${SPOOLDIR:=/home/ribas/moj/run/spool/submissions}"
# defaults DERIVADOS do próprio checkout (_LIBDIR = server/api/v1/lib), nunca caminho de dev
# hardcoded: na imagem de produção (/opt/moj/cdmoj) o caminho de dev NÃO EXISTE e o SCOREDIR
# quebrado fazia TODO regen_locked executar script inexistente, mudo (rc engolido) — os caches
# de response-stats/calib-activity/statistics/panorama nunca nasciam e os painéis serviam o
# fallback zerado p/ sempre. Env (imagem/quadlet) continua vencendo o default.
: "${NEWSDIR:=$_LIBDIR/../../../var/news}"
: "${SCOREDIR:=$_LIBDIR/../../../score}"
: "${DEFAULT_SCORE_MODE:=icpc}"
export CONTESTSDIR SCOREDIR   # herdados por sub-processos (ex.: server/score/build.sh)

# --- liveness do daemon de julgamento -------------------------------------
# O `pgrep` só enxerga o judged quando ele roda no MESMO namespace de PID que a API. No deploy
# recomendado (imagem podman) são DOIS containers — moj-api e moj-judged — e a API JAMAIS veria
# o processo: o painel o daria por morto e os alertas gritariam "daemon parado" p/ sempre.
# Por isso o daemon bate um heartbeat em $RUNDIR/judged.alive (que está no volume compartilhado)
# e aqui aceitamos os dois sinais. Fonte única: usada por /index/status e por lib/alerts.sh.
: "${RUNDIR:=/home/ribas/moj/run}"
: "${JUDGED_ALIVE_FILE:=$RUNDIR/judged.alive}"
: "${JUDGED_ALIVE_TTL:=120}"          # s; o daemon re-drena (e bate) a cada WATCH_REDRAIN_SECS=30
daemon_judged_alive() {
  pgrep -f 'server/daemons/judged.sh' >/dev/null 2>&1 && return 0
  local m; m="$(stat -c %Y "$JUDGED_ALIVE_FILE" 2>/dev/null)"
  [[ -n "$m" ]] || return 1
  (( EPOCHSECONDS - m <= JUDGED_ALIVE_TTL ))
}

# --- resposta (CGI) -------------------------------------------------------
# CGI: emitimos "Status:" (fcgiwrap/nginx traduzem p/ status HTTP) + Content-Type.
respond() {  # respond <code> <reason> <content-type>
  printf 'Status: %s %s\r\n' "${1:-200}" "${2:-OK}"
  printf 'Content-Type: %s\r\n' "${3:-application/json; charset=utf-8}"
  printf '\r\n'
}
emit_json(){ respond "${1:-200}" "${2:-OK}" "application/json; charset=utf-8"; }
emit_text(){ respond "${1:-200}" "${2:-OK}" "text/plain; charset=utf-8"; }
emit_html(){ respond "${1:-200}" "${2:-OK}" "text/html; charset=utf-8"; }

_reason() {
  case "$1" in
    200) echo OK;; 201) echo Created;; 400) echo "Bad Request";;
    401) echo Unauthorized;; 403) echo Forbidden;; 404) echo "Not Found";;
    405) echo "Method Not Allowed";; 409) echo Conflict;;
    422) echo "Unprocessable Entity";; 500) echo "Internal Server Error";;
    *) echo Error;;
  esac
}

# fail <http-status> <message> [error-code] — envelope de erro + encerra.
fail() {
  local code="${1:-400}" msg="$2" ecode="${3:-$1}"
  emit_json "$code" "$(_reason "$code")"
  jq -cn --arg m "$msg" --arg c "$ecode" '{success:false, error:{message:$m, code:$c}}'
  exit 0
}

# ok_json <jq-filter> [jq-args...] — envelope de sucesso: {success:true} + (filter)
# ex.: ok_json '{token:$t, name:$n}' --arg t "$UUID" --arg n "$NAME"
ok_json() {
  local filter="$1"; shift
  emit_json 200 OK
  jq -cn "$@" "{success:true} + ($filter)"
}

# --- validação / paths ----------------------------------------------------
valid_id() {  # id seguro (sem traversal). Permite #, @, ., +, -, _ (usados em ids).
  [[ "$1" =~ ^[A-Za-z0-9._@#+-]+$ ]] && [[ "$1" != *..* ]]
}
require_contest() {  # require_contest <id>
  valid_id "$1" || fail 400 "Invalid contest id" "contest_invalid"
  [[ -d "$CONTESTSDIR/$1" && -f "$CONTESTSDIR/$1/conf" ]] \
    || fail 404 "Contest not found" "contest_notfound"
}
# carrega o conf do contest em variáveis (CONTEST_NAME, CONTEST_TYPE, PROBS, ...)
load_contest_conf() { source "$CONTESTSDIR/$1/conf"; }
# contest SUPER SECRETO (conf SECRET=1): fora das listagens públicas (home/arquivo/status);
# placar e visual (balloons/regions/teams-meta) exigem sessão DO contest. Lido com grep
# (sem source no caminho quente — padrão do _users_source).
contest_is_secret() {
  local v; v="$(grep -m1 '^SECRET=' "$CONTESTSDIR/$1/conf" 2>/dev/null | cut -d= -f2-)"
  v="${v//\'/}"; v="${v//\"/}"; [[ "$v" == 1 ]]
}
# gate dos endpoints públicos quando o contest é secreto: exige sessão válida DAQUELE contest.
require_not_secret_or_auth() {  # <contest>
  contest_is_secret "$1" || return 0
  load_session 2>/dev/null && [[ "$SESSION_CONTEST" == "$1" ]] && return 0
  fail 401 "Contest privado — faça login para ver" "secret_login_required"
}
score_mode_of() {  # ecoa o modo de placar do contest (default DEFAULT_SCORE_MODE)
  local t; t="$(. "$CONTESTSDIR/$1/conf" 2>/dev/null; printf '%s' "${CONTEST_TYPE:-}")"
  case "$t" in
    icpc|obi|treino|heuristic|outro|custom) printf '%s' "$t";;
    lista-publica|lista-privada) printf 'treino';;
    *) printf '%s' "$DEFAULT_SCORE_MODE";;
  esac
}

# --- cache preguiçoso (regenera só quando a fonte muda) -------------------
# Espelha o comportamento legado do MOJ: o processamento (placar/estatísticas) só
# é refeito quando houve modificação na fonte (history/conf); senão serve o que já
# está pronto. E se nada foi gerado ainda, gera na hora (lazy).
#
# stale_cache <cache> <fonte...> : 0 (stale) se o cache não existe OU alguma fonte
# é mais nova que ele (mtime). 1 (fresco) caso contrário.
stale_cache() {
  local cache="$1"; shift
  [[ -f "$cache" ]] || return 0
  local s
  for s in "$@"; do [[ -e "$s" && "$s" -nt "$cache" ]] && return 0; done
  return 1
}

# regen_locked <lockfile> <fonte...> -- <comando...> : se o cache estiver velho,
# adquire um flock (evita rebuild concorrente — cache stampede), reconfere e roda o
# comando de geração. O 1º argumento da lista de fontes é tratado como o próprio
# cache p/ a reconferência. Silencioso; nunca aborta a request se a geração falha.
regen_locked() {
  local lock="$1"; shift
  local cache="$1"
  local -a srcs=() cmd=()
  while (( $# )); do [[ "$1" == "--" ]] && { shift; break; }; srcs+=("$1"); shift; done
  cmd=("$@")
  stale_cache "$cache" "${srcs[@]:1}" || return 0
  mkdir -p "$(dirname "$lock")" 2>/dev/null
  (
    flock -w 20 9 || exit 0
    stale_cache "$cache" "${srcs[@]:1}" || exit 0   # double-check após o lock
    "${cmd[@]}" >/dev/null 2>&1 || true
  ) 9>"$lock"
}

# --- util -----------------------------------------------------------------
urldecode() { local s="${1//+/ }"; printf '%b' "${s//%/\\x}"; }
read_body(){ cat -; }
# read_body_file — grava o corpo num ARQUIVO temporário e ecoa o CAMINHO. Obrigatório nos POSTs
# GRANDES (o pacote de um problema chega a 100+ MB de JSON). Com o corpo numa VARIÁVEL, cada
# `jq … <<<"$body"` é um here-string: o bash REGRAVA os 100 MB num temp e o jq RE-PARSEIA tudo —
# o handler de push fazia isso 36 vezes (~50s de CPU + 3,6 GB de I/O) e estourava o
# fastcgi_read_timeout, deixando o pacote META-APLICADO. Com o corpo em arquivo, todo jq lê o
# arquivo direto (`jq … < "$f"`) e dá p/ passar por --slurpfile. Quem chama remove o arquivo.
read_body_file(){ local f; f="$(mktemp)"; cat - > "$f"; printf '%s' "$f"; }
# render_markdown_html: markdown do stdin -> fragmento HTML no stdout (pandoc 3.x).
# raw_html DESABILITADO (conteúdo público; impede <script> injetado); math via --mathml.
# Usado pelas notícias/posts (detalhe e preview do editor).
render_markdown_html() { pandoc -f markdown-raw_html -t html5 --mathml 2>/dev/null; }
require_method() {  # require_method <METHOD>
  [[ "${REQUEST_METHOD:-GET}" == "$1" ]] || fail 405 "Use $1" "method_not_allowed"
}

# audit_log <action> <details> — registra ação administrativa (treino) com quem fez.
# Formato tab-sep: epoch \t admin_login \t action \t details
audit_log() {
  local who="${SESSION_LOGIN:-?}" det="${2//$'\t'/ }"
  det="${det//$'\n'/ }"
  mkdir -p "$CONTESTSDIR/treino/var" 2>/dev/null
  printf '%s\t%s\t%s\t%s\n' "$EPOCHSECONDS" "$who" "$1" "$det" \
    >> "$CONTESTSDIR/treino/var/admin-audit.log" 2>/dev/null || true
}

# activity_log <event> <details> — LOG DE ATIVIDADE do treino: eventos de LEITURA
# (problem-view, log-view, source-download) que escalam com page-view. SEPARADO do
# admin-audit (dominado por report de máquina) e ROTACIONADO POR MÊS no próprio nome
# (var/activity-YYYY-MM.log). TSV: epoch \t login("anon" sem sessão) \t event \t details \t ip.
# Consumido pelo feed /treino/admin/activity-log (kind=read). Evento novo de leitura na
# plataforma ⇒ instrumente com ESTE helper.
activity_log() {
  local who="${SESSION_LOGIN:-anon}" det="${2//$'\t'/ }" ym ip="-"
  det="${det//$'\n'/ }"
  printf -v ym '%(%Y-%m)T' "$EPOCHSECONDS"
  declare -F client_ip >/dev/null 2>&1 && ip="$(client_ip)"
  mkdir -p "$CONTESTSDIR/treino/var" 2>/dev/null
  printf '%s\t%s\t%s\t%s\t%s\n' "$EPOCHSECONDS" "$who" "$1" "$det" "${ip:--}" \
    >> "$CONTESTSDIR/treino/var/activity-$ym.log" 2>/dev/null || true
}

# audit_log_to <contest> <action> <details> — auditoria de um contest específico
# (contests/<contest>/var/admin-audit.log). Usado pelas ações do admin do contest.
audit_log_to() {
  local c="$1" who="${SESSION_LOGIN:-?}" det="${3//$'\t'/ }"
  det="${det//$'\n'/ }"
  valid_id "$c" || return 0
  mkdir -p "$CONTESTSDIR/$c/var" 2>/dev/null
  printf '%s\t%s\t%s\t%s\n' "$EPOCHSECONDS" "$who" "$2" "$det" \
    >> "$CONTESTSDIR/$c/var/admin-audit.log" 2>/dev/null || true
}
