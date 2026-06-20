# GET /ops/problemtl?problem=<id>   (Bearer, admin) -> JSON
# Time limits de um problema nos juízes (substitui /problemtl do bot).
# Best-effort: nc ao master {"cmd":"problemtl","problem":<id>} com timeout curto;
# indisponível -> {success:true, problem:..., time_limits:{}}.
require_admin

problem="$(param problem)"
[[ -n "$problem" ]] || fail 400 "Missing problem" "problem_missing"
valid_id "$problem" || fail 400 "Invalid problem" "problem_invalid"

: "${JUDGE_HOST:=localhost}"
: "${JUDGE_PORT:=27000}"

emit_json 200 OK
resp=""
if command -v nc >/dev/null 2>&1; then
  req="$(jq -cn --arg p "$problem" '{cmd:"problemtl", problem:$p}')"
  resp="$(printf '%s\n' "$req" | nc -w 2 "$JUDGE_HOST" "$JUDGE_PORT" 2>/dev/null)"
fi

if [[ -n "$resp" ]] && jq -e . >/dev/null 2>&1 <<<"$resp"; then
  jq -c --arg p "$problem" '{success:true, problem:$p, time_limits:.}' <<<"$resp"
else
  jq -cn --arg p "$problem" '{success:true, problem:$p, time_limits:{}}'
fi
