# GET /treino/virtual/info?contest=<cid>   (Bearer do TREINO)
# Participação virtual: o que dá p/ saber ANTES de largar — título, duração, nº de problemas — e o
# estado da run deste login. Contest não elegível (rodando, secreto, congelado, módulo desligado,
# problema não-público, inexistente) = 404 `virtual_unavailable`, SEMPRE o mesmo corpo.
require_method GET
require_auth_contest treino
source "$_LIBDIR/virtual.sh"
cid="$(param contest)"
vr_gate "$cid"
is_reserved_role_login "$SESSION_LOGIN" && me='{"state":"forbidden"}' || me="$(vr_me_json "$SESSION_LOGIN" "$cid")"
[[ -n "$me" ]] || fail 500 "Falha ao ler a participação" "virtual_state_fail"
ok_json '{contest:$c, title:$t, start_time:$st, duration:$dur, penalty_minutes:$pen, problems_count:$np,
          rules:{grace_s:$grace, max_discards:$max, schedule_max_s:$sched}, me:$me}' \
  --arg c "$VR_CID" --arg t "$VR_TITLE" --argjson st "$VR_START" --argjson dur "$VR_DUR" \
  --argjson pen "$VR_PEN" --argjson np "${#VR_CANON[@]}" --argjson grace "$VR_GRACE_S" \
  --argjson max "$VR_MAX_DISCARDS" --argjson sched "$VR_SCHEDULE_MAX_S" --argjson me "$me"
