# GET /contest/statistics?contest=<id>  (admin/judge/mon) -> estatísticas agregadas (cacheadas).
# O cálculo vive em server/score/stats-gen.sh (análogo ao build.sh do placar); aqui só
# servimos o cache JSON, regenerando-o PREGUIÇOSAMENTE quando var/.score-dirty (tocado a
# cada escrita de history) ou o conf mudam — espelhando o placar: não reprocessa quando
# nada aconteceu, mas gera na hora se ainda não houver nada gerado.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_admin || is_judge || is_mon; } || fail 403 "Apenas admin/judge/monitor" "stats_forbidden"

cache="$CONTESTSDIR/$contest/var/statistics.cache.json"
regen_locked "$CONTESTSDIR/$contest/var/.stats.lock" \
  "$cache" "$CONTESTSDIR/$contest/var/.score-dirty" "$CONTESTSDIR/$contest/conf" \
  -- bash "$SCOREDIR/stats-gen.sh" "$contest" "$cache"

emit_json 200 OK
if [[ -f "$cache" ]]; then
  cat "$cache"
else
  jq -cn '{success:true, totals:{submissions:0,accepted:0,users:0,problems_solved:0}, problems:[], languages:[], verdicts:[], timeline:[]}'
fi
