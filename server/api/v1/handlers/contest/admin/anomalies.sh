# GET /contest/admin/anomalies?contest=<c>[&round=<slug>]   (admin OU juiz-chefe)
# ANOMALIAS de uso de máquina durante a prova (motor em lib/anomalies.sh): time com 2 sessões
# vivas em máquinas diferentes, máquina com 2+ times, submissão vinda de máquina diferente da
# do login, UA fora do esperado da sede, sede com menos máquinas que times, trocas de máquina e
# a trilha da sessão única (revogações). As de MÁQUINA valem sempre que o UA do mlinux identifica a
# máquina (`machines_identified`, com ou sem gate); o ua_mismatch precisa do gate (enforce ou observe).
# Cache de resposta de 15 s por rodada (o painel atualiza a cada 30 s).
#
# POST {action:"explain", id, note}  — marca um caso como EXPLICADO (ex.: "trocou de máquina por defeito,
#      confirmado pelo chefe da sede"): sai das contagens e fica na lista, apagado, com quem/quando/nota.
#      {action:"unexplain", id}       — desfaz. `id` = o `id` da anomalia na lista (kind|login|machine).
#      Grava var/anomalies-explained.json (entrada do cache) e vai ao audit (anomaly-explain/-unexplain).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin_or_chief || fail 403 "Apenas o admin ou o juiz-chefe" "admin_required"
if [[ "${REQUEST_METHOD:-GET}" == POST ]]; then
  bodyf="$(read_body_file)"
  jq -e 'type == "object"' "$bodyf" >/dev/null 2>&1 || fail 400 "JSON inválido" "bad_json"
  act="$(jq -r '.action // ""' "$bodyf")"; aid="$(jq -r '.id // ""' "$bodyf")"
  # id = kind|login|machine — vem da própria lista; só o formato é conferido (texto, sem quebra de linha)
  [[ -n "$aid" && ${#aid} -le 600 && "$aid" != *$'\n'* && "$aid" =~ ^[a-z_]+\| ]] || fail 422 "id inválido" "id_invalid"
  xf="$CONTESTSDIR/$contest/var/anomalies-explained.json"; mkdir -p "$CONTESTSDIR/$contest/var"
  exec {_xfd}>"$xf.lock"; flock -w 5 "$_xfd" || fail 503 "ocupado, tente de novo" "busy"
  cur='{}'; [[ -s "$xf" ]] && cur="$(jq -c 'if type == "object" then . else {} end' "$xf" 2>/dev/null)"; [[ -n "$cur" ]] || cur='{}'
  xt="$xf.tmp.${BASHPID}"
  case "$act" in
    explain)
      note="$(jq -r '.note // ""' "$bodyf")"; note="${note//$'\n'/ }"
      [[ -n "${note// /}" ]] || fail 422 "Diga o motivo (ex.: troca de máquina por defeito, confirmada pela sede)" "note_required"
      (( ${#note} <= 300 )) || fail 422 "Motivo muito longo (máx. 300)" "note_long"
      jq -c --arg id "$aid" --arg by "$SESSION_LOGIN" --argjson at "$EPOCHSECONDS" --arg n "$note" \
        '.[$id] = {by:$by, at:$at, note:$n}' <<<"$cur" > "$xt" && mv -f "$xt" "$xf" || fail 500 "falha ao gravar" "write_fail"
      audit_log_to "$contest" anomaly-explain "id=${aid// /_} by=$SESSION_LOGIN" ;;
    unexplain)
      jq -c --arg id "$aid" 'del(.[$id])' <<<"$cur" > "$xt" && mv -f "$xt" "$xf" || fail 500 "falha ao gravar" "write_fail"
      audit_log_to "$contest" anomaly-unexplain "id=${aid// /_} by=$SESSION_LOGIN" ;;
    *) fail 400 "action deve ser explain|unexplain" "action_invalid" ;;
  esac
  ok_json '{saved:true, id:$id, action:$a}' --arg id "$aid" --arg a "$act"
  exit 0
fi
require_method GET
source "$_DIR/lib/users.sh"; source "$_DIR/lib/contest-create.sh"
source "$_DIR/lib/ua-gate.sh"; source "$_DIR/lib/contest-rounds.sh"; source "$_DIR/lib/anomalies.sh"

round="$(param round)"
if [[ -n "$round" ]]; then
  rd_valid_slug "$round" || fail 400 "round inválido" "round_invalid"
  [[ -n "$(rd_round "$contest" "$round")" ]] || fail 404 "Rodada não encontrada" "round_notfound"
fi
cdir="$CONTESTSDIR/$contest"
cf="$cdir/var/.anomalies-cache.${round:-active}.json"
if resp_cache_fresh "$cf" 15 "$cdir/var/access.log" "$cdir/var/submit-origin.log" \
     "$cdir/var/session-events.log" "$cdir/ua-gate.json" "$cdir/var/nutella.cache.json" \
     "$cdir/var/nutella-events.log" "$cdir/var/anomalies-explained.json"; then
  emit_json 200 OK; cat "$cf"; exit 0
fi
outf="$(mktemp)" || fail 500 "tmp" "tmp"
if ! an_build "$contest" "$round" "$outf"; then rm -f "$outf"; fail 500 "Falha ao apurar anomalias" "build_fail"; fi
[[ -s "$outf" ]] || { rm -f "$outf"; fail 500 "Falha ao apurar anomalias" "build_fail"; }
# agregado cresce com o evento: por arquivo, nunca por --argjson (ARG_MAX)
ok_json '$a[0]' --slurpfile a "$outf"
resp_cache_store "$cf" "$OK_JSON_BODY"
rm -f "$outf"
