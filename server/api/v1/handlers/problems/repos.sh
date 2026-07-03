# GET /problems/repos   (Bearer)
# ORGS de que o autor é membro (o "diretório" <org> do id onde ele pode criar problemas), inclui a
# implícita <login> — p/ o seletor de diretório do editor. (Modelo MOJ-nativo: o diretório é a org.)
require_method GET
require_auth
source "$_DIR/lib/orgs.sh"
ensure_implicit_org "$SESSION_LOGIN"
mine="$(org_list_for "$SESSION_LOGIN")"; [[ -n "$mine" ]] || mine='[]'
reg="$(cat "$ORGS_REGISTRY" 2>/dev/null)"; [[ -n "$reg" ]] || reg='{}'
emit_json 200 OK
jq -cn --argjson reg "$reg" --argjson mine "$mine" --arg me "$SESSION_LOGIN" '
  { success:true,
    repos: [ $mine[] as $n | ($reg[$n] // {}) as $o
      | { repo:$n, owner:($o.created_by // $me),
          collaborators:(($o.members // []) - [($o.created_by // $me)]),
          collections:[], public_allowed:($o.public_allowed // false),
          implicit:($o.implicit // false), mine:(($o.created_by // "")==$me) } ]
      | sort_by(.implicit, .repo) }'
