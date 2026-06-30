# GET /treino/admin/response-stats  (.admin) -> tempo de resposta do treino (cacheado).
# espera (submit->veredito), julgamento (duration_s) e fila — geral, por dia (média) e mapa
# de calor dia-da-semana × hora. Só conta submissões com finalized_at (único timestamp de
# veredito persistido); a cobertura (history_total vs with_finalized) vai no JSON.
# O cálculo vive em server/score/treino-response-gen.sh; aqui só servimos o cache, regenerando
# PREGUIÇOSAMENTE quando controle/history ou results/ mudam — espelha /contest/statistics.
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"

cache="$CONTESTSDIR/treino/var/response-stats.cache.json"
regen_locked "$CONTESTSDIR/treino/var/.response-stats.lock" \
  "$cache" "$CONTESTSDIR/treino/controle/history" "$CONTESTSDIR/treino/results" \
  -- bash "$SCOREDIR/treino-response-gen.sh" treino "$cache"

emit_json 200 OK
if [[ -f "$cache" ]]; then
  cat "$cache"
else
  jq -cn '{success:true, coverage:{history_total:0,with_finalized:0},
           overall:{n:0,avg_wait_s:0,p50_wait_s:0,p95_wait_s:0,max_wait_s:0,avg_judge_s:0,avg_queue_s:0},
           per_day:[], by_dow_hour:[]}'
fi
