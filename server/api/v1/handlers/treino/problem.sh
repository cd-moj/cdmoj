# GET /treino/problem?id=<problem-id>
# Retorna o JSON do problema: {id, title, author, statement_html_b64, time_limits, tags}
id="$(param id)"
[[ -n "$id" ]] || fail 400 "Missing problem id" "id_missing"
valid_id "$id" || fail 400 "Invalid problem id" "id_invalid"
f="$CONTESTSDIR/treino/var/jsons/$id.json"
[[ -f "$f" ]] || fail 404 "Problem not found" "problem_notfound"
# 3ª camada anti-vazamento: esta rota é ANÔNIMA e serve o ENUNCIADO INTEIRO. Estar em var/jsons/ já
# deveria significar "público" (é o gerador quem decide), mas um bug do gerador já vazou prova em
# elaboração p/ a internet — então quem serve também confere. `!= false` (e não `== true`) de
# propósito: json legado sem o campo passa; só o explicitamente privado é barrado.
jq -e '.public != false' "$f" >/dev/null 2>&1 || fail 404 "Problem not found" "problem_notfound"
emit_json 200 OK
jq -c '{success:true} + .' "$f"
