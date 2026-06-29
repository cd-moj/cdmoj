# lib/auth.sh — sessões por token (Bearer), guardadas em $SESSIONDIR (modo 700).
# Padrão: header `Authorization: Bearer <token>` (HTTP_AUTHORIZATION).
# Compat: aceita header não-padrão `Bearer: <token>` (HTTP_BEARER) do sistema antigo.

_bearer_token() {
  local a="${HTTP_AUTHORIZATION:-}"
  if [[ "$a" == "Bearer "* ]]; then printf '%s' "${a#Bearer }"; return; fi
  printf '%s' "${HTTP_BEARER:-}"
}

SESSION_TOKEN=""; SESSION_CONTEST=""; SESSION_LOGIN=""; SESSION_NAME=""; SESSION_AT=""

# load_session -> 0 se autenticado (popula SESSION_*), 1 caso contrário.
load_session() {
  SESSION_TOKEN="$(_bearer_token)"
  [[ -n "$SESSION_TOKEN" ]] || return 1
  valid_id "$SESSION_TOKEN" || return 1
  local f="$SESSIONDIR/$SESSION_TOKEN"
  [[ -f "$f" ]] || return 1
  local CONTEST="" LOGIN="" USERFULLNAME="" LOGINAT=""
  source "$f"
  SESSION_CONTEST="$CONTEST"; SESSION_LOGIN="$LOGIN"
  SESSION_NAME="$USERFULLNAME"; SESSION_AT="$LOGINAT"
  [[ -n "$SESSION_LOGIN" ]]
}

require_auth() { load_session || fail 401 "Not authenticated" "auth_required"; }
require_auth_contest() {  # require_auth_contest <contest>
  require_auth
  [[ "$SESSION_CONTEST" == "$1" ]] || fail 403 "Not logged into this contest" "auth_contest"
}

# papéis por substring no username (convenção do MOJ)
is_admin(){ [[ "$SESSION_LOGIN" == *.admin ]]; }
# .cjudge (juiz-chefe) HERDA os poderes de juiz; .admin também é juiz.
is_judge(){ [[ "$SESSION_LOGIN" == *.judge || "$SESSION_LOGIN" == *.cjudge || "$SESSION_LOGIN" == *.admin ]]; }
is_chief(){ [[ "$SESSION_LOGIN" == *.cjudge ]]; }
is_admin_or_chief(){ is_admin || is_chief; }
is_staff(){ [[ "$SESSION_LOGIN" == *.staff ]]; }
is_mon(){ [[ "$SESSION_LOGIN" == *.mon ]]; }
require_admin(){ require_auth; is_admin || fail 403 "Admin only" "admin_required"; }
require_judge(){ require_auth; is_judge || fail 403 "Judge only" "judge_required"; }
require_chief(){ require_auth; is_chief || fail 403 "Chief judge only" "chief_required"; }

# _users_source <contest> — fonte dos usuários: USERS_FROM do conf (ex.: treino) se válido,
# senão o próprio contest. Lido com grep (NÃO faz source do conf no caminho de auth).
_users_source() {
  local c="$1" line src
  line="$(grep -m1 '^USERS_FROM=' "$CONTESTSDIR/$c/conf" 2>/dev/null)"
  src="${line#USERS_FROM=}"; src="${src%\'}"; src="${src#\'}"; src="${src%\"}"; src="${src#\"}"
  if [[ -n "$src" ]] && valid_id "$src" && [[ "$src" != "$c" ]] && [[ -f "$CONTESTSDIR/$src/passwd" ]]; then
    printf '%s' "$src"
  else printf '%s' "$c"; fi
}

# verify_password <contest> <login> <pass> — confere o passwd do PRÓPRIO contest (admin +
# usuários específicos) e, se houver USERS_FROM, cai para o passwd compartilhado (ex.: treino).
verify_password() {
  cut -d: -f1,2 "$CONTESTSDIR/$1/passwd" 2>/dev/null | grep -qxF -- "$2:$3" && return 0
  local src; src="$(_users_source "$1")"
  [[ "$src" != "$1" ]] || return 1
  cut -d: -f1,2 "$CONTESTSDIR/$src/passwd" 2>/dev/null | grep -qxF -- "$2:$3"
}
user_fullname() {  # <contest> <login> — passwd próprio primeiro, depois USERS_FROM
  local n; n="$(awk -F: -v u="$2" '$1==u{print $3; exit}' "$CONTESTSDIR/$1/passwd" 2>/dev/null)"
  [[ -n "$n" ]] && { printf '%s' "$n"; return; }
  local src; src="$(_users_source "$1")"
  [[ "$src" != "$1" ]] && awk -F: -v u="$2" '$1==u{print $3; exit}' "$CONTESTSDIR/$src/passwd" 2>/dev/null
}

# IP do cliente: 1º hop de X-Forwarded-For, senão X-Real-IP/REMOTE_ADDR.
# Sanitizado (só chars de IP) — o arquivo de sessão é "sourced", então nada de metachars.
client_ip(){
  local ip="${HTTP_X_FORWARDED_FOR:-}"; ip="${ip%%,*}"
  [[ -z "$ip" ]] && ip="${HTTP_X_REAL_IP:-${REMOTE_ADDR:-}}"
  printf '%s' "$ip" | tr -cd '0-9a-fA-F.:'
}

# create_session <contest> <login> <name> -> ecoa o token (uuid)
create_session() {
  mkdir -p "$SESSIONDIR"; chmod 700 "$SESSIONDIR" 2>/dev/null
  local uuid; uuid="$(</proc/sys/kernel/random/uuid)"
  local ip ua
  ip="$(client_ip)"
  ua="$(printf '%s' "${HTTP_USER_AGENT:-}" | base64 -w0)"   # b64 p/ não injetar no source
  ( umask 077
    {
      printf 'CONTEST=%q\n'      "$1"
      printf 'LOGIN=%q\n'        "$2"
      printf 'USERFULLNAME=%q\n' "$3"
      printf 'LOGINAT=%q\n'      "$EPOCHSECONDS"
      printf 'IP=%q\n'           "$ip"
      printf 'UA_B64=%q\n'       "$ua"
    } > "$SESSIONDIR/$uuid"
  )
  printf '%s' "$uuid"
}
destroy_session(){ [[ -n "${1:-}" ]] && valid_id "$1" && rm -f "$SESSIONDIR/$1"; }

# remove_contest_sessions <contest> [login] -> ecoa o nº de sessões removidas.
# Sem <login>, remove todas do contest. Usado por deslogar/desabilitar usuário.
remove_contest_sessions(){
  local c="$1" want="${2:-}" n=0 f CONTEST LOGIN
  set +o noglob; shopt -s nullglob
  for f in "$SESSIONDIR"/*; do
    [[ -f "$f" ]] || continue
    CONTEST=""; LOGIN=""; source "$f" 2>/dev/null
    [[ "$CONTEST" == "$c" ]] || continue
    [[ -z "$want" || "$LOGIN" == "$want" ]] || continue
    rm -f "$f"; ((n++))
  done
  shopt -u nullglob
  printf '%s' "$n"
}
