# POST /contest/set-verdict?contest=<id>   (Bearer, admin ou juiz-CHEFE)
# body: {id, username, verdict, problem_id?}
# Troca o veredicto de UMA submissão (a página Avaliar, nos contests sem veredicto manual): grava o setverdict no
# spool (rv_emit_setverdict, o mesmo do fluxo de revisão) e o daemon o aplica pelo escritor único.
# `id` = o da SUBMISSÃO (16/11/2026): o daemon acha a linha do history por ele. Sem ele o pedido não tinha alvo — o
# handler inventava um id e respondia "queued" a um pedido que o daemon descartava ("submissão não achada"); hoje a
# rota confere ANTES de responder: submissão inexistente = 404, de outro problema = 422, ainda em julgamento = 409
# (o resultado do juiz chegaria depois e apagaria a troca; a retida na revisão manual pode).
# ⚠ GATE: sobrescrever o veredicto de um time é ato de CHEFIA — no fluxo de veredicto manual o
# juiz comum vota (review/vote) e o desempate é do chefe (review/resolve). A UI já escondia a
# coluna do juiz puro (a lista dele é anônima e o set-verdict exige username), mas a rota
# aceitava qualquer is_judge: por curl/moj-cli um juiz comum sobrescrevia veredicto sozinho.
# Regra da casa: acesso é da API, nunca só da interface (2026-08-20).
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin_or_chief || fail 403 "Só o juiz-chefe ou o admin sobrescreve veredicto" "chief_required"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
problem="$(jq -r '.problem_id // empty' <<<"$body")"
verdict="$(jq -r '.verdict // empty' <<<"$body")"
username="$(jq -r '.username // empty' <<<"$body")"
sid="$(jq -r '.id // empty' <<<"$body")"
[[ -n "$verdict" && -n "$username" ]] || fail 400 "Missing verdict or username" "incomplete"
[[ -n "$sid" ]] || fail 400 "Falta o id da submissão" "id_required"
# nada de string livre no history (2026-09-14): label OU classe da lista configurada
source "$_LIBDIR/review.sh"
verdict="$(rv_canon_verdict "$contest" "$verdict")" || fail 422 "Veredicto não está na lista configurada (final-verdicts)" "verdict_invalid"
valid_id "$username" || fail 400 "Invalid username" "username_invalid"
[[ "$sid" =~ ^[0-9a-f]{8,64}$ ]] || fail 400 "Invalid submission id" "id_invalid"
[[ -z "$problem" ]] || valid_id "$problem" || fail 400 "Invalid problem id" "problem_invalid"

# a linha da submissão no history do aluno: <tempo>:<prob>:<lang>:<verdict…>:<sub_epoch>:<id>
# (o veredicto pode ter `:` — vai do 4º campo ao antepenúltimo; o problema é o 2º)
h_prob=""; h_verdict=""
IFS=$'\t' read -r h_prob h_verdict < <(awk -F: -v id="$sid" '$NF==id{ v=$4; for (i=5; i<=NF-2; i++) v=v":"$i;
  printf "%s\t%s\n", $2, v; exit }' "$(user_hist_file "$contest" "$username")" 2>/dev/null)
[[ -n "$h_prob" ]] || fail 404 "Submissão não encontrada" "submission_notfound"
[[ -z "$problem" || "$problem" == "$h_prob" ]] || fail 422 "A submissão é de outro problema" "problem_mismatch"
if [[ "$h_verdict" =~ ^(Not\ Answered\ Yet|On\ queue|Running) && ! -f "$CONTESTSDIR/$contest/review/$sid.json" ]]; then
  fail 409 "A submissão ainda está em julgamento: espere o veredicto do juiz" "submission_pending"
fi

rv_emit_setverdict "$contest" "$sid" "$username" "$h_prob" "$verdict"
audit_log_to "$contest" set-verdict "id=$sid user=$username prob=$h_prob verdict=$verdict"   # quem pediu (o daemon registra a aplicação)

ok_json '{action:"set-verdict", id:$id, status:"queued"}' --arg id "$sid"
