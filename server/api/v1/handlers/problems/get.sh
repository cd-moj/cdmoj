# GET /problems/get?id=<id>   (Bearer)
# Detalhe de um problema: metadados do índice + relatório de validação + enunciado HTML
# (do índice público do treino, quando houver) com tl/tags.
require_method GET
require_auth
source "$_DIR/lib/problems.sh"
id="$(param id)"
[[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
require_problem_view "$id"   # privado só p/ dono/colaborador (corta na API; não revela a existência)
base="$(owners_merged | jq -c --arg id "$id" 'first(.problems[]|select(.id==$id)) // empty' 2>/dev/null)"
[[ -n "$base" ]] || base="$(jq -cn --arg id "$id" '{id:$id, unknown:true}')"

vf="$RUNDIR/validation/$id.json"; val='null'; [[ -f "$vf" ]] && val="$(cat "$vf" 2>/dev/null)"
[[ -n "$val" ]] || val='null'

jf="$CONTESTSDIR/treino/var/jsons/$id.json"
emit_json 200 OK
if [[ -f "$jf" ]]; then
  jq -c --argjson base "$base" --argjson val "$val" '
    {success:true} + $base
    + { validation:$val,
        statement_html_b64:(.statement_html_b64 // null),
        time_limits:(.time_limits // {}),
        tags:(.tags // []) }' "$jf" 2>/dev/null
else
  jq -cn --argjson base "$base" --argjson val "$val" '{success:true} + $base + {validation:$val}'
fi
