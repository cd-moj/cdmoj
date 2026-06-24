# GET /problems/collections   (Bearer)
# Lista as coleções (competição/curso) com contagem total/pública + dono e membros (grupo de
# setters) do registro. Inclui coleções recém-criadas mesmo sem problemas ainda.
require_method GET
require_auth
source "$_DIR/lib/problems.sh"
reg="$(cat "$COLLECTIONS_REGISTRY" 2>/dev/null)"; [[ -n "$reg" ]] || reg='{}'
gadm=false; is_admin && gadm=true
emit_json 200 OK
owners_merged | jq -c --argjson reg "$reg" --arg me "$SESSION_LOGIN" --argjson gadm "$gadm" '
  ( [ .problems[] | {c:.collections[], pub:.public} ] | group_by(.c)
    | map({name:.[0].c, count:length, public:([.[]|select(.pub)]|length)}) ) as $fromp
  | ($fromp | map(.name)) as $names
  | ( $reg | to_entries | map(select((.key|IN($names[]))|not) | {name:.key, count:0, public:0}) ) as $empty
  | { success:true,
      collections: ( ($fromp + $empty)
        | map( ($reg[.name] // {}) as $r
          | . + { owner:($r.owner // null), members:($r.members // []), admins:($r.admins // []),
                  title:($r.title // .name), mine:(($r.owner // "")==$me),
                  can_manage:( (($r.owner // "")==$me) or (($r.admins // [])|index($me)|type=="number") or $gadm ) })
        | sort_by(-.count) ) }' 2>/dev/null || jq -cn '{success:true, collections:[]}'
