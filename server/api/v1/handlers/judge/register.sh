# POST /judge/register   (Bearer mojw_<token>)
# Anuncia/atualiza a capacidade + inventário de um worker (juiz). Grava
# $REGISTRYDIR/<host>.json. Chamado pelo agent ao subir e quando o inventário muda.
# body: {host, capability, arch, cpu, mem_kb, gpu, problems:{id:mtime,...}, inv_hash}
require_method POST
require_worker
source "$_DIR/../../judge-gw/sched-lib.sh"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
host="$(jq -r '.host // empty' <<<"$body")"
[[ -n "$host" ]] || fail 400 "Missing host" "host_missing"
valid_hostname "$host" || fail 400 "Invalid host" "host_invalid"

# normaliza o registro: campos conhecidos + state=free + carimbos de tempo.
# gpu SÓ vale com compute comprovado (vendor nvidia/amd, do nvidia-smi/rocm-smi do agente);
# agente antigo mandava lspci (vendor "other") ou a MENSAGEM DE ERRO do nvidia-smi — descarta.
# E capability=gpu sem gpu real rebaixa p/ pos (need_capability=gpu nunca cai em host cego).
reg="$(jq -c --argjson now "$EPOCHSECONDS" '
  (if ((.gpu.vendor // "") | IN("nvidia","amd")) and ((.gpu.names // "") != "")
      and ((.gpu.names // "") | test("failed|error|couldn.t communicate"; "i") | not)
   then .gpu else null end) as $gpu
  | {
    host,
    capability: (if (.capability // "pos") == "gpu" and $gpu == null then "pos"
                 else (.capability // "pos") end),
    arch:    (.arch    // null),
    cpu:     (.cpu     // null),
    ncpu:    (.ncpu    // null),
    mem_kb:  (.mem_kb  // null),
    gpu:     $gpu,
    problems:(.problems// {}),
    problems_count: ((.problems // {}) | length),
    langs:   (.langs   // []),
    cage_root:(.cage_root // null),
    cache_bytes:(.cache_bytes // 0),
    inv_hash:(.inv_hash// null),
    state:   "free",
    last_seen: $now,
    registered_at: $now,
    last_update: (.last_update // null)
  }' <<<"$body" 2>/dev/null)"
[[ -n "$reg" ]] || fail 400 "Bad registration payload" "reg_bad"
reg_write "$host" "$reg" || fail 500 "Could not write registry" "reg_write_fail"

ok_json '{host:$h, registered:true, ttl:$ttl}' --arg h "$host" --argjson ttl "$REG_TTL"
