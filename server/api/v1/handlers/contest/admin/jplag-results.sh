# GET /contest/admin/jplag-results?contest=<id>  (admin) -> status + resultados por problema/lang.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"

jdir="$CONTESTSDIR/$contest/jplag"
status="$( [[ -f "$jdir/status.json" ]] && jq -c . "$jdir/status.json" 2>/dev/null || echo '{"running":false,"message":"nunca executado"}')"
[[ -n "$status" ]] || status='{"running":false,"message":"nunca executado"}'
set +o noglob; shopt -s nullglob
arr=()
for f in "$jdir"/r-*.json; do [[ -f "$f" ]] && arr+=("$(cat "$f")"); done
shopt -u nullglob
results="$( ((${#arr[@]})) && printf '%s\n' "${arr[@]}" | jq -cs 'sort_by(.problem, .lang)' || echo '[]')"
ok_json '{status:$s, results:$r}' --argjson s "$status" --argjson r "$results"
