# POST /ops/calib-cancel   (Bearer, admin)   body: {id, inprogress?:false}
# CANCELA calibrações de um problema na fila: remove as PENDENTES (updates/pending) e os
# comandos DIRECIONADOS ainda não entregues (commands/<host>). Por padrão NÃO toca as em
# execução (o juiz está rodando — a resposta traz `inflight` e a saída é `moj judges reset`);
# {inprogress:true} remove também os claims de updates/inprogress (o juiz ainda vai reportar
# nesse reqid — o report cai num reqid inexistente, inofensivo; use após um reset/restart).
require_method POST
# PORTÃO (16/10/2026): só o SUPER-ADMIN, com sessão do treino — antes era `require_admin` (qualquer .admin de qualquer
# contest, inclusive o admin LOCAL que todo criador de contest ganha). Ver lib/auth.sh (require_treino_superadmin).
require_treino_superadmin
source "$_DIR/../../judge-gw/sched-lib.sh"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
[[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
with_inprog="$(jq -r '.inprogress // false' <<<"$body")"

# a remoção mora no sched-lib (sched_calib_drop): a mesma do delete/move de problema
read -r removed_pending removed_targeted removed_inprog inflight < <(sched_calib_drop "$id" $( [[ "$with_inprog" == true ]] && echo inprogress ))

audit_log "calib-cancel" "id=$id pending=$removed_pending targeted=$removed_targeted inprog_removed=$removed_inprog inflight=$inflight"
ok_json '{action:"calib-cancel", id:$id, removed_pending:$p, removed_targeted:$t,
          removed_inprogress:$r, inflight:$i}' \
  --arg id "$id" --argjson p "$removed_pending" --argjson t "$removed_targeted" \
  --argjson r "$removed_inprog" --argjson i "$inflight"
