# GET/POST /contest/admin/problems?contest=<id>  (admin DO contest)
# GET  -> [{source,problem_id,name,letter,statement_key}] na ordem atual.
# POST {action, ...}: add | remove | reorder | rename. Reescreve PROBS no conf + auditoria.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
source "$_LIBDIR/contest-create.sh"

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  ok_json '{problems:$p}' --argjson p "$(cc_probs_json "$contest")"
  exit 0
fi

require_method POST
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
action="$(jq -r '.action // empty' <<<"$body")"
cur="$(cc_probs_json "$contest")"
new=""

case "$action" in
  add)
    prob="$(jq -c '.problem // {}' <<<"$body")"
    [[ "$(jq -r '(.problem_id // .bank_id // "")' <<<"$prob")" != "" ]] || fail 422 "Informe problem_id ou bank_id" "prob_missing"
    new="$(jq -cn --argjson cur "$cur" --argjson p "$prob" '$cur + [$p]')"
    ;;
  remove)
    L="$(jq -r '.letter // empty' <<<"$body")"
    [[ -n "$L" ]] || fail 400 "Informe a letra" "letter_missing"
    new="$(jq -cn --argjson cur "$cur" --arg l "$L" '[ $cur[] | select(.letter != $l) ]')"
    ;;
  rename)
    L="$(jq -r '.letter // empty' <<<"$body")"
    [[ -n "$L" ]] || fail 400 "Informe a letra" "letter_missing"
    new="$(jq -cn --argjson cur "$cur" --argjson b "$body" --arg l "$L" '
      [ $cur[] | if .letter==$l then
          (if ($b|has("name")) then .name=$b.name else . end)
          | (if ($b|has("new_letter")) then .letter=$b.new_letter else . end)
        else . end ]')"
    ;;
  reorder)
    order="$(jq -c '.order // []' <<<"$body")"
    new="$(jq -cn --argjson cur "$cur" --argjson order "$order" '
      ($cur | map({(.letter): .}) | add) as $by
      | [ $order | to_entries[] | . as $e | ($by[$e.value] // empty) | (.letter = ([65 + $e.key] | implode)) ]')"
    ;;
  *) fail 400 "action inválida (add|remove|reorder|rename)" "action_invalid" ;;
esac

[[ -n "$new" ]] || fail 422 "Nada a fazer" "noop"
cc_set_probs "$contest" "$new" || fail 422 "Falha ao gravar problemas (dados inválidos?)" "probs_write"
audit_log_to "$contest" "problems-$action" "$(jq -cr '. | del(.problem.statement_b64)' <<<"$body" 2>/dev/null | head -c 300)"
ok_json '{saved:true, problems:$p}' --argjson p "$(cc_probs_json "$contest")"
