# GET /orgs/list  (Bearer) -> ORGS de que o login é membro/admin (inclui a IMPLÍCITA <login>, criada
# aqui se faltar), com contagem de problemas (visíveis ao login) e flags de gestão. NÃO lista orgs de
# que o login não participa (não vaza a existência de cursos alheios).
require_method GET
require_auth
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"
ensure_implicit_org "$SESSION_LOGIN"
mine="$(org_list_for "$SESSION_LOGIN")"; [[ -n "$mine" ]] || mine='[]'
reg="$(cat "$ORGS_REGISTRY" 2>/dev/null)"; [[ -n "$reg" ]] || reg='{}'
gadm=false; is_admin && gadm=true
emit_json 200 OK
owners_merged | jq -c --argjson reg "$reg" --argjson mine "$mine" --arg me "$SESSION_LOGIN" --argjson gadm "$gadm" '
  ( [ .problems[] | select(.public or .owner==$me or ((.collaborators // [])|index($me)|type=="number")
        or (((.repo // (.id|split("#")[0])) as $r | $mine|index($r))|type=="number"))
      | {org:(.id|split("#")[0]), pub:.public} ] | group_by(.org)
    | map({key:.[0].org, value:{count:length, public:([.[]|select(.pub)]|length)}}) | from_entries ) as $cnt
  | { success:true,
      orgs: [ $mine[] as $n | ($reg[$n] // {}) as $o
              | { name:$n, title:($o.title // $n),
                  members:($o.members // []), admins:($o.admins // []),
                  public_allowed:($o.public_allowed // false), implicit:($o.implicit // false),
                  count:(($cnt[$n].count) // 0), public:(($cnt[$n].public) // 0),
                  mine:(($o.created_by // "")==$me),
                  can_manage:( (($o.admins // [])|index($me)|type=="number") or $gadm ) } ]
        | sort_by(.implicit, .name) }' 2>/dev/null \
  || jq -cn '{success:true, orgs:[]}'
