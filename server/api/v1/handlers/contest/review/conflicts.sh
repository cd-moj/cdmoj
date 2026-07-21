# GET /contest/review/conflicts?contest=<id>   (Bearer, admin OU juiz-chefe)
# Sumário dos CONFLITOS de veredicto (2 juízes discordaram) p/ o juiz-chefe resolver. Mostra os
# votos de cada juiz. `n` é usado pelo front p/ disparar o alerta vibrante quando aumenta.
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin_or_chief || fail 403 "Apenas o admin ou o juiz-chefe" "chief_required"
source "$_LIBDIR/review.sh"

now="$EPOCHSECONDS"
items=()
while IFS= read -r rf; do
  [[ -n "$rf" ]] || continue
  p="$(jq -c --argjson now "$now" --argjson q "$(rv_quorum "$contest")" "$(rv_expire_filter)
    | $(rv_recompute)
    | select(.conflict == true)
    | { id, login, problem_id, lang, sub_epoch, computed_verdict, created_at,
        votes:[ (.votes // [])[] | {by, label, verdict} ] }" "$rf" 2>/dev/null)"
  [[ -n "$p" && "$p" != null ]] && items+=("$p")
done < <(find "$(rv_dir "$contest")" -maxdepth 1 -name '*.json' 2>/dev/null)
out="$( ((${#items[@]})) && printf '%s\n' "${items[@]}" | jq -cs 'sort_by(.created_at)' || echo '[]')"
ok_json '{conflicts:$c, n:($c|length), options:$o}' --argjson c "$out" --argjson o "$(rv_options "$contest")"
