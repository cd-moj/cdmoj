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
: "${NEWSDIR:=/home/ribas/moj/server/var/news}"
: "${SCOREDIR:=/home/ribas/moj/server/score}"
: "${DEFAULT_SCORE_MODE:=icpc}"
export CONTESTSDIR SCOREDIR   # herdados por sub-processos (ex.: server/score/build.sh)

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
