# GET /problems/repos   (Bearer)
# Diretórios (repos Gitea) que o autor possui ou nos quais é colaborador — p/ o seletor do editor.
require_method GET
require_auth
source "$_DIR/lib/problems.sh"
emit_json 200 OK
if [[ -f "$REPO_REGISTRY" ]]; then
  jq -c --arg me "$SESSION_LOGIN" '
    { success:true,
      repos: [ to_entries[]
        | { repo:.key, owner:.value.owner,
            collaborators:(.value.collaborators // []),
            collections:(.value.collections // []) }
        | select(.owner==$me or (.collaborators|index($me)))
        | . + {mine:(.owner==$me)} ] }' "$REPO_REGISTRY" 2>/dev/null || jq -cn '{success:true, repos:[]}'
else
  jq -cn '{success:true, repos:[]}'
fi
