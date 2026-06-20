# POST /contest/clarification-answer?contest=<id>  (admin/judge/mon) {id, answer, public?}
# Responde uma clarification. public=true -> visível a todo o contest; senão só ao time.
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_admin || is_judge || is_mon; } || fail 403 "Apenas admin/judge/monitor podem responder" "answer_forbidden"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
cid="$(jq -r '.id // empty' <<<"$body")"
answer="$(jq -r '.answer // empty' <<<"$body")"
pub="$(jq -r 'if .public==true then true else false end' <<<"$body")"
[[ "$cid" =~ ^[0-9a-f]{32}$ ]] || fail 400 "id inválido" "id_invalid"
[[ -n "$answer" ]] || fail 422 "Escreva a resposta" "answer_missing"
(( ${#answer} <= 4000 )) || fail 422 "Resposta muito longa" "answer_long"
f="$CONTESTSDIR/$contest/clarifications/$cid.json"
[[ -f "$f" ]] || fail 404 "Clarification não encontrada" "notfound"
jq -c --arg a "$answer" --arg by "$SESSION_LOGIN" --argjson at "$EPOCHSECONDS" --argjson pb "$pub" \
  '.answer=$a | .answered_by=$by | .answered_at=$at | .public=$pb' "$f" > "$f.tmp" && mv -f "$f.tmp" "$f"
audit_log_to "$contest" clarification-answer "id=$cid public=$pub"
ok_json '{answered:true}'
