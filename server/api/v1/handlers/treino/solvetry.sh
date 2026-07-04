# GET /treino/solvetry[?user=<login>]   -> {solved:[ids], attempted:[ids]}
# Sem ?user usa o usuário logado. Calcula a partir do history do usuário.
user="$(param user)"
if [[ -z "$user" ]]; then load_session && user="$SESSION_LOGIN"; fi
[[ -n "$user" ]] || fail 400 "Missing user" "user_missing"
valid_id "$user" || fail 400 "Invalid user" "user_invalid"

emit_json 200 OK
# users/<user>/history — emit_user_history normaliza p/ 7 campos.
emit_user_history treino "$user" \
| awk -F: '
  { if ($5 ~ /^Accepted/) s[$3]=1; else a[$3]=1 }
  END { for (k in s) print "S\t" k; for (k in a) if (!(k in s)) print "A\t" k }
' \
| jq -R -s -c '
    split("\n") | map(select(length>0))
    | reduce .[] as $l ({solved:[], attempted:[]};
        ($l|split("\t")) as $p
        | if $p[0]=="S" then .solved += [$p[1]] else .attempted += [$p[1]] end)
    | {success:true} + .'
