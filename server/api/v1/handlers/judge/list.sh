# GET /judge/list   (Bearer, admin)
# Registro dos juízes: specs (CPU/mem/GPU) + inventário (nº de problemas) + estado +
# último report de atualização por juiz. Para o admin "perceber" o que cada juiz tem.
require_method GET
require_admin
source "$_DIR/../../judge-gw/sched-lib.sh"
source "$_DIR/lib/tl-store.sh"

now="$EPOCHSECONDS"
# resumo de time-limits POR HOST (do store run/tl/<id>.json): nº de problemas calibrados +
# as linguagens que o host realmente calibrou (com TL). Uma varredura só.
tlsum="$(find "$TL_STORE_DIR" -maxdepth 1 -name '*.json' 2>/dev/null | while IFS= read -r tf; do
    jq -c '(.hosts // {}) | to_entries[] | {host:.key, langs:((.value.tl//{})|keys|map(select(.!="default")))}' "$tf" 2>/dev/null
  done | jq -s -c 'group_by(.host) | map({key:.[0].host,
        value:{calibrated:length, langs:(map(.langs)|add|unique|sort)}}) | from_entries')"
[[ -n "$tlsum" ]] || tlsum='{}'

emit_json 200 OK
{
  while IFS= read -r f; do
    jq -c --argjson now "$now" --argjson ttl "$REG_TTL" --argjson tl "$tlsum" '{
      host, capability, arch, cpu, ncpu:(.ncpu//null), mem_kb, gpu,
      langs:(.langs // []), cage_root:(.cage_root // null),
      problems_count:(.problems_count // ((.problems//{})|length)),
      state, last_seen, online:((.last_seen//0) >= ($now-$ttl)),
      tl_summary:($tl[.host] // {calibrated:0, langs:[]}),
      last_update:(.last_update//null)
    }' "$f" 2>/dev/null
  done < <(find "$REGISTRYDIR" -maxdepth 1 -name '*.json' 2>/dev/null | sort)
} | jq -s -c --argjson now "$now" \
  '{success:true, time:$now, count:length,
    online:(map(select(.online))|length), busy:(map(select(.state=="busy"))|length),
    judges:sort_by(.host)}'
