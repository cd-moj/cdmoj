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
dir="$CONTESTSDIR/$contest/clarifications"
f="$dir/$cid.json"
[[ -f "$f" ]] || fail 404 "Clarification não encontrada" "notfound"
now="$EPOCHSECONDS"

# serializa com a reserva (clarification-claim) p/ dois juízes não responderem a mesma
exec 9>"$dir/$cid.lock"; flock -w 10 9 || fail 409 "Ocupado, tente de novo" "locked"
answered="$(jq -r 'if ((.answer//"")|length)>0 then "true" else "false" end' "$f")"
claim_by="$(jq -r '.answer_claim.by // ""' "$f")"
claim_exp="$(jq -r '.answer_claim.expires_at // 0' "$f")"
(( now > ${claim_exp:-0} )) && claim_by=""
# já respondida: só chief/admin EDITAM; juiz/monitor respondem apenas as ABERTAS
if [[ "$answered" == true ]] && ! is_admin_or_chief; then
  fail 409 "Já respondida — apenas o juiz-chefe/admin edita a resposta" "already_answered"
fi
# aberta: exige a reserva minha (ou nenhuma) p/ não atropelar outro juiz
if [[ "$answered" != true && -n "$claim_by" && "$claim_by" != "$SESSION_LOGIN" ]]; then
  fail 409 "Reservada por $claim_by" "clar_claimed"
fi
jq -c --arg a "$answer" --arg by "$SESSION_LOGIN" --argjson at "$now" --argjson pb "$pub" \
  '.answer=$a | .answered_by=$by | .answered_at=$at | .public=$pb | .answer_claim=null' "$f" > "$f.tmp" && mv -f "$f.tmp" "$f"
audit_log_to "$contest" clarification-answer "id=$cid public=$pub edited=$answered by=$SESSION_LOGIN"
ok_json '{answered:true, edited:$e}' --argjson e "$([[ "$answered" == true ]] && echo true || echo false)"
