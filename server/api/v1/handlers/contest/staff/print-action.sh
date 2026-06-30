# POST /contest/staff/print-action?contest=<c>   (Bearer; .staff ou .admin)
#   body {id, action: claim|processed|delivered, mode?: auto|manual}
# Máquina de estado da tarefa (sob flock <id>.lock — serializa com o build do PDF):
#   claim     : pending + (sem dono ou eu)  -> reserva (claimed_by/at)   [409 já reservada]
#   processed : qualquer (idempotente)       -> status=printed (+claim implícito)
#   delivered : printed                       -> status=delivered          [409 imprima antes]
# Tudo auditado (print-claim / print-processed / print-delivered) com seq= e by=.
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_staff || is_admin; } || fail 403 "Apenas staff" "staff_required"
source "$_LIBDIR/print.sh"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
action="$(jq -r '.action // empty' <<<"$body")"
mode="$(jq -r '.mode // "manual"' <<<"$body")"; [[ "$mode" == auto ]] || mode=manual
[[ "$id" =~ ^[A-Za-z0-9_]+$ ]] || fail 400 "id inválido" "id_invalid"
case "$action" in claim|processed|delivered) ;; *) fail 422 "ação inválida" "action_invalid";; esac

dir="$(pr_dir "$contest")"
meta="$dir/$id.json"
[[ -f "$meta" ]] || fail 404 "Pedido não encontrado" "notfound"
owner="$(jq -r '.login // ""' "$meta" 2>/dev/null)"
staff_can_see "$contest" "$SESSION_LOGIN" "$owner" || fail 403 "Tarefa fora do seu escopo" "out_of_scope"

me="$SESSION_LOGIN"
exec 9>"$dir/$id.lock"; flock -w 10 9 || fail 409 "Ocupado, tente de novo" "locked"

cur="$(jq -r '.status // "pending"' "$meta")"
seq="$(jq -r '.seq // 0' "$meta")"
pages="$(jq -r '.pages // 0' "$meta")"
kind="$(jq -r '.kind // "print"' "$meta")"   # print | balloon -> prefixo do evento de auditoria
tmp="$dir/$id.json.tmp"

case "$action" in
  claim)
    [[ "$cur" == pending ]] || fail 409 "Tarefa não está pendente" "not_pending"
    cb="$(jq -r '.claimed_by // ""' "$meta")"
    [[ -z "$cb" || "$cb" == "$me" ]] || fail 409 "Já reservada por $cb" "already_claimed"
    jq --arg by "$me" --argjson at "$EPOCHSECONDS" '.claimed_by=$by | .claimed_at=$at' "$meta" > "$tmp" && mv -f "$tmp" "$meta"
    audit_log_to "$contest" "$kind-claim" "seq=$seq by=$me"
    ;;
  processed)
    if [[ "$cur" == delivered ]]; then :   # já entregue: no-op idempotente
    else
      jq --arg by "$me" --argjson at "$EPOCHSECONDS" --arg md "$mode" '
        .status="printed" | .processed_by=$by | .processed_at=$at | .print_mode=$md
        | (if (.claimed_by // "")=="" then .claimed_by=$by | .claimed_at=$at else . end)' \
        "$meta" > "$tmp" && mv -f "$tmp" "$meta"
      audit_log_to "$contest" "$kind-processed" "seq=$seq by=$me modo=$mode paginas=$pages"
    fi
    ;;
  delivered)
    [[ "$cur" == printed ]] || fail 409 "Imprima antes de entregar" "not_printed"
    jq --arg by "$me" --argjson at "$EPOCHSECONDS" '.status="delivered" | .delivered_by=$by | .delivered_at=$at' "$meta" > "$tmp" && mv -f "$tmp" "$meta"
    audit_log_to "$contest" "$kind-delivered" "seq=$seq by=$me"
    ;;
esac

new="$(jq -c '{id,seq,status,claimed_by,processed_by,delivered_by}' "$meta")"
ok_json '{updated:$u}' --argjson u "$new"
