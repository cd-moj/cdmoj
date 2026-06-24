# lib/gitea.sh — integração com o Gitea (store git + motor de permissão da gestão de
# problemas). Wrappers curl que usam o TOKEN ADMIN server-side (modo 600). NUNCA ecoa
# segredos. O autor só apresenta a sessão do MOJ; aqui traduzimos isso em ações no Gitea.
: "${RUNDIR:=/home/ribas/moj/run}"
: "${GITEA_URL:=http://localhost:3939}"
: "${GITEA_ADMIN_TOKEN_FILE:=$RUNDIR/secrets/gitea-admin.token}"
: "${GITEA_USER_TOKENS_DIR:=$RUNDIR/secrets/gitea-user-tokens}"
: "${GITEA_BIN:=$RUNDIR/gitea/gitea}"
: "${GITEA_CONFIG:=$RUNDIR/gitea/custom/conf/app.ini}"
: "${GITEA_WORK_DIR:=$RUNDIR/gitea}"

_gitea_admin_token(){ [[ -f "$GITEA_ADMIN_TOKEN_FILE" ]] && cat "$GITEA_ADMIN_TOKEN_FILE"; }
# _gitea_cli <args...> — roda o binário do Gitea (mesmo OS user) com config/workdir corretos
_gitea_cli(){ GITEA_WORK_DIR="$GITEA_WORK_DIR" "$GITEA_BIN" -c "$GITEA_CONFIG" "$@"; }
_gitea_valid_login(){ [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && [[ "$1" != *..* ]]; }

# gitea_api <method> <path> [json-body] -> corpo no stdout; código HTTP em $GITEA_HTTP
gitea_api(){
  local m="$1" p="$2" body="${3:-}" tok t; tok="$(_gitea_admin_token)"
  t="$(mktemp)"
  if [[ -n "$body" ]]; then
    GITEA_HTTP="$(curl -sS -o "$t" -w '%{http_code}' -X "$m" -H "Authorization: token $tok" \
      -H 'Content-Type: application/json' --data "$body" "$GITEA_URL/api/v1$p" 2>/dev/null)"
  else
    GITEA_HTTP="$(curl -sS -o "$t" -w '%{http_code}' -X "$m" -H "Authorization: token $tok" \
      "$GITEA_URL/api/v1$p" 2>/dev/null)"
  fi
  cat "$t"; rm -f "$t"
}

# gitea_sudo_api <login> <method> <path> [body] — age COMO o usuário (commit/token autorado por ele)
gitea_sudo_api(){
  local login="$1" m="$2" p="$3" body="${4:-}" tok; tok="$(_gitea_admin_token)"
  local args=(-sS -X "$m" -H "Authorization: token $tok" -H "Sudo: $login")
  [[ -n "$body" ]] && args+=(-H 'Content-Type: application/json' --data "$body")
  curl "${args[@]}" "$GITEA_URL/api/v1$p" 2>/dev/null
}

# gitea_ensure_user <login> [fullname] [email] — cria se não existir (idempotente, lazy)
gitea_ensure_user(){
  local login="$1" name="${2:-$1}" email="${3:-$1@moj.local}"
  _gitea_valid_login "$login" || return 1
  gitea_api GET "/users/$login" >/dev/null
  [[ "$GITEA_HTTP" == 200 ]] && return 0
  local pass; pass="$(head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')Aa1.moj"
  gitea_api POST "/admin/users" "$(jq -cn --arg u "$login" --arg n "$name" --arg e "$email" --arg p "$pass" \
    '{username:$u, full_name:$n, email:$e, password:$p, must_change_password:false}')" >/dev/null
  [[ "$GITEA_HTTP" =~ ^2 ]]
}

# gitea_ensure_user_token <login> — provisiona/reusa o token HTTPS do usuário (git); cacheia 600.
# Mint via CLI do Gitea (a API /tokens exige BasicAuth/senha — que NÃO guardamos; o CLI opera
# no DB sem senha, keyless). Ecoa o token (senha HTTPS); nunca vai p/ .git/config (git-broker.sh).
gitea_ensure_user_token(){
  local login="$1" f                       # f em linha à parte: $login só existe após o assign
  f="$GITEA_USER_TOKENS_DIR/$login"
  _gitea_valid_login "$login" || return 1
  [[ -s "$f" ]] && { cat "$f"; return 0; }
  mkdir -p "$GITEA_USER_TOKENS_DIR" 2>/dev/null; chmod 700 "$GITEA_USER_TOKENS_DIR" 2>/dev/null
  local out tok name="moj-git-$EPOCHSECONDS-$RANDOM"
  out="$(_gitea_cli admin user generate-access-token --username "$login" \
    --token-name "$name" --scopes write:repository 2>/dev/null)"
  tok="$(grep -oE '[a-f0-9]{40}' <<<"$out" | head -1)"
  [[ -n "$tok" ]] || return 1
  ( umask 077; printf '%s' "$tok" > "$f" )
  printf '%s' "$tok"
}
# gitea_user_token_clear <login> — invalida o cache local (re-mint no próximo uso)
gitea_user_token_clear(){ rm -f "$GITEA_USER_TOKENS_DIR/$1" 2>/dev/null; }

# gitea_ensure_repo <owner> <repo> — cria repo do usuário se não existir (auto-init).
gitea_ensure_repo(){
  local owner="$1" repo="$2"
  _gitea_valid_login "$owner" || return 1
  gitea_api GET "/repos/$owner/$repo" >/dev/null
  [[ "$GITEA_HTTP" == 200 ]] && return 0
  gitea_sudo_api "$owner" POST "/user/repos" \
    "$(jq -cn --arg n "$repo" '{name:$n, private:true, auto_init:true, default_branch:"master"}')" >/dev/null
  gitea_api GET "/repos/$owner/$repo" >/dev/null; [[ "$GITEA_HTTP" == 200 ]]
}

# gitea_set_collaborator <owner> <repo> <user> <write|read|admin>
gitea_set_collaborator(){
  gitea_api PUT "/repos/$1/$2/collaborators/$3" "$(jq -cn --arg p "${4:-write}" '{permission:$p}')" >/dev/null
  [[ "$GITEA_HTTP" =~ ^2 ]]
}
gitea_rm_collaborator(){ gitea_api DELETE "/repos/$1/$2/collaborators/$3" >/dev/null; [[ "$GITEA_HTTP" =~ ^2 ]]; }

# gitea_can_write <owner> <repo> <login> — 0 se login pode escrever no repo (owner/collab/admin)
gitea_can_write(){
  [[ "$1" == "$3" ]] && return 0
  local perm; perm="$(gitea_api GET "/repos/$1/$2/collaborators/$3/permission" | jq -r '.permission // "none"' 2>/dev/null)"
  [[ "$perm" == write || "$perm" == admin || "$perm" == owner ]]
}
