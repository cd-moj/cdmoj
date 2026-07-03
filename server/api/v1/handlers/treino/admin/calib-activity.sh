# GET /treino/admin/calib-activity  (.admin) -> volume de calibrações no tempo (cacheado).
# por dia + mapa de calor dia-da-semana × hora, do log append-only run/updates/log. O cálculo vive em
# server/score/treino-calib-gen.sh; aqui só servimos o cache, regenerando PREGUIÇOSAMENTE quando o log
# muda (mtime do diretório) — espelha /treino/admin/response-stats.
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
: "${RUNDIR:=/home/ribas/moj/run}"

cache="$CONTESTSDIR/treino/var/calib-activity.cache.json"
regen_locked "$CONTESTSDIR/treino/var/.calib-activity.lock" \
  "$cache" "$RUNDIR/updates/log" \
  -- bash "$SCOREDIR/treino-calib-gen.sh" "$cache"

emit_json 200 OK
if [[ -f "$cache" ]]; then
  cat "$cache"
else
  jq -cn '{success:true, calib_per_day:[], calib_by_dow_hour:[], total:0}'
fi
