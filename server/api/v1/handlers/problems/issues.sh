# GET  /problems/issues?id=<id>                                        (Bearer)
#   -> {id, open, issues:[{n,title,body,state,by,at,updated_at,closed_by,closed_at,comments:[{by,at,body}]}]}
# POST /problems/issues  {id, action: open|comment|close|reopen, n?, title?, body?}
#   open    {title, body?}      -> nova issue (aberta)
#   comment {n, body}           -> comentário
#   close   {n, body?}          -> fecha (o texto, se veio, entra como comentário)
#   reopen  {n, body?}          -> reabre
#   -> {id, open, issue}
# ISSUES POR PROBLEMA (lib/problem-issues.sh): a revisão interna da banca. Issue aberta tira o problema
# de "pronto" (/problems/status: pending issues_open:<n>). Acesso = quem EDITA o problema
# (require_problem_edit): quem não pode ver recebe o MESMO 404 de problema inexistente.
source "$_DIR/lib/tl-store.sh"; source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"
source "$_DIR/lib/problem-issues.sh"
require_auth

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  id="$(param id)"
  [[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
  valid_id "$id" || fail 400 "Invalid id" "id_invalid"
  require_problem_edit "$id"
  [[ -d "$(pkg_path "$id")" ]] || fail 404 "Problema não existe" "prob_missing"
  # a loja cresce com o nº de issues/comentários: vai por --slurpfile (ok_json_slurp), nunca --argjson
  ok_json_slurp '{id:$id, open:([$d[0].issues[] | select(.state == "open")] | length),
                  issues:($d[0].issues | sort_by(if .state == "open" then 0 else 1 end, -(.updated_at // 0)))}' \
    d "$(pi_get "$id")" --arg id "$id"
  exit 0
fi

require_method POST
bf="$(read_body_file)"; trap 'rm -f "$bf"' EXIT
jq -e 'type == "object"' >/dev/null 2>&1 < "$bf" || fail 400 "Invalid JSON body" "bad_json"
id="$(jq -r '.id // empty' "$bf")"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
require_problem_edit "$id"
[[ -d "$(pkg_path "$id")" ]] || fail 404 "Problema não existe" "prob_missing"
act="$(jq -r '.action // ""' "$bf")"
res="$(pi_apply "$id" "$SESSION_LOGIN" "$bf")"; rc=$?
case "$rc" in
  0) ;;
  2) fail 400 "$res" "issue_invalid" ;;
  3) fail 404 "$res" "issue_notfound" ;;
  4) fail 409 "$res" "issue_state" ;;
  5) fail 422 "$res" "issue_limit" ;;
  *) fail 500 "Não foi possível gravar a issue" "issue_store_fail" ;;
esac
n="$(jq -r '.issue.n // ""' <<<"$res")"
audit_log "problem-issue" "id=$id action=$act n=$n by=$SESSION_LOGIN"
ok_json_slurp '{id:$id} + $r[0]' r "$res" --arg id "$id"
