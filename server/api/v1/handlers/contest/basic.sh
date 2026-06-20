# GET /contest/basic?contest=<id>   (PÚBLICO)
# Info básica p/ tela de login/countdown: nome, id, início, fim, login_start_time, locale.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"

CONTEST_ID="$contest"; CONTEST_NAME=""; CONTEST_START=0; CONTEST_END=0
LOGIN_START_TIME=""; LOCALE=""; LOGIN_ENABLED=""; FREEZE_TIME=""; SCORE_ANON=""
load_contest_conf "$contest"

[[ -n "$LOGIN_START_TIME" ]] || LOGIN_START_TIME="$CONTEST_START"
[[ -n "$LOCALE" ]] || LOCALE="pt"
le="$([[ "$LOGIN_ENABLED" == n ]] && echo false || echo true)"
sa="$([[ "$SCORE_ANON" == 1 ]] && echo true || echo false)"

ok_json '{contest_id:$id, contest_name:$name, start_time:$start, end_time:$end,
          login_start_time:$lst, locale:$loc, login_enabled:$le, freeze_time:$fz, score_anon:$sa}' \
  --arg id "$CONTEST_ID" --arg name "$CONTEST_NAME" \
  --argjson start "${CONTEST_START:-0}" --argjson end "${CONTEST_END:-0}" \
  --argjson lst "${LOGIN_START_TIME:-0}" --arg loc "$LOCALE" \
  --argjson le "$le" --argjson fz "${FREEZE_TIME:-0}" --argjson sa "$sa"
