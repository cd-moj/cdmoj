# POST /contest/set-verdict?contest=<id>   (Bearer, judge)
# body: {problem_id, verdict, username}
# Registra um override de veredicto: grava arquivo de spool p/ o daemon aplicar.
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_judge || fail 403 "Judge only" "judge_required"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
problem="$(jq -r '.problem_id // empty' <<<"$body")"
verdict="$(jq -r '.verdict // empty' <<<"$body")"
username="$(jq -r '.username // empty' <<<"$body")"
[[ -n "$problem" && -n "$verdict" && -n "$username" ]] \
  || fail 400 "Missing problem_id, verdict or username" "incomplete"
valid_id "$problem" || fail 400 "Invalid problem id" "problem_invalid"
valid_id "$username" || fail 400 "Invalid username" "username_invalid"

AGORA="$EPOCHSECONDS"
ID="$(printf '%s%s%s%s%s' "$contest" "$AGORA" "$SESSION_LOGIN" "$username" "$RANDOM" \
      | md5sum | cut -d' ' -f1)"

mkdir -p "$SPOOLDIR"
spoolname="$contest:$AGORA:$ID:$SESSION_LOGIN:setverdict:$problem"
tmp="$SPOOLDIR/.in.$ID"
jq -cn --arg c "$contest" --arg j "$SESSION_LOGIN" --arg p "$problem" \
   --arg v "$verdict" --arg u "$username" --argjson ts "$AGORA" --arg id "$ID" \
   '{action:"set-verdict", contest:$c, judge:$j, problem_id:$p,
     verdict:$v, username:$u, time:$ts, id:$id}' > "$tmp"
mv -f "$tmp" "$SPOOLDIR/$spoolname"

ok_json '{action:"set-verdict", id:$id, status:"queued"}' --arg id "$ID"
