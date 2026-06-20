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
: "${DEFAULT_SCORE_MODE:=icpc}"

# --- resposta (CGI) -------------------------------------------------------
# CGI: emitimos "Status:" (fcgiwrap/nginx traduzem p/ status HTTP) + Content-Type.
respond() {  # respond <code> <reason> <content-type>
  printf 'Status: %s %s\r\n' "${1:-200}" "${2:-OK}"
  printf 'Content-Type: %s\r\n' "${3:-application/json; charset=utf-8}"
  printf '\r\n'
}
emit_json(){ respond "${1:-200}" "${2:-OK}" "application/json; charset=utf-8"; }
emit_text(){ respond "${1:-200}" "${2:-OK}" "text/plain; charset=utf-8"; }

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
