# GET /problems/collections   (Bearer)
# Lista as COLEÇÕES (tags CURADAS do registro) com contagem de problemas VISÍVEIS ao login. Coleção é
# só um rótulo de agrupamento (m:n), ORTOGONAL à ORG (acesso). O nome pode ter espaços. `can_manage` =
# dono da coleção ou admin global.
require_method GET
require_auth
source "$_DIR/lib/problems.sh"
reg="$(cat "$COLL_REGISTRY" 2>/dev/null)"; [[ -n "$reg" ]] || reg='{}'
gadm=false; is_admin && gadm=true
emit_json 200 OK
owners_visible | jq -c --argjson reg "$reg" --arg me "$SESSION_LOGIN" --argjson gadm "$gadm" '
  ( [ .problems[] | {c:(.collections//[])[], pub:.public} ] | group_by(.c)
    | map({key:.[0].c, value:{count:length, public:([.[]|select(.pub)]|length)}}) | from_entries ) as $cnt
  | { success:true,
      collections: [ ($reg|keys[]) as $n | ($reg[$n]) as $r
        | { name:$n, owner:($r.owner // null), count:(($cnt[$n].count)//0), public:(($cnt[$n].public)//0),
            mine:(($r.owner // "")==$me), can_manage:( (($r.owner // "")==$me) or $gadm ) } ]
        | sort_by(-.count, (.name|ascii_downcase)) }' 2>/dev/null || jq -cn '{success:true, collections:[]}'
