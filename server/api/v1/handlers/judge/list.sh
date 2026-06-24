# GET /judge/list   (Bearer, admin)
# Registro dos juízes: specs (CPU/mem/GPU) + inventário (nº de problemas) + estado +
# último report de atualização por juiz. Para o admin "perceber" o que cada juiz tem.
require_method GET
require_admin
source "$_DIR/../../judge-gw/sched-lib.sh"

now="$EPOCHSECONDS"
emit_json 200 OK
{
  while IFS= read -r f; do
    jq -c --argjson now "$now" --argjson ttl "$REG_TTL" '{
      host, capability, arch, cpu, ncpu:(.ncpu//null), mem_kb, gpu,
      problems_count:(.problems_count // ((.problems//{})|length)),
      state, last_seen, online:((.last_seen//0) >= ($now-$ttl)),
      last_update:(.last_update//null)
    }' "$f" 2>/dev/null
  done < <(find "$REGISTRYDIR" -maxdepth 1 -name '*.json' 2>/dev/null | sort)
} | jq -s -c --argjson now "$now" \
  '{success:true, time:$now, count:length,
    online:(map(select(.online))|length), busy:(map(select(.state=="busy"))|length),
    judges:sort_by(.host)}'
