# POST /judge/tl-report   (Bearer mojw_<token>)
# O juiz reporta o TL que CALIBROU p/ um problema no seu cache:
#   body: {host, id, checksum, tl:{lang:seg, ...}}
# Guardamos por host; o TL servível = MÁX entre hosts p/ o checksum reportado. Se o
# problema já mudou no servidor (checksum != atual), o report é IGNORADO como obsoleto
# (o juiz vai recalibrar). Em sucesso, dispara em background a regeneração do var/jsons
# (time_limits do treino atualizado). É chamado tanto na calibração quanto ao RELANÇAR o
# juiz (re-reporta os TLs do cache, sem recalibrar).
require_method POST
require_worker
source "$_DIR/../../judge-gw/sched-lib.sh"   # valid_hostname
source "$_DIR/lib/tl-store.sh"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
host="$(jq -r '.host // empty' <<<"$body")"; valid_hostname "$host" || fail 400 "Invalid host" "host_invalid"
id="$(jq -r '.id // empty' <<<"$body")"; valid_id "$id" || fail 400 "Invalid id" "id_invalid"
cks="$(jq -r '.checksum // empty' <<<"$body")"
[[ "$cks" =~ ^[a-f0-9]{6,64}$ ]] || fail 400 "Invalid checksum" "cks_invalid"
tl="$(jq -c '.tl // {}' <<<"$body")"

cur="$(pkg_tl_checksum "$(pkg_path "$id")")"
if [[ -n "$cur" && "$cur" != "$cks" ]]; then
  # obsoleto: o pacote no servidor mudou desde a calibração -> o juiz recalibra
  ok_json '{recorded:false, stale:true, id:$id, current_checksum:$c}' --arg id "$id" --arg c "$cur"
else
  tl_store_record "$host" "$id" "$cks" "$tl" || fail 500 "Could not store TL" "tl_store_fail"
  index_problem_bg "$id" 0
  audit_log "tl-report" "id=$id host=$host cks=${cks:0:8}"
  ok_json '{recorded:true, stale:false, id:$id, served:$srv}' \
    --arg id "$id" --argjson srv "$(tl_store_served_for "$id" "$cks")"
fi
