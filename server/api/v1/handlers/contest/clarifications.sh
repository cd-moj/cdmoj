# GET /contest/clarifications?contest=<id>  (Bearer)
# Lista clarifications. admin/judge/mon veem todas; demais veem as próprias + as públicas
# já respondidas. Quem PERGUNTOU (.login + asker_name) só o juiz-chefe/admin vê (pedido do
# juiz-chefe, 2026-09-14); juiz comum e monitor seguem sem ver (tratamento isonômico).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

dir="$CONTESTSDIR/$contest/clarifications"
priv=false; { is_admin || is_judge || is_mon; } && priv=true
edit=false; is_admin_or_chief && edit=true

# dieta 2026-08-30: era 1 cat POR clarification — um cat só + jq -cs (ver updates.sh)
set +o noglob; shopt -s nullglob
_cf=("$dir"/*.json)
shopt -u nullglob
all='[]'
(( ${#_cf[@]} )) && all="$(cat "${_cf[@]}" 2>/dev/null | jq -cs 'sort_by(-.time)')"
[[ -n "$all" ]] || all='[]'
now="$EPOCHSECONDS"
if [[ "$edit" == true ]]; then
  # juiz-chefe/admin: veem quem perguntou. Mapa login -> fullname em UMA varredura (local vence a
  # fonte USERS_FROM), por arquivo — nunca um jq por clarification nem --argjson de mapa.
  NM="$(mktemp)"; trap 'rm -f "$NM" "$NM.json"' EXIT
  d="$CONTESTSDIR/$contest/users"
  [[ -d "$d" ]] && find "$d" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
    | xargs -0 -r jq -r '[.login//"", .fullname//""] | @tsv' >> "$NM" 2>/dev/null
  src="$(_users_source "$contest")"
  if [[ "$src" != "$contest" ]]; then
    find "$CONTESTSDIR/$src/users" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
      | xargs -0 -r jq -r '[.login//"", .fullname//""] | @tsv' >> "$NM" 2>/dev/null
  fi
  jq -Rn '[inputs | split("\t") | select(length >= 2 and .[0] != "") | {key:.[0], value:.[1]}] | reverse | from_entries' \
    < "$NM" > "$NM.json" 2>/dev/null || printf '{}' > "$NM.json"
  out="$(jq -c --argjson now "$now" --slurpfile nm "$NM.json" '[ .[]
    | (if ((.answer_claim.expires_at // 0) < $now) then .answer_claim=null else . end)
    | .asker_name = (if (.login // "") != "" then ($nm[0][.login] // "") else "" end) ]' <<<"$all")"
elif [[ "$priv" == true ]]; then
  # juiz/monitor coordenam a resposta (veem answer_claim e answered_by), mas NUNCA veem quem
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
# a lista inteira (texto livre de pergunta+resposta) estoura o teto de 128KiB do --argjson
# numa prova com muitas clarifications — vai por --slurpfile (ver ok_json_slurp).
# can_edit = juiz-chefe OU admin (editam resposta dada, liberam reserva alheia com force);
# is_chief fica por compat e vale o mesmo — o admin nunca ganhava o botão de editar.
ok_json_slurp '{clarifications:$c[0], can_answer:$ca, can_edit:$ce, is_chief:$ce, me:$me}' c "$out" \
  --argjson ca "$priv" --argjson ce "$edit" --arg me "$SESSION_LOGIN"
