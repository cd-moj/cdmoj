# POST /treino/admin/lock-user  {login} | {logins:[...]} [+ dry_run | plan_id + confirm]  (SÓ o super-admin)
# Trava o acesso: troca a senha por uma aleatória (que ninguém vê) e encerra as sessões. É do super-admin e SEMPRE
# passa pela prévia + plan_id + confirm, até para 1 conta: a senha antiga não volta (lib/admin-bulk.sh).
# A conta de quem chama, conta de papel e super-admin NUNCA entram (voltam em `skipped`).
require_method POST
require_treino_superadmin
source "$_LIBDIR/admin-bulk.sh"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
T="$(mktemp -d)" || fail 500 "Falha ao preparar" "tmp_fail"; trap 'rm -rf "$T"' EXIT
ab_input_logins "$body" "$T/in"
ab_exclude "$T/in" "$T/cand" "$T/skip"
: > "$T/keep"
while IFS= read -r l; do
  if user_exists treino "$l"; then printf '%s\n' "$l" >> "$T/keep"; else printf '%s\tnotfound\n' "$l" >> "$T/skip"; fi
done < "$T/cand"
n="$(grep -c . "$T/keep")"; n="${n//[^0-9]/}"; n="${n:-0}"
(( n > 0 )) || FAIL_EXTRA="$(ab_skipped_json "$T/skip")" fail 404 "Nenhum usuário válido para travar" "user_notfound"
ab_limits "$n"
ab_scan treino logins "$T/keep" "$T/sess"
ns="$(grep -c . "$T/sess")"; ns="${ns//[^0-9]/}"; ns="${ns:-0}"
ab_confirm lock-user "$(ab_plan_id lock-user "$T/keep")" "$body" "$T/keep" "$ns" "$T/skip"

: > "$T/users"
while IFS= read -r l; do
  newpass="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 18)"
  [[ -n "$newpass" ]] && user_set_password treino "$l" "$newpass" && printf '%s\n' "$l" >> "$T/users"
done < "$T/keep"
removed=0
while IFS=$'\t' read -r f _lg _ip; do
  [[ -n "$f" ]] && valid_id "$f" && rm -f "$SESSIONDIR/$f" && removed=$((removed + 1))
done < "$T/sess"
nu="$(grep -c . "$T/users")"; nu="${nu//[^0-9]/}"; nu="${nu:-0}"
sk="$(grep -c . "$T/skip")"; sk="${sk//[^0-9]/}"; sk="${sk:-0}"
detail="$(ab_detail lock-user "$T/users" "$T/skip" "$removed")"
audit_log lock-user "afetados=$nu sessoes=$removed pulados=$sk ip=$(client_ip) detalhe=$detail"
ab_notify "🔒 <b>Painel do treino</b>: <b>$(ab_html "$SESSION_LOGIN")</b> TRAVOU <b>$nu</b> conta(s) (senha trocada, $removed sessão(ões) encerrada(s)) às $(printf '%(%d/%m %H:%M)T' "$EPOCHSECONDS"), IP $(client_ip). Detalhe: <code>$(ab_html "$detail")</code>"
ok_json_slurp '{locked:true, users:$u[0], users_count:($u[0]|length), sessions_removed:$n, detail:$d} + $s' \
  u "$(jq -Rn '[inputs | select(length > 0)]' < "$T/users")" \
  --argjson n "$removed" --arg d "$detail" --argjson s "$(ab_skipped_json "$T/skip")"
