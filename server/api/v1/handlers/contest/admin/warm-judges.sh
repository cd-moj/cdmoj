# POST /contest/admin/warm-judges?contest=<id>   (admin ou juiz-chefe DO contest)
# "🔥 Aquecer juízes" (Central › Falta para começar, item judges_warm): manda um `calibrate` DIRIGIDO
# (o mesmo comando do editor, /problems/request-calibration com hosts) a cada par juiz×problema que o
# jw_matrix (lib/judge-warm.sh) acha FRIO — juiz online do pool efetivo do problema que ainda não
# calibrou a versão atual. O juiz o recebe no heartbeat, baixa o pacote, calibra e reporta o TL; a
# 1ª submissão do problema naquele juiz deixa de esperar por isso (7,3 min na XIV Maratona UnB).
#   · par QUENTE não recebe nada (o calibrate dirigido é FULL: recalibrar quem já está pronto só
#     gastaria slot); par AQUECENDO (comando na fila ou em execução) não é repetido;
#   · sob flock: dois cliques não duplicam (o 2º recalcula e já vê os pares "aquecendo");
#   · cada calibração ocupa um slot do juiz por alguns minutos — é p/ ANTES do início (a UI avisa).
# Não abre pacote nenhum (fronteira): quem baixa e calibra é o juiz.
# body: {} (nada)  -> {sent:[{host,id,letter,cmdid}], before:{warm,warming,cold}}
# O núcleo é jw_warm (lib/judge-warm.sh) — o mesmo do bin/warm-judges.sh (promoção de rodada e o aquecimento
# automático ~15 min antes do início, que o judged dispara).
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin_or_chief || fail 403 "Apenas o admin ou o juiz-chefe" "admin_required"
source "$_DIR/../../judge-gw/sched-lib.sh"
source "$_DIR/lib/tl-store.sh"
source "$_DIR/lib/judge-warm.sh"

CONTEST_JUDGES=""; PROBS=()
load_contest_conf "$contest"

SENT="$(mktemp)"; trap 'rm -f "$SENT"' EXIT
counts="$(jw_warm "$contest" "$SESSION_LOGIN" "$SENT")"; rc=$?
(( rc == 2 )) && fail 409 "Outro pedido de aquecimento deste contest está em andamento" "warm_busy"
(( rc == 0 )) && [[ -n "$counts" ]] || fail 500 "Falha ao montar o mapa de juízes" "warm_matrix_fail"
n="$(grep -c . "$SENT" 2>/dev/null)"; n="${n//[^0-9]/}"; n="${n:-0}"
audit_log_to "$contest" warm-judges "sent=$n $(jq -r '"cold=\(.cold) warming=\(.warming) warm=\(.warm)"' <<<"$counts")"
ok_json_slurp '{sent:$s[0], before:$b}' \
  s "$(jq -Rsc 'split("\n") | map(select(length > 0) | split("\t") | {host:.[0], id:.[1], letter:.[2], cmdid:.[3]})' < "$SENT")" \
  --argjson b "$counts"
