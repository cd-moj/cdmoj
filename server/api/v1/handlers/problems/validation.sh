# GET /problems/validation?id=<id>   (Bearer)
# Devolve o último relatório de validação do problema (checks + ok + render_warnings).
require_method GET
require_auth
: "${RUNDIR:=/home/ribas/moj/run}"

id="$(param id)"
[[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"

f="$RUNDIR/validation/$id.json"
emit_json 200 OK
if [[ -f "$f" ]]; then
  jq -c '{success:true} + .' "$f"
else
  jq -cn --arg i "$id" '{success:true, id:$i, status:"unvalidated"}'
fi
