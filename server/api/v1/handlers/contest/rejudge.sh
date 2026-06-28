# POST /contest/rejudge?contest=<id>   (Bearer, admin)
# body: {ids:[...]}  — para cada submission id, enfileira um arquivo de rejulgamento
# em $SPOOLDIR: <contest>:<time>:<id>:<login>:rejulgar:<subid>
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Admin only" "admin_required"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
# normaliza: aceita {ids:[...]} (array) ou ids como string única
mapfile -t IDS < <(jq -r '(.ids // []) | (if type=="array" then .[] else . end) // empty' <<<"$body")
(( ${#IDS[@]} > 0 )) || fail 400 "Missing ids" "ids_missing"

mkdir -p "$SPOOLDIR"
AGORA="$EPOCHSECONDS"
declare -a QUEUED
for subid in "${IDS[@]}"; do
  [[ -n "$subid" ]] || continue
  valid_id "$subid" || fail 400 "Invalid submission id: $subid" "id_invalid"
  spoolname="$contest:$AGORA:$subid:$SESSION_LOGIN:rejulgar:$subid"
  : > "$SPOOLDIR/$spoolname"
  QUEUED+=("$subid")
done

audit_log_to "$contest" rejudge "count=${#QUEUED[@]} ids=$( (IFS=,; printf '%s' "${QUEUED[*]}") | head -c 200)"
ok_json '{action:"rejudge", queued:$q, count:($q|length)}' \
  --argjson q "$(printf '%s\n' "${QUEUED[@]}" | jq -R . | jq -cs 'map(select(length>0))')"
