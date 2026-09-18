# GET  /treino/virtual/run?contest=<cid>          -> estado + minhas runs (Bearer do TREINO)
# POST /treino/virtual/run {contest, action, …}
#   start   {accept:true, at?:<epoch>}  larga agora ou agenda (≤ 7 dias). UMA participação por conta
#                                       por contest: 409 `virtual_already` se já há uma viva/gravada.
#   cancel                              desfaz um agendamento (não gasta desistência)
#   discard                             DESISTE sem gravar: só rodando, só enquanto (≤ 15 min OU 0 AC)
#                                       e no máximo 2 vezes — a 3ª largada é definitiva
#   finish                              encerra antes do tempo; com 0 AC (e não-definitiva) vira discard
# O resultado é DERIVADO do history do treino ∩ submissões etiquetadas (`/submit … virtual:<cid>`).
require_auth_contest treino
source "$_LIBDIR/virtual.sh"
is_reserved_role_login "$SESSION_LOGIN" && fail 403 "Conta de papel não participa" "role_forbidden"
L="$SESSION_LOGIN"
if [[ "$REQUEST_METHOD" == GET ]]; then
  cid="$(param contest)"; vr_gate "$cid"
else
  require_method POST
  body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
  cid="$(jq -r '.contest // empty' <<<"$body")"; [[ -n "$cid" ]] || cid="$(param contest)"
  vr_gate "$cid"
  action="$(jq -r '.action // empty' <<<"$body")"
  vr_lock "$L" || fail 503 "Tente de novo" "virtual_busy"
  vr_refresh "$L" "$cid"
  j="$(vr_state "$L" "$cid")"; eff="$(vr_effective "$j")"
  _ac(){ local st en; IFS=$'\t' read -r st en < <(jq -r '[.start, .end]|@tsv' <<<"$j")
         vr_summary "$(vr_my_runs "$L" "$cid" "$st" "$en")" "$VR_PEN" | jq -r .ac; }
  case "$action" in
    start)
      [[ "$(jq -r '.accept == true' <<<"$body")" == true ]] || { vr_unlock; fail 422 "Aceite as regras para começar" "terms_required"; }
      case "$eff" in none|discarded) ;; *) vr_unlock; fail 409 "Você já tem uma participação virtual neste contest" "virtual_already";; esac
      at="$(jq -r '.at // empty' <<<"$body")"; at="${at//[!0-9]/}"; now="$EPOCHSECONDS"
      [[ -n "$at" ]] || at="$now"; (( at < now )) && at="$now"
      (( at > now + VR_SCHEDULE_MAX_S )) && { vr_unlock; fail 422 "Agende para no máximo 7 dias à frente" "virtual_at_invalid"; }
      disc=0; starts=0
      [[ -n "$j" ]] && IFS=$'\t' read -r disc starts < <(jq -r '[(.discards // 0), (.starts // 0)]|@tsv' <<<"$j")
      fin=false; (( disc >= VR_MAX_DISCARDS )) && fin=true
      off=false; [[ -s "$CONTESTSDIR/$cid/users/$L/history" ]] && off=true
      jq -cn --arg c "$cid" --argjson s "$at" --argjson d "$VR_DUR" --argjson disc "$disc" \
             --argjson starts "$(( starts + 1 ))" --argjson fin "$fin" --argjson off "$off" --argjson now "$now" \
        '{version:1, contest:$c, state:"active", start:$s, end:($s+$d), duration:$d, starts:$starts,
          discards:$disc, final:$fin, official:$off, created_at:$now}' \
        | _vr_write "$(vr_file "$L" "$cid")" || { vr_unlock; fail 500 "Falha ao gravar" "save_fail"; }
      : > "$(vr_subs "$L" "$cid")" ;;
    cancel)
      [[ "$eff" == scheduled ]] || { vr_unlock; fail 409 "Só dá para cancelar antes de começar" "virtual_not_scheduled"; }
      _vr_discard "$L" "$cid" "$j" 0 ;;
    discard)
      vr_can_discard "$j" "$(_ac)" || { vr_unlock; fail 409 "Desistir só vale nos primeiros 15 minutos ou sem nenhum Accepted — e no máximo $VR_MAX_DISCARDS vezes" "virtual_locked"; }
      _vr_discard "$L" "$cid" "$j" 1 ;;
    finish)
      [[ "$eff" == running ]] || { vr_unlock; fail 409 "Não há participação em andamento" "virtual_not_running"; }
      if (( $(_ac) == 0 )) && [[ "$(jq -r '.final // false' <<<"$j")" != true ]]; then
        _vr_discard "$L" "$cid" "$j" 1
      else
        jq -c --argjson now "$EPOCHSECONDS" '.end=$now | .finished_early=true' <<<"$j" | _vr_write "$(vr_file "$L" "$cid")"
        vr_refresh "$L" "$cid"
      fi ;;
    *) vr_unlock; fail 400 "Ação inválida" "action_invalid" ;;
  esac
  vr_unlock
fi
me="$(vr_me_json "$L" "$cid")"; [[ -n "$me" ]] || fail 500 "Falha ao ler a participação" "virtual_state_fail"
ok_json '{contest:$c, duration:$dur, penalty_minutes:$pen, me:$me}' \
  --arg c "$VR_CID" --argjson dur "$VR_DUR" --argjson pen "$VR_PEN" --argjson me "$me"
