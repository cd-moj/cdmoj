# POST /ops/judge-reset   (Bearer, admin)   body: {host, action?:"kill"|"restart"}
# RECUPERAÇÃO de um juiz sem SSH (a ferramenta que faltou no incidente 2026-07-15):
#   kill (default) — o agente SIGKILL-a o grupo de processos de CADA slot (job inteiro:
#     build-and-test+bwrap+solução), reporta judge-error/calib-fail ao servidor (nada espera
#     TTL), aplica config pendente e volta a reivindicar.
#   restart — kill como acima e o agente se RE-EXECUTA (relê config; register boot:true
#     re-enfileira o que estava atribuído).
# O comando é entregue no PRÓXIMO heartbeat MESMO com o juiz ocupado/desabilitado
# (cmd_claim_urgent fura o gate) — juiz wedgado com slots presos é exatamente o alvo.
require_method POST
# PORTÃO (16/10/2026): só o SUPER-ADMIN, com sessão do treino — antes era `require_admin` (qualquer .admin de qualquer
# contest, inclusive o admin LOCAL que todo criador de contest ganha). Ver lib/auth.sh (require_treino_superadmin).
require_treino_superadmin
source "$_DIR/../../judge-gw/sched-lib.sh"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
host="$(jq -r '.host // empty' <<<"$body")"
valid_hostname "$host" || fail 400 "Invalid host" "host_invalid"
[[ -f "$REGISTRYDIR/$host.json" ]] || fail 404 "Juiz desconhecido (sem registro)" "host_unknown"
action="$(jq -r '.action // "kill"' <<<"$body")"
[[ "$action" == kill || "$action" == restart ]] || fail 400 "action inválida (kill|restart)" "action_invalid"

cmdid="$(cmd_request "$host" "$action" "$SESSION_LOGIN")"
[[ -n "$cmdid" ]] || fail 500 "Não consegui enfileirar o comando" "cmd_fail"
audit_log "judge-reset" "host=$host action=$action cmdid=$cmdid"
ok_json '{action:$a, host:$h, cmdid:$c, status:"queued"}' \
  --arg a "$action" --arg h "$host" --arg c "$cmdid"
