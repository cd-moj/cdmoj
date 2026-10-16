# POST /treino/admin/logout-user  {login} | {logins:[...]} [+ dry_run | plan_id + confirm]  (.admin do treino)
# Encerra as sessões do treino dos usuários informados. As regras de ação de vários alvos são da lib/admin-bulk.sh
# (16/10/2026: um .admin comum deslogou 1.310 contas de uma vez, ele mesmo e o super-admin inclusive):
#   · a conta de quem chama, conta de papel e super-admin NUNCA entram (voltam em `skipped`);
#   · 1 alvo: executa direto; 2..20: prévia + plan_id + confirm (o número de contas); mais de 20: só o super-admin.
require_method POST
require_treino_admin
source "$_LIBDIR/admin-bulk.sh"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
T="$(mktemp -d)" || fail 500 "Falha ao preparar" "tmp_fail"; trap 'rm -rf "$T"' EXIT
ab_input_logins "$body" "$T/in"
ab_exclude "$T/in" "$T/keep" "$T/skip"
n="$(grep -c . "$T/keep")"; n="${n//[^0-9]/}"; n="${n:-0}"
(( n > 0 )) || FAIL_EXTRA="$(ab_skipped_json "$T/skip")" \
  fail 422 "Nenhuma conta para deslogar: a sua, as de papel (.admin, .judge…) e a do super-admin nunca entram" "no_targets"
ab_limits "$n"
ab_scan treino logins "$T/keep" "$T/sess"
cut -f2 "$T/sess" | awk 'NF && !s[$0]++' > "$T/aff"
ns="$(grep -c . "$T/sess")"; ns="${ns//[^0-9]/}"; ns="${ns:-0}"
# 2+ alvos SEMPRE passam pela prévia; 1 alvo só quando a tela a pede (dry_run)
if (( n > 1 )) || [[ "$(jq -r '.dry_run == true' <<<"$body")" == true ]]; then
  ab_confirm logout-user "$(ab_plan_id logout-user "$T/keep")" "$body" "$T/aff" "$ns" "$T/skip"
fi

# executa: apaga as sessões achadas na varredura (a confirmação por `source` já foi feita nela)
removed=0; : > "$T/done"
while IFS=$'\t' read -r f lg _ip; do
  [[ -n "$f" ]] && valid_id "$f" && rm -f "$SESSIONDIR/$f" && { removed=$((removed + 1)); printf '%s\n' "$lg" >> "$T/done"; }
done < "$T/sess"
awk 'NF && !s[$0]++' "$T/done" > "$T/users"
nu="$(grep -c . "$T/users")"; nu="${nu//[^0-9]/}"; nu="${nu:-0}"
sk="$(grep -c . "$T/skip")"; sk="${sk//[^0-9]/}"; sk="${sk:-0}"
detail="$(ab_detail logout-user "$T/users" "$T/skip" "$removed")"
audit_log logout-user "afetados=$nu sessoes=$removed pulados=$sk ip=$(client_ip) detalhe=$detail"
if (( n > 1 )); then
  ab_notify "⚠️ <b>Painel do treino</b>: <b>$(ab_html "$SESSION_LOGIN")</b> deslogou <b>$nu</b> conta(s) ($removed sessão(ões)) às $(printf '%(%d/%m %H:%M)T' "$EPOCHSECONDS"), IP $(client_ip). Pulados: $sk. Detalhe: <code>$(ab_html "$detail")</code>"
fi
ok_json_slurp '{logged_out:true, users:$u[0], users_count:($u[0]|length), sessions_removed:$n, detail:$d} + $s' \
  u "$(jq -Rn '[inputs | select(length > 0)]' < "$T/users")" \
  --argjson n "$removed" --arg d "$detail" --argjson s "$(ab_skipped_json "$T/skip")"
