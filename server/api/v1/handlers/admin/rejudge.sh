# POST /admin/rejudge   (Bearer, admin)  — variante p/ o bot.
# body: {contest, ids:[...]}  OU  {contest, problem}
# Enfileira rejulgamento por lista de ids, ou de um problema inteiro, em $SPOOLDIR.
require_method POST
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
contest="$(jq -r '.contest // empty' <<<"$body")"
problem="$(jq -r '.problem // .problem_id // empty' <<<"$body")"

[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Admin only" "admin_required"

mkdir -p "$SPOOLDIR"
AGORA="$EPOCHSECONDS"

mapfile -t IDS < <(jq -r '(.ids // []) | (if type=="array" then .[] else . end) // empty' <<<"$body")

if (( ${#IDS[@]} > 0 )); then
  declare -a QUEUED
  for subid in "${IDS[@]}"; do
    [[ -n "$subid" ]] || continue
    valid_id "$subid" || fail 400 "Invalid submission id: $subid" "id_invalid"
    : > "$SPOOLDIR/$contest:$AGORA:$subid:$SESSION_LOGIN:rejulgar:$subid"
    QUEUED+=("$subid")
  done
  ok_json '{action:"rejudge", queued:$q, count:($q|length)}' \
    --argjson q "$(printf '%s\n' "${QUEUED[@]}" | jq -R . | jq -cs 'map(select(length>0))')"
elif [[ -n "$problem" ]]; then
  valid_id "$problem" || fail 400 "Invalid problem id" "problem_invalid"
  ID="$(printf '%s%s%s' "$contest" "$AGORA" "$RANDOM" | md5sum | cut -d' ' -f1)"
  : > "$SPOOLDIR/$contest:$AGORA:$ID:$SESSION_LOGIN:rejulgarproblema:$problem"
  ok_json '{action:"rejudge", problem:$p, status:"queued"}' --arg p "$problem"
else
  fail 400 "Missing ids or problem" "rejudge_target_missing"
fi
