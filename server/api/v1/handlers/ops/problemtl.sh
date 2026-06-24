# GET /ops/problemtl?problem=<id>   (Bearer, admin) -> JSON
# Time limits de um problema, do STORE reportado pelos juízes (modelo cache).
#   {success, problem, checksum, time_limits:{lang:seg} (máx entre hosts), hosts:{...}}
# time_limits vazio = ninguém calibrou a versão atual ainda (ou o pacote mudou).
require_admin
source "$_DIR/lib/tl-store.sh"

problem="$(param problem)"
[[ -n "$problem" ]] || fail 400 "Missing problem" "problem_missing"
valid_id "$problem" || fail 400 "Invalid problem" "problem_invalid"

cur="$(pkg_tl_checksum "$(pkg_path "$problem")")"
emit_json 200 OK
jq -cn --arg p "$problem" --arg cks "$cur" \
   --argjson tl "$(tl_store_served_for "$problem" "$cur")" \
   --argjson store "$(tl_store_get "$problem")" '
   {success:true, problem:$p, checksum:$cks, time_limits:$tl,
    calibrated_checksum:($store.checksum // ""),
    hosts:($store.hosts // {}), updated_at:($store.updated_at // null),
    stale:(($store.checksum // "") != $cks and ($store.checksum // "") != "")}'
