# GET /problems/collections   (Bearer)
# Lista as coleções (competição/curso) com contagem total/pública + dono e membros (grupo de
# setters) do registro. Inclui coleções recém-criadas mesmo sem problemas ainda.
require_method GET
require_auth
source "$_DIR/lib/problems.sh"
reg="$(cat "$COLLECTIONS_REGISTRY" 2>/dev/null)"; [[ -n "$reg" ]] || reg='{}'
rreg="$(cat "$REPO_REGISTRY" 2>/dev/null)"; [[ -n "$rreg" ]] || rreg='{}'
gadm=false; is_admin && gadm=true
emit_json 200 OK
owners_merged | jq -c --argjson reg "$reg" --argjson rreg "$rreg" --arg me "$SESSION_LOGIN" --argjson gadm "$gadm" '
  ( [ .problems[]
      | select(.public or .owner==$me or ((.collaborators // [])|index($me)|type=="number"))  # só conta o que o login PODE ver (não vaza nº de privados)
      | {c:.collections[], pub:.public} ] | group_by(.c)
    | map({name:.[0].c, count:length, public:([.[]|select(.pub)]|length)}) ) as $fromp
  | ($fromp | map(.name)) as $names
  | ( $reg | to_entries | map(select((.key|IN($names[]))|not) | {name:.key, count:0, public:0}) ) as $empty
  | { success:true,
      collections: ( ($fromp + $empty)
        | map( ($reg[.name] // {}) as $r | ($rreg[.name] // null) as $rr
          # Coleção REGISTRADA tem precedência. Senão, se há um repo homônimo, é um "repo-curso":
          # os SETTERS são os colaboradores do repo, o dono é o do repo, e não há co-admins.
          | (if (($r.owner // null) != null)
             then { owner:$r.owner, members:($r.members // []), admins:($r.admins // []), repo_course:false }
             elif $rr != null
             then { owner:($rr.owner // null), members:($rr.collaborators // []), admins:[], repo_course:true }
             else { owner:null, members:[], admins:[], repo_course:false } end) as $g
          | . + { owner:$g.owner, members:$g.members, admins:$g.admins, repo_course:$g.repo_course,
                  title:($r.title // .name), mine:(($g.owner // "")==$me),
                  can_manage:( (($g.owner // "")==$me) or (($g.admins // [])|index($me)|type=="number") or $gadm ) })
        | sort_by(-.count) ) }' 2>/dev/null || jq -cn '{success:true, collections:[]}'
