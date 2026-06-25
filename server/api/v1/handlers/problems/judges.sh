# GET /problems/judges   (Bearer)
# Lista os juízes (do registro pull) p/ a calibração DIRECIONADA do editor: host, modelo de CPU,
# linguagens e se está online. O editor agrupa por CPU p/ oferecer "1 por processador".
require_method GET
require_auth
: "${RUNDIR:=/home/ribas/moj/run}"; : "${REGISTRYDIR:=$RUNDIR/registry}"; : "${REG_TTL:=30}"
now="$EPOCHSECONDS"

out="$(find "$REGISTRYDIR" -maxdepth 1 -name '*.json' -type f -exec cat {} + 2>/dev/null \
  | jq -s -c --argjson now "$now" --argjson ttl "$REG_TTL" '
      map(select(.host) | {
            host:.host, cpu:((.cpu // "")|tostring), arch:(.arch // null),
            langs:(.langs // []), cage_root:(.cage_root // null),
            last_seen:(.last_seen // 0), online:(((.last_seen // 0)) >= ($now - $ttl)) })
      | sort_by([(.online|not), .cpu, .host])')"
[[ -n "$out" ]] || out='[]'

emit_json 200 OK
jq -cn --argjson j "$out" '{success:true, judges:$j}'
