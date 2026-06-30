# POST /contest/review/resolve?contest=<id>   (Bearer, juiz-chefe ou admin)  {id, verdict}
# Resolve um CONFLITO (ou faz override): o juiz-chefe escolhe o veredicto final, que é liberado
# ao aluno (enfileira setverdict). Auditado.
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin_or_chief || fail 403 "Apenas o juiz-chefe (ou admin) resolve conflitos" "chief_required"
source "$_LIBDIR/review.sh"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
raw="$(jq -r '.verdict // empty' <<<"$body")"
[[ "$id" =~ ^[A-Za-z0-9_]+$ ]] || fail 400 "id inválido" "id_invalid"
[[ -n "$raw" ]] || fail 422 "Escolha o veredicto" "verdict_missing"
verdict="$(rv_canon_verdict "$contest" "$raw")" || fail 422 "Veredicto não está na lista configurada" "verdict_invalid"

dir="$(rv_dir "$contest")"; f="$dir/$id.json"
[[ -f "$f" ]] || fail 404 "Submissão não está em revisão" "notfound"
me="$SESSION_LOGIN"; now="$EPOCHSECONDS"

exec 9>"$(rv_lock "$contest")"; flock -w 10 9 || fail 409 "Ocupado, tente de novo" "locked"
snap="$(rv_snapshot "$f")"; [[ -n "$snap" ]] || fail 500 "Falha ao ler" "read_fail"
[[ "$(jq -r '.status' <<<"$snap")" == released ]] && fail 409 "Submissão já liberada" "already_released"

login="$(jq -r '.login' <<<"$snap")"; prob="$(jq -r '.problem_id' <<<"$snap")"
rv_emit_setverdict "$contest" "$id" "$login" "$prob" "$verdict"
jq -c --arg v "$verdict" --arg by "$me" --argjson at "$now" \
  '.status="released" | .conflict=false | .released_verdict=$v | .released_by=$by | .released_at=$at' "$f" > "$f.tmp" && mv -f "$f.tmp" "$f"
audit_log_to "$contest" review-resolve "id=$id verdict=$verdict by=$me"
ok_json '{status:"released", released_verdict:$v}' --arg v "$verdict"
