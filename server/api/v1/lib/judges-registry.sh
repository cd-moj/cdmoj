# lib/judges-registry.sh — a LISTA de juízes do registro pull (run/registry/<host>.json), para quem escolhe juízes:
# a calibração DIRECIONADA do editor de problema (GET /problems/judges) e o pool de juízes do contest
# (GET /contest/admin/judges, seletor em Regras e no assistente). Uma leitura só — as duas rotas devolvem o mesmo
# formato. Sourceada POR HANDLER.
#
# jr_list_json -> [{host, cpu, arch, langs, cage_root, last_seen, online}] (online = batida dentro do REG_TTL),
#                 ordenado: online primeiro, depois CPU e host. Nunca vazio: sem registro, "[]".
jr_list_json(){
  : "${RUNDIR:=/home/ribas/moj/run}"; : "${REGISTRYDIR:=$RUNDIR/registry}"; : "${REG_TTL:=30}"
  local out
  out="$(find "$REGISTRYDIR" -maxdepth 1 -name '*.json' -type f -exec cat {} + 2>/dev/null \
    | jq -s -c --argjson now "$EPOCHSECONDS" --argjson ttl "$REG_TTL" '
        map(select(.host) | {
              host:.host, cpu:((.cpu // "")|tostring), arch:(.arch // null),
              langs:(.langs // []), cage_root:(.cage_root // null),
              last_seen:(.last_seen // 0), online:(((.last_seen // 0)) >= ($now - $ttl)) })
        | sort_by([(.online|not), .cpu, .host])')"
  [[ -n "$out" ]] || out='[]'
  printf '%s' "$out"
}
