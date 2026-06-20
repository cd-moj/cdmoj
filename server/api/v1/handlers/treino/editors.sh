# GET /treino/editors -> ranking dos editores favoritos declarados pelos usuários.
# -> {success:true, editors:[{editor,count} ...ordenado desc], total}
emit_json 200 OK
set +o noglob; shopt -s nullglob
files=("$CONTESTSDIR/treino/var/profiles/"*.json)
shopt -u nullglob
if (( ${#files[@]} == 0 )); then jq -cn '{success:true, editors:[], total:0}'; exit 0; fi
jq -s '
  [ .[] | .favorite_editor? // empty | select(type=="string" and . != "") ]
  | length as $tot
  | (group_by(.) | map({editor: .[0], count: length}) | sort_by(-.count))
  | {success:true, editors:., total:$tot}
' "${files[@]}" 2>/dev/null || jq -cn '{success:true, editors:[], total:0}'
