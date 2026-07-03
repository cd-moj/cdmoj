# GET /problems/collections   (Bearer)
# Lista as COLEÇÕES = ORGS de que o login participa (inclui a implícita), com contagem total/pública.
# Modelo MOJ-nativo: a coleção É a org. Alias de /orgs/list no formato antigo {collections:[...]}.
require_method GET
require_auth
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"
ensure_implicit_org "$SESSION_LOGIN"
mine="$(org_list_for "$SESSION_LOGIN")"; [[ -n "$mine" ]] || mine='[]'
reg="$(cat "$ORGS_REGISTRY" 2>/dev/null)"; [[ -n "$reg" ]] || reg='{}'
gadm=false; is_admin && gadm=true
emit_json 200 OK
owners_merged | jq -c --argjson reg "$reg" --argjson mine "$mine" --arg me "$SESSION_LOGIN" --argjson gadm "$gadm" '
  ( [ .problems[] | select(.public or .owner==$me or ((.collaborators // [])|index($me)|type=="number"))
      | {org:(.id|split("#")[0]), pub:.public} ] | group_by(.org)
    | map({key:.[0].org, value:{count:length, public:([.[]|select(.pub)]|length)}}) | from_entries ) as $cnt
  | { success:true,
      collections: [ $mine[] as $n | ($reg[$n] // {}) as $o
        | { name:$n, title:($o.title // $n), count:(($cnt[$n].count) // 0), public:(($cnt[$n].public) // 0),
            owner:($o.created_by // null), members:($o.members // []), admins:($o.admins // []),
            public_allowed:($o.public_allowed // false), implicit:($o.implicit // false),
            repo_course:false, mine:(($o.created_by // "")==$me),
            can_manage:( (($o.admins // [])|index($me)|type=="number") or $gadm ) } ]
        | sort_by(.implicit, -.count) }' 2>/dev/null || jq -cn '{success:true, collections:[]}'
