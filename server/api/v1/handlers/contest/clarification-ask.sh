# POST /contest/clarification-ask?contest=<id>  (Bearer) {problem?, question}
# Qualquer usuário logado no contest pergunta. problem = letra do problema ou "general".
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
question="$(jq -r '.question // empty' <<<"$body")"
problem="$(jq -r '.problem // "general"' <<<"$body")"
[[ -n "$question" ]] || fail 422 "Escreva a pergunta" "question_missing"
(( ${#question} <= 4000 )) || fail 422 "Pergunta muito longa" "question_long"
[[ "$problem" == "general" || "$problem" =~ ^[A-Za-z0-9]{1,3}$ ]] || fail 422 "problema inválido" "problem_invalid"

dir="$CONTESTSDIR/$contest/clarifications"; mkdir -p "$dir"
id="$(printf '%s%s%s%s' "$contest" "$EPOCHSECONDS" "$SESSION_LOGIN" "$RANDOM" | md5sum | cut -d' ' -f1)"
jq -cn --arg id "$id" --argjson t "$EPOCHSECONDS" --arg p "$problem" --arg l "$SESSION_LOGIN" --arg q "$question" \
  '{id:$id, time:$t, problem:$p, login:$l, question:$q, public:false, answer:"", answered_by:"", answered_at:0}' \
  > "$dir/$id.json.tmp" && mv -f "$dir/$id.json.tmp" "$dir/$id.json"
audit_log_to "$contest" clarification-ask "by=$SESSION_LOGIN problem=$problem id=$id"
ok_json '{asked:true, id:$id}' --arg id "$id"
