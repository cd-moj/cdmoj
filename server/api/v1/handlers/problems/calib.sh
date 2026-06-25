# GET /problems/calib?id=<id>   (Bearer)
# Resumo de calibração p/ o editor: por juiz (host) que calibrou — o TL calibrado (do store),
# quando, e o LOG de calibração (run/calib/<id>/<host>.json), p/ o autor ver como cada solução
# se comportou em cada juiz.
require_method GET
require_auth
source "$_DIR/lib/tl-store.sh"   # tl_store_get
: "${RUNDIR:=/home/ribas/moj/run}"; : "${CALIB_DIR:=$RUNDIR/calib}"

id="$(param id)"
[[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"

store="$(tl_store_get "$id")"; [[ -n "$store" ]] || store='{}'
logs='{}'; d="$CALIB_DIR/$id"
if [[ -d "$d" ]]; then
  logs="$(find "$d" -maxdepth 1 -name '*.json' -type f -exec cat {} + 2>/dev/null \
    | jq -s -c 'map(select(.host) | {(.host): {at:.at, checksum:.checksum, log:.log, reports:(.reports // [])}}) | add // {}')"
  [[ -n "$logs" ]] || logs='{}'
fi

emit_json 200 OK
jq -cn --argjson store "$store" --argjson logs "$logs" '
  ($store.hosts // {}) as $h
  | (($h|keys) + ($logs|keys) | unique) as $hosts
  | { success:true, id:($store.id // ""), checksum:($store.checksum // ""),
      hosts: [ $hosts[] as $n
               | { host:$n, tl:($h[$n].tl // {}),
                   at:($h[$n].at // $logs[$n].at // 0),
                   log:($logs[$n].log // null),
                   reports:($logs[$n].reports // []) } ] }'
