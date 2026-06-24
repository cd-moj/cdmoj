# POST /problems/git-credential   (Bearer)   body: {repo}
# Credencial HTTPS efêmera p/ o CLI rodar UM git clone/push do diretório, SEM chave SSH.
# Só p/ quem pode escrever no repo. O cliente NÃO deve persistir o token (usa via askpass,
# um comando, e descarta). Modo avançado: requer que o Gitea seja alcançável pelo cliente.
require_method POST
require_auth
source "$_DIR/lib/gitea.sh"; source "$_DIR/lib/problems.sh"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
repo="$(jq -r '.repo // empty' <<<"$body")"
[[ "$repo" =~ ^[a-z0-9][a-z0-9._-]{1,63}$ ]] || fail 400 "Diretório inválido" "repo_invalid"
owner="$(repo_owner "$repo")"; [[ -n "$owner" ]] || fail 404 "Diretório não existe no Gitea" "repo_missing"
gitea_can_write "$owner" "$repo" "$SESSION_LOGIN" || fail 403 "Sem permissão de escrita" "forbidden"

tok="$(gitea_ensure_user_token "$SESSION_LOGIN")"; [[ -n "$tok" ]] || fail 502 "Falha ao emitir credencial" "token_fail"
url="${GITEA_PUBLIC_URL%/}/$owner/$repo.git"
audit_log "git-credential" "repo=$repo by=$SESSION_LOGIN"
ok_json '{repo:$r, owner:$o, url:$u, username:$un, token:$t, scheme:"http-basic",
          hint:"use via askpass; não persista o token"}' \
  --arg r "$repo" --arg o "$owner" --arg u "$url" --arg un "$SESSION_LOGIN" --arg t "$tok"
