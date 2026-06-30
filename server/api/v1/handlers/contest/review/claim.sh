# POST /contest/review/claim?contest=<id>   (Bearer, judge)  {id, action:claim|extend|giveup}
# Pega/renova/larga a avaliação de uma submissão. Máx 2 avaliadores; um juiz só avalia UMA por
# vez; TTL de 5 min (renovável com extend). Tudo sob flock + auditado.
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
action="$(jq -r '.action // empty' <<<"$body")"
[[ "$id" =~ ^[A-Za-z0-9_]+$ ]] || fail 400 "id inválido" "id_invalid"
case "$action" in claim|extend|giveup) ;; *) fail 422 "ação inválida" "action_invalid";; esac

dir="$(rv_dir "$contest")"; f="$dir/$id.json"
[[ -f "$f" ]] || fail 404 "Submissão não está em revisão" "notfound"
me="$SESSION_LOGIN"; now="$EPOCHSECONDS"; ttl="$(rv_ttl)"

exec 9>"$(rv_lock "$contest")"; flock -w 10 9 || fail 409 "Ocupado, tente de novo" "locked"
snap="$(rv_snapshot "$f")"; [[ -n "$snap" ]] || fail 500 "Falha ao ler" "read_fail"
[[ "$(jq -r '.status' <<<"$snap")" == released ]] && fail 409 "Submissão já liberada" "released"

case "$action" in
  claim)
    [[ "$(jq -r --arg me "$me" 'any((.votes//[])[]; .by==$me)' <<<"$snap")" == true ]] && fail 409 "Você já votou nesta submissão" "already_voted"
    (( "$(jq '(.votes//[])|length' <<<"$snap")" < 2 )) || fail 409 "Submissão já avaliada (aguardando liberação/chief)" "already_evaluated"
    other="$(rv_active_claim_by "$contest" "$me")"
    [[ -z "$other" || "$other" == "$id" ]] || fail 409 "Você já avalia a submissão $other; termine antes" "already_evaluating"
    if [[ "$(jq -r --arg me "$me" 'any((.claimants//[])[]; .by==$me)' <<<"$snap")" != true ]]; then
      (( "$(jq '(.claimants//[])|length' <<<"$snap")" < 2 )) || fail 409 "Já há 2 juízes avaliando" "slots_full"
    fi
    new="$(rv_apply "$f" '.claimants = ([ (.claimants//[])[] | select(.by != $me) ] + [{by:$me, at:$now, expires_at:($now+$ttl)}])' --arg me "$me" --argjson ttl "$ttl")"
    audit_log_to "$contest" review-claim "id=$id by=$me"
    ;;
  extend)
    jq -e --arg me "$me" 'any((.claimants//[])[]; .by==$me)' <<<"$snap" >/dev/null || fail 409 "Você não está avaliando esta" "not_claiming"
    new="$(rv_apply "$f" '.claimants = [ (.claimants//[])[] | if .by==$me then .expires_at=($now+$ttl) else . end ]' --arg me "$me" --argjson ttl "$ttl")"
    audit_log_to "$contest" review-extend "id=$id by=$me"
    ;;
  giveup)
    # desistir = larga o claim (sem votar); o voto, se já dado, é permanente (não se desfaz aqui)
    new="$(rv_apply "$f" '.claimants=[(.claimants//[])[]|select(.by!=$me)]' --arg me "$me")"
    audit_log_to "$contest" review-giveup "id=$id by=$me"
    ;;
esac
[[ -n "$new" ]] || fail 500 "Falha ao gravar" "write_fail"
ok_json '{updated:$u}' --argjson u "$(jq -c '{id, status, conflict, claimants:[(.claimants//[])[]|{by,expires_at}]}' <<<"$new")"
