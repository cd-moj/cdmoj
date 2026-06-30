# POST /contest/review/vote?contest=<id>   (Bearer, judge)  {id, label}
# Um avaliador registra o veredicto escolhido. Quando 2 avaliadores escolhem o MESMO veredicto,
# ele é liberado ao aluno (enfileira setverdict). Veredictos diferentes -> conflito (chief resolve).
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_judge || fail 403 "Judge only" "judge_required"
source "$_LIBDIR/review.sh"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
label="$(jq -r '.label // empty' <<<"$body")"
[[ "$id" =~ ^[A-Za-z0-9_]+$ ]] || fail 400 "id inválido" "id_invalid"
[[ -n "$label" ]] || fail 422 "Escolha um veredicto" "label_missing"
verdict="$(rv_canon_verdict "$contest" "$label")" || fail 422 "Veredicto não está na lista configurada" "verdict_invalid"

dir="$(rv_dir "$contest")"; f="$dir/$id.json"
[[ -f "$f" ]] || fail 404 "Submissão não está em revisão" "notfound"
me="$SESSION_LOGIN"; now="$EPOCHSECONDS"

exec 9>"$(rv_lock "$contest")"; flock -w 10 9 || fail 409 "Ocupado, tente de novo" "locked"
snap="$(rv_snapshot "$f")"; [[ -n "$snap" ]] || fail 500 "Falha ao ler" "read_fail"
[[ "$(jq -r '.status' <<<"$snap")" == released ]] && fail 409 "Submissão já liberada" "released"
jq -e --arg me "$me" 'any((.claimants//[])[]; .by==$me)' <<<"$snap" >/dev/null \
  || fail 409 "Pegue a submissão antes de votar" "not_claiming"

new="$(rv_apply "$f" '.votes = ([ (.votes//[])[] | select(.by != $me) ] + [{by:$me, at:$now, label:$label, verdict:$verdict}])' \
  --arg me "$me" --arg label "$label" --arg verdict "$verdict")"
[[ -n "$new" ]] || fail 500 "Falha ao gravar" "write_fail"
st="$(jq -r '.status' <<<"$new")"

if [[ "$st" == agreed ]]; then
  v="$(jq -r '(.votes[0].verdict)' <<<"$new")"
  login="$(jq -r '.login' <<<"$new")"; prob="$(jq -r '.problem_id' <<<"$new")"
  rv_emit_setverdict "$contest" "$id" "$login" "$prob" "$v"
  jq -c --arg v "$v" --argjson at "$now" '.status="released" | .released_verdict=$v | .released_by="agreement" | .released_at=$at' "$f" > "$f.tmp" && mv -f "$f.tmp" "$f"
  audit_log_to "$contest" review-agree "id=$id verdict=$v by=$me"
  ok_json '{status:"released", released_verdict:$v}' --arg v "$v"
elif [[ "$st" == conflict ]]; then
  audit_log_to "$contest" review-conflict "id=$id by=$me"
  ok_json '{status:"conflict"}'
else
  audit_log_to "$contest" review-vote "id=$id by=$me verdict=$verdict"
  ok_json '{status:$s}' --arg s "$st"
fi
