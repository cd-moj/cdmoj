# GET /problems/calib?id=<id>   (Bearer)
# Resumo de calibração p/ o editor: por juiz (host) que calibrou — o TL calibrado (do store),
# quando, e o LOG de calibração (run/calib/<id>/<host>.json), p/ o autor ver como cada solução
# se comportou em cada juiz.
require_method GET
require_auth
source "$_DIR/lib/tl-store.sh"; source "$_DIR/lib/gitea.sh"; source "$_DIR/lib/problems.sh"
: "${RUNDIR:=/home/ribas/moj/run}"; : "${CALIB_DIR:=$RUNDIR/calib}"

id="$(param id)"
[[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
require_problem_edit "$id"   # log de calibração revela comportamento das soluções -> só dono/colaborador

store="$(tl_store_get "$id")"; [[ -n "$store" ]] || store='{}'
logs='{}'; d="$CALIB_DIR/$id"
if [[ -d "$d" ]]; then
  logs="$(find "$d" -maxdepth 1 -name '*.json' -type f -exec cat {} + 2>/dev/null \
    | jq -s -c 'map(select(.host) | {(.host): {at:.at, checksum:.checksum, log:.log, reports:(.reports // [])}}) | add // {}')"
  [[ -n "$logs" ]] || logs='{}'
fi

# linguagens das soluções good (extensão) — p/ apontar as que NÃO calibraram (falharam). O -o noglob
# da API vale aqui -> uso find, não glob.
pkg="$(pkg_path "$id")"; goodlangs='[]'
if [[ -n "$pkg" && -d "$pkg/sols/good" ]]; then
  goodlangs="$(find "$pkg/sols/good" -maxdepth 1 -type f 2>/dev/null \
    | while IFS= read -r gf; do e="${gf##*.}"; [[ "$e" != "$gf" ]] && echo "$e"; done \
    | LC_ALL=C sort -u | jq -Rsc 'split("\n")|map(select(length>0))')"
  [[ -n "$goodlangs" ]] || goodlangs='[]'
fi

emit_json 200 OK
jq -cn --argjson store "$store" --argjson logs "$logs" --argjson gl "$goodlangs" '
  ($store.hosts // {}) as $h
  | (($h|keys) + ($logs|keys) | unique) as $hosts
  | ([ $h[]?.tl // {} | keys[] | select(.!="default") ] | unique) as $served   # calibrado em >=1 host
  | { success:true, id:($store.id // ""), checksum:($store.checksum // ""),
      good_langs:$gl,
      missing_langs:[ $gl[] | select(. as $g | ($served|index($g)|not)) ],     # sem TL em NENHUM host
      hosts: [ $hosts[] as $n
               | ($h[$n].tl // {}) as $htl
               | { host:$n, tl:$htl,
                   missing:[ $gl[] | select(. as $g | ($htl|has($g)|not)) ],   # sem TL NESTE host
                   at:($h[$n].at // $logs[$n].at // 0),
                   log:($logs[$n].log // null),
                   reports:($logs[$n].reports // []) } ] }'
