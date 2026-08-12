# POST /ops/relatorio   (AUTH: bot token — require_bot; GATE: admin pelo telegram_id)
# body: {telegram_id, args:[...]}   — args = as palavras depois de /relatorio, verbatim.
#
# Painel de submissões do mojinho p/ o grupo dos professores (top-10 de contests no
# período + treino + comparações com o ano anterior). Subcomandos:
#   (vazio)            relatório do semestre configurado, [inicio, agora]
#   AAAA-MM-DD         override pontual: [essa data 00:00, agora]
#   config <ini> <fim> grava o semestre (quartis passam a ser enviados automaticamente
#                      pelo sweep do /ops/alerts; vencidos entram pré-marcados)
#   status             config, quartis, o que já foi enviado, próximo envio
#
# O bot NÃO sabe quem é admin — a política mora AQUI: só conta *.admin do treino com
# Telegram vinculado (o MESMO conjunto que recebe alertas). Cliente hostil não fura.
require_method POST
require_bot
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
tgid="$(jq -r '.telegram_id // empty' <<<"$body")"
valid_tgid "$tgid" || fail 400 "telegram_id inválido" "tgid_invalid"

login="$(tg_login_of_id treino "$tgid")"
[[ "$login" == *.admin ]] \
  || fail 403 "Apenas admins do MOJ (conta .admin com Telegram vinculado ao seu Telegram)" "admin_required"

source "$_DIR/lib/relatorio.sh"
mapfile -t args < <(jq -r '(.args // [])[]' <<<"$body")
sub="${args[0]:-}"
now="$EPOCHSECONDS"
NOTCONF_MSG="Semestre não configurado — use /relatorio config AAAA-MM-DD AAAA-MM-DD"

case "$sub" in
  config)
    di="${args[1]:-}"; df="${args[2]:-}"
    i="$(rel_parse_date "$di")"      || fail 422 "Data de início inválida ('$di') — use AAAA-MM-DD" "bad_date"
    f="$(rel_parse_date "$df" end)"  || fail 422 "Data de fim inválida ('$df') — use AAAA-MM-DD" "bad_date"
    (( i < f )) || fail 422 "O início tem de ser antes do fim" "bad_range"
    rel_conf_set "$i" "$f" "$login" || fail 500 "Falha ao gravar a configuração" "conf_fail"
    audit_log_to treino relatorio-config "por $login: $di a $df"
    read -r -a b <<<"$(rel_quartil_bounds "$i" "$f")"
    html="✅ Semestre configurado: <b>$(fmt_epoch "$i" '%d/%m/%Y') – $(fmt_epoch "$f" '%d/%m/%Y')</b>"$'\n'
    html+="Relatórios automáticos no grupo ao fim de cada quartil:"$'\n'
    for k in 1 2 3 4; do
      mark=""; (( now >= b[k-1] )) && mark=" — já vencido (não reenvio retroativo)"
      html+="Q$k: $(fmt_epoch "${b[k-1]}" '%d/%m/%Y')$mark"$'\n'
    done
    html+=$'\n'"Peça um agora com /relatorio."
    ok_json '{html:$h}' --arg h "$html"
    ;;

  status)
    cj="$(rel_conf_get)"
    i="$(jq -r '.inicio // empty' <<<"$cj")"; f="$(jq -r '.fim // empty' <<<"$cj")"
    [[ "$i" =~ ^[0-9]+$ && "$f" =~ ^[0-9]+$ ]] || fail 409 "$NOTCONF_MSG" "not_configured"
    read -r -a b <<<"$(rel_quartil_bounds "$i" "$f")"
    html="📊 Relatório — configuração"$'\n'
    html+="Semestre: <b>$(fmt_epoch "$i" '%d/%m/%Y') – $(fmt_epoch "$f" '%d/%m/%Y')</b>"
    html+=" (por $(rel_esc "$(jq -r '.configured_by // "?"' <<<"$cj")"))"$'\n'
    for k in 1 2 3 4; do
      s="$(jq -r --arg k "$k" '.sent[$k] // empty' <<<"$cj")"
      when="$(fmt_epoch "${b[k-1]}" '%d/%m/%Y')"
      if [[ "$s" == 0 ]]; then st="◦ pré-marcado na configuração (sem envio)"
      elif [[ "$s" =~ ^[0-9]+$ ]]; then st="✓ enviado em $(fmt_epoch "$s" '%d/%m %H:%M')"
      elif (( now >= b[k-1] )); then st="⏳ pendente — sai no próximo ciclo (≤1h)"
      else st="agendado"; fi
      html+="Q$k ($when): $st"$'\n'
    done
    cache="$(rel_cache_file)"
    if [[ -f "$cache" ]]; then
      html+="Cache: gerado há $(( (now - $(stat -c %Y "$cache" 2>/dev/null || echo "$now")) / 60 )) min"
    else
      html+="Cache: vazio (primeiro /relatorio vai gerar)"
    fi
    ok_json '{html:$h}' --arg h "$html"
    ;;

  ""|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
    label=""
    if [[ -n "$sub" ]]; then
      since="$(rel_parse_date "$sub")" || fail 400 "Data inválida ('$sub') — use AAAA-MM-DD" "bad_date"
      (( since < now )) || fail 400 "Essa data está no futuro" "bad_date"
    else
      cj="$(rel_conf_get)"
      i="$(jq -r '.inicio // empty' <<<"$cj")"; f="$(jq -r '.fim // empty' <<<"$cj")"
      [[ "$i" =~ ^[0-9]+$ && "$f" =~ ^[0-9]+$ ]] || fail 409 "$NOTCONF_MSG" "not_configured"
      (( now >= i )) || fail 409 "O semestre configurado ainda não começou ($(fmt_epoch "$i" '%d/%m/%Y'))" "not_started"
      since="$i"
      if (( now >= f )); then label="quartil <b>4/4</b> (encerrado)"
      else label="quartil <b>$(rel_quartil_now "$i" "$f" "$now")/4</b>"; fi
    fi
    rel_generate "$since" "$now" "$(rel_cache_file)"
    case $? in
      0) ;;
      2) ok_json '{html:$h, pending:true}' \
           --arg h "⏳ A base estava fria — estou terminando o relatório em segundo plano. Mande /relatorio de novo em ~1 minuto."
         exit 0 ;;
      *) fail 500 "Falha ao gerar o relatório (tente de novo em instantes)" "gen_fail" ;;
    esac
    html="$(rel_html "$(rel_cache_file)" "$label")"
    [[ -n "$html" ]] || fail 500 "Falha ao montar o relatório" "gen_fail"
    ok_json '{html:$h}' --arg h "$html"
    ;;

  *)
    fail 400 "Não entendi '$sub'. Use: /relatorio [AAAA-MM-DD] | config <início> <fim> | status" "bad_args"
    ;;
esac
