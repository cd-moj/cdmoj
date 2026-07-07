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
# .cstaff (chefe de staff de uma sede) NÃO herda .staff: ele VÊ (etiquetas com senha, fila de
# staff, cerimônia de revelação da sede) mas não AGE — handlers testam is_cstaff explicitamente.
is_cstaff(){ [[ "$SESSION_LOGIN" == *.cstaff ]]; }
is_mon(){ [[ "$SESSION_LOGIN" == *.mon ]]; }
# is_reserved_role_login <login> — 0 se o login termina num SUFIXO DE PAPEL reservado. Helper
# central p/ (a) o auto-cadastro NUNCA criar papel por sufixo (signup web/bot) e (b) os handlers
# de admin de contest NÃO tratarem conta privilegiada como aluno (disable/troca de senha em massa/
# logout em massa). NÃO trava o /admin/adduser (admin autenticado cria .judge/.staff de um contest
# legitimamente). Mantém a lista em UM lugar (awk não enxerga a função — ao replicar em regex,
# lembre do .cjudge/.cstaff: \.(admin|judge|cjudge|staff|cstaff|mon)$).
is_reserved_role_login(){ case "$1" in *.admin|*.judge|*.cjudge|*.staff|*.cstaff|*.mon) return 0;; *) return 1;; esac; }
require_admin(){ require_auth; is_admin || fail 403 "Admin only" "admin_required"; }
require_judge(){ require_auth; is_judge || fail 403 "Judge only" "judge_required"; }
require_chief(){ require_auth; is_chief || fail 403 "Chief judge only" "chief_required"; }

# _users_source <contest> — fonte dos usuários: USERS_FROM do conf (ex.: treino) se válido,
# senão o próprio contest. Lido com grep (NÃO faz source do conf no caminho de auth).
_users_source() {
  local c="$1" line src
  line="$(grep -m1 '^USERS_FROM=' "$CONTESTSDIR/$c/conf" 2>/dev/null)"
  src="${line#USERS_FROM=}"; src="${src%\'}"; src="${src#\'}"; src="${src%\"}"; src="${src#\"}"
  if [[ -n "$src" ]] && valid_id "$src" && [[ "$src" != "$c" ]] && [[ -d "$CONTESTSDIR/$src/users" ]]; then
    printf '%s' "$src"
  else printf '%s' "$c"; fi
}

# verify_password <contest> <login> <pass> — confere o users/<login>/account.json do PRÓPRIO
# contest (O(1)) e, se houver USERS_FROM, cai para a fonte compartilhada (ex.: treino).
# valid_id no login ANTES de montar caminho (input do usuário — sem traversal). Senha com
# prefixo '!' = conta desativada (o literal nunca casa com o que o usuário digita).
verify_password() {
  valid_id "$2" || return 1
  local p
  p="$(jq -r '.password // empty' "$CONTESTSDIR/$1/users/$2/account.json" 2>/dev/null)"
  [[ -n "$p" && "$p" == "$3" ]] && return 0
  local src; src="$(_users_source "$1")"
  [[ "$src" != "$1" ]] || return 1
  p="$(jq -r '.password // empty' "$CONTESTSDIR/$src/users/$2/account.json" 2>/dev/null)"
  [[ -n "$p" && "$p" == "$3" ]]
}
user_fullname() {  # <contest> <login> — account.json próprio primeiro, depois USERS_FROM
  valid_id "$2" || return 1
  local n; n="$(jq -r '.fullname // empty' "$CONTESTSDIR/$1/users/$2/account.json" 2>/dev/null)"
  [[ -n "$n" ]] && { printf '%s' "$n"; return; }
  local src; src="$(_users_source "$1")"
  [[ "$src" != "$1" ]] && jq -r '.fullname // empty' "$CONTESTSDIR/$src/users/$2/account.json" 2>/dev/null
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
