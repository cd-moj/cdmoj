# GET /problems/tl?id=<id>  (Bearer) -> time_limits ao vivo do problema (store dos juízes) +
# staleness EXATA (recomputa o checksum do pacote AGORA). Espelha /ops/problemtl, mas o acesso é
# dono/colaborador OU público (require_problem_view: 404 se privado e não autorizado), não .admin.
# Ao contrário do /problems/status (stale vem do índice, ≤30 min de atraso), aqui o hash é feito na
# hora — p/ 1 problema — quando se quer o valor fresco/exato.
require_method GET
require_auth
source "$_DIR/lib/problems.sh"
source "$_DIR/lib/tl-store.sh"

id="$(param id)"
[[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
require_problem_view "$id"

cur="$(pkg_tl_checksum "$(pkg_path "$id")")"
emit_json 200 OK
jq -cn --arg p "$id" --arg cks "$cur" \
   --argjson tl "$(tl_store_served_for "$id" "$cur")" \
   --argjson store "$(tl_store_get "$id")" '
   ($store.checksum // "") as $cal
   | (($store.hosts // {}) | length > 0) as $calibrated
   | {success:true, problem:$p, checksum:$cks, time_limits:$tl,
      calibrated_checksum:$cal, hosts:($store.hosts // {}),
      updated_at:($store.updated_at // null), calibrated:$calibrated,
      stale:($cal != $cks and $cal != ""),
      needs_recalibration:($calibrated and $cal != $cks and $cal != "")}'
