# GET /treino/problem?id=<problem-id>
# Retorna o JSON do problema: {id, title, statement_html_b64, time_limits, tags}
id="$(param id)"
[[ -n "$id" ]] || fail 400 "Missing problem id" "id_missing"
valid_id "$id" || fail 400 "Invalid problem id" "id_invalid"
f="$CONTESTSDIR/treino/var/jsons/$id.json"
[[ -f "$f" ]] || fail 404 "Problem not found" "problem_notfound"
emit_json 200 OK
jq -c '{success:true} + .' "$f"
