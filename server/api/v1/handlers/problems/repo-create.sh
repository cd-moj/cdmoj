# POST /problems/repo-create   (Bearer)   body: {repo, collections?:[...]}
# Cria/garante uma ORG (o "diretório" <org> do id <org>#<prob>) — registro MOJ-nativo em orgs.json,
# sem Gitea. O criador vira membro+admin. Exige permissão de criação (mesma regra de criar contest).
# (Alias histórico de /orgs/create; o CLI/editor ainda chamam este nome.)
require_method POST
require_auth
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/contest-create.sh"; source "$_DIR/lib/problems.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar (mesma regra de criar contest)" "create_forbidden"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
repo="$(jq -r '.repo // empty' <<<"$body")"
[[ "$repo" =~ ^[a-z0-9][a-z0-9._-]{1,63}$ ]] || fail 400 "Nome de org inválido (use [a-z0-9._-])" "repo_invalid"
if org_exists "$repo"; then org_can_manage "$repo" "$SESSION_LOGIN" || fail 409 "Org já existe" "repo_taken"; fi
org_register "$repo" "$SESSION_LOGIN"
coll_register "$repo" "$SESSION_LOGIN"   # coleção homônima (agrupamento default do id) fica válida
audit_log "repo-create" "org=$repo owner=$SESSION_LOGIN"
ok_json '{action:"repo-create", repo:$r, owner:$o, collections:$c}' \
  --arg r "$repo" --arg o "$SESSION_LOGIN" --argjson c "$(jq -c '.collections // []' <<<"$body")"
