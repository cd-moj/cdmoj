# GET /contest/review/list?contest=<id>   (Bearer, judge)
# Fila de revisão de veredicto manual + minha avaliação ativa + contadores. Votos dos outros
# juízes ficam OCULTOS p/ não-chief (evita anchoring); o juiz-chefe vê tudo.
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_judge || fail 403 "Judge only" "judge_required"
source "$_LIBDIR/review.sh"

me="$SESSION_LOGIN"; now="$EPOCHSECONDS"
chief="$(is_chief && echo true || echo false)"
manual="$([[ "$(grep -m1 '^MANUAL_VERDICT=' "$CONTESTSDIR/$contest/conf" 2>/dev/null | cut -d= -f2- | tr -d "\"'")" == 1 ]] && echo true || echo false)"
options="$(rv_options "$contest")"
dir="$(rv_dir "$contest")"

set +o noglob; shopt -s nullglob
items=()
for f in "$dir"/*.json; do
  [[ -f "$f" ]] || continue
  proj="$(jq -c --argjson now "$now" --arg me "$me" --argjson chief "$chief" "$(rv_expire_filter)
    | $(rv_recompute)
    | select((.status // \"open\") != \"released\")
    | { id, login, problem_id, lang, computed_verdict, status, conflict, created_at, sub_epoch,
        claimants: [ (.claimants // [])[] | {by, elapsed_s:(\$now - (.at // 0)), expires_in_s:((.expires_at // 0) - \$now)} ],
        votes_n: ((.votes // [])|length),
        my_vote: (((.votes // [])[] | select(.by==\$me) | .verdict) // null),
        votes: (if \$chief then (.votes // []) else null end) }" "$f" 2>/dev/null)"
  [[ -n "$proj" && "$proj" != null ]] && items+=("$proj")
done
shopt -u nullglob

list="$( ((${#items[@]})) && printf '%s\n' "${items[@]}" | jq -cs 'sort_by(.created_at)' || echo '[]')"
counts="$(jq -c '{
  not_evaluated:   ([.[]|select((.claimants|length)==0 and ((.votes_n//0)==0))]|length),
  being_evaluated: ([.[]|select((.claimants|length)>=1)]|length),
  awaiting_second: ([.[]|select((.claimants|length)==0 and ((.votes_n//0)==1) and (.conflict!=true))]|length),
  conflicts:       ([.[]|select(.conflict==true)]|length) }' <<<"$list")"
my_active="$(rv_active_claim_by "$contest" "$me")"; [[ -n "$my_active" ]] || my_active=null
[[ "$my_active" == null ]] || my_active="\"$my_active\""

ok_json '{manual:$mn, options:$o, items:$it, counts:$c, my_active:$ma, is_chief:$ch}' \
  --argjson mn "$manual" --argjson o "$options" --argjson it "$list" --argjson c "$counts" \
  --argjson ma "$my_active" --argjson ch "$chief"
