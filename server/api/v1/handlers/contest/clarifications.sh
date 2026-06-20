# GET /contest/clarifications?contest=<id>  (Bearer)
# Lista clarifications. admin/judge/mon veem todas; demais veem as próprias + as públicas
# já respondidas.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

dir="$CONTESTSDIR/$contest/clarifications"
priv=false; { is_admin || is_judge || is_mon; } && priv=true

set +o noglob; shopt -s nullglob
arr=()
for f in "$dir"/*.json; do [[ -f "$f" ]] && arr+=("$(cat "$f")"); done
shopt -u nullglob
all="$( ((${#arr[@]})) && printf '%s\n' "${arr[@]}" | jq -cs 'sort_by(-.time)' || echo '[]')"
if [[ "$priv" == true ]]; then
  out="$all"
else
  out="$(jq -c --arg me "$SESSION_LOGIN" '[ .[] | select(.login==$me or (.public==true and ((.answer//"")|length)>0)) ]' <<<"$all")"
fi
ok_json '{clarifications:$c, can_answer:$ca}' --argjson c "$out" --argjson ca "$priv"
