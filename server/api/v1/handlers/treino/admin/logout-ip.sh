# POST /treino/admin/logout-ip  {ip} [+ dry_run | plan_id + confirm]  (SÓ o super-admin)
# Encerra as sessões do treino que vieram de um IP. Num laboratório ou atrás de NAT um IP são dezenas de contas, por
# isso é do super-admin e SEMPRE passa pela prévia + plan_id + confirm (lib/admin-bulk.sh). A conta de quem chama,
# conta de papel e super-admin NUNCA entram: a sessão delas naquele IP fica (volta em `skipped`).
require_method POST
require_treino_superadmin
source "$_LIBDIR/admin-bulk.sh"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
ip="$(jq -r '.ip // empty' <<<"$body")"
[[ -n "$ip" ]] || fail 400 "Informe o IP" "missing"
[[ "$ip" =~ ^[0-9a-fA-F.:]+$ ]] || fail 400 "IP inválido" "ip_invalid"
T="$(mktemp -d)" || fail 500 "Falha ao preparar" "tmp_fail"; trap 'rm -rf "$T"' EXIT
ab_scan treino ip "$ip" "$T/all"
cut -f2 "$T/all" | awk 'NF && !s[$0]++' > "$T/in"
ab_exclude "$T/in" "$T/keep" "$T/skip"
declare -A OK=(); while IFS= read -r l; do OK["$l"]=1; done < "$T/keep"
: > "$T/sess"
while IFS=$'\t' read -r f lg sip; do [[ -n "${OK[$lg]:-}" ]] && printf '%s\t%s\t%s\n' "$f" "$lg" "$sip" >> "$T/sess"; done < "$T/all"
n="$(grep -c . "$T/keep")"; n="${n//[^0-9]/}"; n="${n:-0}"
ab_limits "$n"
ns="$(grep -c . "$T/sess")"; ns="${ns//[^0-9]/}"; ns="${ns:-0}"
ab_confirm logout-ip "$(ab_plan_id logout-ip "ip=$ip")" "$body" "$T/keep" "$ns" "$T/skip"

removed=0; : > "$T/done"
while IFS=$'\t' read -r f lg _ip; do
  [[ -n "$f" ]] && valid_id "$f" && rm -f "$SESSIONDIR/$f" && { removed=$((removed + 1)); printf '%s\n' "$lg" >> "$T/done"; }
done < "$T/sess"
awk 'NF && !s[$0]++' "$T/done" > "$T/users"
nu="$(grep -c . "$T/users")"; nu="${nu//[^0-9]/}"; nu="${nu:-0}"
sk="$(grep -c . "$T/skip")"; sk="${sk//[^0-9]/}"; sk="${sk:-0}"
detail="$(ab_detail logout-ip "$T/users" "$T/skip" "$removed" "$(jq -cn --arg ip "$ip" '{target_ip:$ip}')")"
audit_log logout-ip "ip_alvo=$ip afetados=$nu sessoes=$removed pulados=$sk ip=$(client_ip) detalhe=$detail"
ab_notify "⚠️ <b>Painel do treino</b>: <b>$(ab_html "$SESSION_LOGIN")</b> deslogou o IP <b>$ip</b>: $nu conta(s), $removed sessão(ões), às $(printf '%(%d/%m %H:%M)T' "$EPOCHSECONDS"). Detalhe: <code>$(ab_html "$detail")</code>"
ok_json_slurp '{logged_out:true, ip:$ip, users:$u[0], users_count:($u[0]|length), sessions_removed:$n, detail:$d} + $s' \
  u "$(jq -Rn '[inputs | select(length > 0)]' < "$T/users")" \
  --arg ip "$ip" --argjson n "$removed" --arg d "$detail" --argjson s "$(ab_skipped_json "$T/skip")"
