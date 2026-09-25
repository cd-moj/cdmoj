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

mkdir -p "$CMDDIR" 2>/dev/null
exec {_wfd}>"$CMDDIR/.warm-$contest.lock" 2>/dev/null && flock -w 20 "$_wfd" 2>/dev/null \
  || fail 409 "Outro pedido de aquecimento deste contest está em andamento" "warm_busy"
wm="$(jw_matrix "$contest")"
jq -e '.counts' >/dev/null 2>&1 <<<"$wm" || fail 500 "Falha ao montar o mapa de juízes" "warm_matrix_fail"
SENT="$(mktemp)"; trap 'rm -f "$SENT"' EXIT
while IFS=$'\t' read -r h id letter; do
  valid_hostname "$h" && valid_id "$id" || continue
  cid="$(cmd_request "$h" calibrate "$SESSION_LOGIN" "$id")" || continue
  [[ -n "$cid" ]] && printf '%s\t%s\t%s\t%s\n' "$h" "$id" "$letter" "$cid" >> "$SENT"
done < <(jq -r '.cold[] | [.host, .id, .letter] | @tsv' <<<"$wm")
eval "exec ${_wfd}>&-"
n="$(grep -c . "$SENT" 2>/dev/null)"; n="${n//[^0-9]/}"; n="${n:-0}"
audit_log_to "$contest" warm-judges "sent=$n $(jq -r '"cold=\(.counts.cold) warming=\(.counts.warming) warm=\(.counts.warm)"' <<<"$wm")"
ok_json_slurp '{sent:$s[0], before:$b}' \
  s "$(jq -Rsc 'split("\n") | map(select(length > 0) | split("\t") | {host:.[0], id:.[1], letter:.[2], cmdid:.[3]})' < "$SENT")" \
  --argjson b "$(jq -c '.counts' <<<"$wm")"
