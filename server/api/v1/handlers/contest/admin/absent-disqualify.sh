# GET/POST /contest/admin/absent-disqualify?contest=<c>   (admin DO contest)
# DESCLASSIFICAR QUEM NÃO LOGOU, em lote (regras em lib/absent-dq.sh).
#   GET                              -> {preview:{window,live,counts,candidates[],kept_classified[],plan_id}, batches[]}
#                                       (a prévia: nada é gravado)
#   POST {action:"apply", plan_id}   -> desclassifica os candidatos; a lista tem de ser a da prévia (mudou = 409
#                                       plan_changed: o cliente pede a prévia de novo pelo GET — ela não vai no erro,
#                                       que passa por argv e estouraria com milhares de times). -> {batch, count, batches[]}
#   POST {action:"undo", batch}      -> devolve o lote (só quem ainda tem a marca dele). -> {batch, restored, batches[]}
#                                       404 batch_notfound · 409 batch_undone
# Vale a qualquer momento (decisão do Ribas): com a prova rodando, a janela vai até agora e a prévia diz `live:true`.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
[[ "$contest" == treino ]] && fail 409 "O Treino Livre não tem prova para desclassificar ausentes" "not_a_contest"
source "$_LIBDIR/contest-gate.sh"
source "$_LIBDIR/absent-dq.sh"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

if [[ "$REQUEST_METHOD" == GET ]]; then
  adq_scan "$contest" "$W" || fail 500 "Falha ao levantar os times" "scan_fail"
  adq_batches_json "$contest" > "$W/batches.json"
  ok_json '{preview:$p[0], batches:$b[0]}' --slurpfile p "$W/scan.json" --slurpfile b "$W/batches.json"
  exit 0
fi

require_method POST
body="$(read_body)"; [[ -n "$body" ]] || body='{}'
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
action="$(jq -r '.action // ""' <<<"$body")"
# um lote por vez (aplicar × desfazer × outro admin)
exec 8>"$CONTESTSDIR/$contest/var/.absent-dq.lock"
flock -w 20 8 || fail 409 "Outra desclassificação em lote está em andamento — tente de novo" "busy"
case "$action" in
  apply)
    pid="$(jq -r '.plan_id // ""' <<<"$body")"
    adq_scan "$contest" "$W" || fail 500 "Falha ao levantar os times" "scan_fail"
    if [[ -z "$pid" || "$pid" != "$(jq -r '.plan_id' "$W/scan.json")" ]]; then
      fail 409 "A lista mudou desde a prévia — confira a nova lista e confirme de novo" "plan_changed"
    fi
    [[ "$(jq -r '.counts.candidates' "$W/scan.json")" -gt 0 ]] || fail 409 "Não há time para desclassificar" "nothing_to_do"
    id="$(adq_apply "$contest" "$W" "$SESSION_LOGIN")" || fail 500 "Falha ao desclassificar" "apply_fail"
    n="$(jq -r --arg id "$id" '.batches[] | select(.id == $id) | .logins | length' "$(adq_state_file "$contest")" 2>/dev/null)"
    adq_batches_json "$contest" > "$W/batches.json"
    ok_json '{batch:$id, count:$n, batches:$b[0]}' --arg id "$id" --argjson n "${n:-0}" --slurpfile b "$W/batches.json" ;;
  undo)
    bid="$(jq -r '.batch // ""' <<<"$body")"
    [[ "$bid" =~ ^adq[0-9a-f]{10}$ ]] || fail 400 "Lote inválido" "batch_invalid"
    r="$(adq_undo "$contest" "$bid" "$SESSION_LOGIN")"; rc=$?
    (( rc == 2 )) && fail 404 "Lote não encontrado" "batch_notfound"
    (( rc == 3 )) && fail 409 "Este lote já foi desfeito" "batch_undone"
    (( rc == 0 )) || fail 500 "Falha ao desfazer" "undo_fail"
    adq_batches_json "$contest" > "$W/batches.json"
    ok_json '{batch:$id, restored:$n, batches:$b[0]}' --arg id "$bid" --argjson n "${r:-0}" --slurpfile b "$W/batches.json" ;;
  *) fail 400 "action inválida (apply|undo)" "action_invalid" ;;
esac
