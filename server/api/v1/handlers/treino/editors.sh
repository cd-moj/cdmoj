# GET /treino/editors -> ranking dos editores favoritos declarados pelos usuários
# (campo favorite_editor dos account.json). Batch find|xargs (sem ARG_MAX).
# -> {success:true, editors:[{editor,count} ...ordenado desc], total}
emit_json 200 OK
out="$(find "$CONTESTSDIR/treino/users" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
  | xargs -0 -r jq -r '.favorite_editor? // empty | select(type=="string" and . != "")' 2>/dev/null \
  | jq -R -s '
      split("\n") | map(select(length>0))
      | length as $tot
      | (group_by(.) | map({editor: .[0], count: length}) | sort_by(-.count))
      | {success:true, editors:., total:$tot}')"
[[ -n "$out" ]] && printf '%s\n' "$out" || jq -cn '{success:true, editors:[], total:0}'
