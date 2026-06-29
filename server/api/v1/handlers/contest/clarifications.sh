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
now="$EPOCHSECONDS"
if [[ "$priv" == true ]]; then
  # privilegiados coordenam a resposta (veem answer_claim e answered_by), mas NUNCA veem quem
  # perguntou (.login) — tratamento isonômico. Reserva expirada é zerada na leitura (lazy).
  out="$(jq -c --argjson now "$now" '[ .[]
    | (if ((.answer_claim.expires_at // 0) < $now) then .answer_claim=null else . end)
    | del(.login) ]' <<<"$all")"
else
  # usuário comum: as próprias + públicas respondidas; sem asker, sem answered_by, sem reserva.
  out="$(jq -c --arg me "$SESSION_LOGIN" '[ .[]
    | select(.login==$me or (.public==true and ((.answer//"")|length)>0))
    | .mine=(.login==$me) | del(.login, .answered_by, .answer_claim) ]' <<<"$all")"
fi
ok_json '{clarifications:$c, can_answer:$ca, is_chief:$ch}' \
  --argjson c "$out" --argjson ca "$priv" --argjson ch "$(is_chief && echo true || echo false)"
