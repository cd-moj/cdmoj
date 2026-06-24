# POST /problems/repo-create   (Bearer)   body: {repo, collections?:[...]}
# Cria um "diretório" = repo Gitea sob o namespace do autor (login do MOJ). Sem chave/git:
# o servidor provisiona o usuário Gitea (lazy) e o repo. Nome global único (não colide com
# repos legados nem com diretório de outro dono).
require_method POST
require_auth
source "$_DIR/lib/gitea.sh"; source "$_DIR/lib/problems.sh"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
repo="$(jq -r '.repo // empty' <<<"$body")"
[[ "$repo" =~ ^[a-z0-9][a-z0-9._-]{1,63}$ ]] || fail 400 "Nome de diretório inválido (use [a-z0-9._-])" "repo_invalid"
[[ -d "$MOJ_PROBLEMS_DIR/$repo" ]] && fail 409 "Já existe um repositório legado com esse nome" "repo_legacy"
exist="$(repo_owner "$repo")"
[[ -n "$exist" && "$exist" != "$SESSION_LOGIN" ]] && fail 409 "Diretório já existe (dono: $exist)" "repo_taken"

gitea_ensure_user "$SESSION_LOGIN" "$SESSION_NAME" "$SESSION_LOGIN@moj.local" || fail 502 "Falha ao provisionar usuário Gitea" "gitea_user"
gitea_ensure_repo "$SESSION_LOGIN" "$repo" || fail 502 "Falha ao criar o repositório" "gitea_repo"
gitea_ensure_webhook "$SESSION_LOGIN" "$repo" 2>/dev/null || true   # push -> reindex (best-effort)
colls="$(jq -r '(.collections // []) | join(",")' <<<"$body")"
repo_register "$repo" "$SESSION_LOGIN" "$colls"
audit_log "repo-create" "repo=$repo owner=$SESSION_LOGIN"
ok_json '{action:"repo-create", repo:$r, owner:$o, collections:$c}' \
  --arg r "$repo" --arg o "$SESSION_LOGIN" --argjson c "$(jq -c '.collections // []' <<<"$body")"
