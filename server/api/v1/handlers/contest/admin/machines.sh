# GET /contest/admin/machines?contest=<c>[&round=<slug>]   (admin OU juiz-chefe)
# MAPA DE MÁQUINAS da rodada: time × IP × User-Agent. É no aquecimento que os times ligam as
# máquinas de verdade, então é ali que se descobre de onde cada um vem — e, na prova oficial, quem
# mudou de máquina (`changed`, comparado com o machines.json da última rodada arquivada).
#
# Fonte: contests/<c>/var/access.log (TSV epoch/login/ip/ua_b64, escritor único no login),
# recortado pela JANELA da rodada. Nada novo é capturado.
#
# SÓ LEITURA — as ações reusam endpoints que já existem:
#   preencher a sede do time -> POST /contest/admin/teams {set:{"<login>":{region:"<sede>"}}}
#   armar o gate de UA       -> POST /contest/admin/settings {login_ua_substring:"…"}
# GET -> {round, prev_round, window, by_login:[…], by_ip:[…], uas:[{ua,n}], ua_suggestion, totals}
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin_or_chief || fail 403 "Apenas o admin ou o juiz-chefe" "admin_required"
source "$_DIR/lib/users.sh"; source "$_DIR/lib/contest-create.sh"
source "$_DIR/lib/contest-rounds.sh"

round="$(param round)"
if [[ -n "$round" ]]; then
  rd_valid_slug "$round" || fail 400 "round inválido" "round_invalid"
  [[ -n "$(rd_round "$contest" "$round")" ]] || fail 404 "Rodada não encontrada" "round_notfound"
fi

m="$(rd_machines "$contest" "$round")"
[[ -n "$m" ]] || fail 500 "Falha ao montar o mapa de máquinas" "build_fail"

# UA vem em base64 do access.log (o login grava assim p/ não injetar no arquivo *sourced*).
# `ua_suggestion` = maior substring COMUM a todos os UAs vistos (candidata ao gate de UA; com
# navegadores diferentes na sala ela fica curta ou vazia — a UI diz isso em vez de fingir).
# --- decodifica os UAs (o access.log guarda base64) e calcula a substring COMUM --------------
# jq não tem LCS: a maior substring comum a todos os UAs sai daqui, testando as substrings do
# MENOR deles (UA tem ~120 chars, então é barato). Vazia = navegadores diferentes na sala; a UI
# mostra a lista e deixa o admin escolher, em vez de fingir que um gate único serve.
uas_file="$(mktemp)"
jq -r '[ .by_login[]?.uas[]? ] | unique | .[]' <<<"$m" 2>/dev/null \
  | while IFS= read -r b; do printf '%s' "$b" | base64 -d 2>/dev/null; printf '\n'; done \
  | grep -v '^[[:space:]]*$' | sort -u > "$uas_file"
sug=""
if [[ -s "$uas_file" ]]; then
  shortest="$(awk '{print length"\t"$0}' "$uas_file" | sort -n | head -n1 | cut -f2-)"
  n=${#shortest}
  for ((len=n; len>=8; len--)); do
    for ((off=0; off+len<=n; off++)); do
      cand="${shortest:off:len}"
      if ! grep -qvF -- "$cand" "$uas_file"; then sug="$cand"; break; fi
    done
    [[ -n "$sug" ]] && break
  done
fi

out="$(jq -c --rawfile uas "$uas_file" --arg sug "$sug" '
  def dec: (try (. | @base64d) catch "");
  . + { uas: ($uas | split("\n") | map(select(length > 0))),
        ua_suggestion: $sug,
        by_login: [ .by_login[] | . + { uas: [ .uas[] | dec ],
                    pairs: [ .pairs[] | (. + {ua: (.ua64 | dec)}) | del(.ua64) ] } ] }' <<<"$m")"
rm -f "$uas_file"
[[ -n "$out" ]] || fail 500 "Falha ao montar a resposta" "build_fail"
audit_log_to "$contest" machines-view "round=${round:-ativa}"
emit_json 200 OK
jq -cn --argjson m "$out" '{success:true} + $m'
