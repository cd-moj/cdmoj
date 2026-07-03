# POST /problems/delete   (Bearer)   body: {id, confirm}
# REMOVE um problema: apaga o repo git LOCAL da org (MOJ_PROBLEMS_DIR/<org>/<prob>) + o treino +
# índices. DESTRUTIVO: `confirm` tem de repetir EXATAMENTE o id. Só MEMBRO da org (senão 404).
require_method POST
require_auth
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
confirm="$(jq -r '.confirm // empty' <<<"$body")"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
org="${id%%#*}"; prob="${id##*#}"; [[ "$prob" != "$id" ]] || fail 400 "Id sem '#'" "id_invalid"
[[ "$confirm" == "$id" ]] || fail 400 "Confirmação inválida — repita exatamente o id ($id) para remover" "confirm_mismatch"
require_problem_edit "$id"
pdir="$MOJ_PROBLEMS_DIR/$org/$prob"; [[ -d "$pdir" ]] || fail 404 "Problema não existe" "prob_missing"

# apaga o repo local + tira do treino + artefatos/índices (visibilidade IMEDIATA)
rm -rf "$pdir" 2>/dev/null
rm -f "$CONTESTSDIR/treino/var/jsons/$id.json" "$CONTESTSDIR/treino/var/jsons-private/$id.json" 2>/dev/null
rm -f "$RUNDIR/validation/$id.json" 2>/dev/null
authored_remove "$id"
( MOJ_PROBLEMS_DIR="$MOJ_PROBLEMS_DIR" CONTESTSDIR="$CONTESTSDIR" \
    setsid bash "$MOJTOOLS_DIR/gen-problem-owners.sh" >/dev/null 2>&1 & ) 2>/dev/null
audit_log "delete" "id=$id by=$SESSION_LOGIN"
ok_json '{action:"delete", id:$id}' --arg id "$id"
