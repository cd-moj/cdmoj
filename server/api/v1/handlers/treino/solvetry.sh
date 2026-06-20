# GET /treino/solvetry[?user=<login>]   -> {solved:[ids], attempted:[ids]}
# Sem ?user usa o usuário logado. Calcula a partir de controle/history.
user="$(param user)"
if [[ -z "$user" ]]; then load_session && user="$SESSION_LOGIN"; fi
[[ -n "$user" ]] || fail 400 "Missing user" "user_missing"
valid_id "$user" || fail 400 "Invalid user" "user_invalid"

hist="$CONTESTSDIR/treino/controle/history"
emit_json 200 OK
[[ -f "$hist" ]] || { jq -cn '{success:true, solved:[], attempted:[]}'; exit 0; }

awk -F: -v u="$user" '
  $2==u { if ($5 ~ /^Accepted/) s[$3]=1; else a[$3]=1 }
  END { for (k in s) print "S\t" k; for (k in a) if (!(k in s)) print "A\t" k }
' "$hist" \
| jq -R -s -c '
    split("\n") | map(select(length>0))
    | reduce .[] as $l ({solved:[], attempted:[]};
        ($l|split("\t")) as $p
        | if $p[0]=="S" then .solved += [$p[1]] else .attempted += [$p[1]] end)
    | {success:true} + .'
