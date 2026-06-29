# POST /contest/clarification-broadcast?contest=<id>  (admin/judge/mon)  {problem?, question, answer}
# "Clarification especial": a organização publica uma pergunta JÁ com a resposta que ela mesma
# escreve, visível a todo o contest. O autor (juiz) fica oculto (login vazio; a UI mostra
# "Aviso oficial / Organização"). Auditado.
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_admin || is_judge || is_mon; } || fail 403 "Apenas admin/judge/monitor" "answer_forbidden"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
question="$(jq -r '.question // empty' <<<"$body")"
answer="$(jq -r '.answer // empty' <<<"$body")"
problem="$(jq -r '.problem // "general"' <<<"$body")"
[[ -n "$question" ]] || fail 422 "Escreva a pergunta" "question_missing"
[[ -n "$answer" ]] || fail 422 "Escreva a resposta" "answer_missing"
(( ${#question} <= 4000 )) || fail 422 "Pergunta muito longa" "question_long"
(( ${#answer} <= 4000 )) || fail 422 "Resposta muito longa" "answer_long"
[[ "$problem" == "general" || "$problem" =~ ^[A-Za-z0-9]{1,3}$ ]] || fail 422 "problema inválido" "problem_invalid"

dir="$CONTESTSDIR/$contest/clarifications"; mkdir -p "$dir"
id="$(printf '%s%s%s%s' "$contest" "$EPOCHSECONDS" "$SESSION_LOGIN" "$RANDOM" | md5sum | cut -d' ' -f1)"
jq -cn --arg id "$id" --argjson t "$EPOCHSECONDS" --arg p "$problem" --arg q "$question" \
  --arg a "$answer" --arg by "$SESSION_LOGIN" --argjson at "$EPOCHSECONDS" \
  '{id:$id, time:$t, problem:$p, login:"", question:$q, public:true, broadcast:true,
    answer:$a, answered_by:$by, answered_at:$at, answer_claim:null}' \
  > "$dir/$id.json.tmp" && mv -f "$dir/$id.json.tmp" "$dir/$id.json"
audit_log_to "$contest" clarification-broadcast "by=$SESSION_LOGIN problem=$problem id=$id"
ok_json '{broadcast:true, id:$id}' --arg id "$id"
