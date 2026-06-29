# POST /contest/clarification-claim?contest=<id>  (admin/judge/mon)  {id, action:claim|release}
# Reserva uma clarification ABERTA p/ responder (evita que dois juízes peguem a mesma). A
# reserva tem TTL (CLAR_TTL, 5 min) e é zerada preguiçosamente na leitura. Auditado.
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_admin || is_judge || is_mon; } || fail 403 "Apenas admin/judge/monitor" "answer_forbidden"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
cid="$(jq -r '.id // empty' <<<"$body")"
action="$(jq -r '.action // empty' <<<"$body")"
[[ "$cid" =~ ^[0-9a-f]{32}$ ]] || fail 400 "id inválido" "id_invalid"
case "$action" in claim|release) ;; *) fail 422 "ação inválida" "action_invalid";; esac

dir="$CONTESTSDIR/$contest/clarifications"
f="$dir/$cid.json"
[[ -f "$f" ]] || fail 404 "Clarification não encontrada" "notfound"
me="$SESSION_LOGIN"; now="$EPOCHSECONDS"; ttl="${CLAR_TTL:-300}"

exec 9>"$dir/$cid.lock"; flock -w 10 9 || fail 409 "Ocupado, tente de novo" "locked"
cur_by="$(jq -r '.answer_claim.by // ""' "$f")"
cur_exp="$(jq -r '.answer_claim.expires_at // 0' "$f")"
(( now > ${cur_exp:-0} )) && cur_by=""                 # reserva expirada = livre
answered="$(jq -r 'if ((.answer//"")|length)>0 then "true" else "false" end' "$f")"
tmp="$dir/$cid.json.tmp"

case "$action" in
  claim)
    # respondida: só chief/admin (que editam) reservam; juiz responde apenas abertas
    [[ "$answered" == true ]] && ! is_admin_or_chief && fail 409 "Já respondida" "already_answered"
    [[ -z "$cur_by" || "$cur_by" == "$me" ]] || fail 409 "Sendo respondida por $cur_by" "clar_claimed"
    jq -c --arg by "$me" --argjson at "$now" --argjson ex "$((now+ttl))" \
      '.answer_claim={by:$by, at:$at, expires_at:$ex}' "$f" > "$tmp" && mv -f "$tmp" "$f"
    audit_log_to "$contest" clar-claim "id=$cid by=$me"
    ok_json '{claimed:true, claimed_by:$by, expires_at:$ex}' --arg by "$me" --argjson ex "$((now+ttl))"
    ;;
  release)
    [[ -z "$cur_by" || "$cur_by" == "$me" ]] || is_admin_or_chief || fail 409 "Reservada por $cur_by" "clar_claimed"
    jq -c '.answer_claim=null' "$f" > "$tmp" && mv -f "$tmp" "$f"
    audit_log_to "$contest" clar-release "id=$cid by=$me"
    ok_json '{released:true}'
    ;;
esac
