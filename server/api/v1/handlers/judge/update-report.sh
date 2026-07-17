# POST /judge/update-report   (Bearer mojw_<token>)
# O worker reporta o resultado de uma atualização de repositório (NFS compartilhado).
# Guarda last_update em registry/<host>.json + o log decodificado, fecha o pedido e
# marca o worker livre.  body: {host, reqid, repo, ok, log_b64, problems_count}
require_method POST
require_worker
source "$_DIR/../../judge-gw/sched-lib.sh"
source "$_DIR/lib/tl-store.sh"   # val_summary_upsert (sumário do Painel segue o evento)

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
host="$(jq -r '.host // empty' <<<"$body")"
valid_hostname "$host" || fail 400 "Invalid host" "host_invalid"
reqid="$(jq -r '.reqid // empty' <<<"$body")"
repo="$(jq -r '.repo // empty' <<<"$body")"
ok="$(jq -r 'if .ok==true then "true" else "false" end' <<<"$body")"
pc="$(jq -r '.problems_count // 0' <<<"$body")"

# grava o log decodificado num store de update-logs
mkdir -p "$UPDATESDIR/log" 2>/dev/null
logf="$UPDATESDIR/log/$host-$EPOCHSECONDS.log"
jq -r '.log_b64 // empty' <<<"$body" | base64 -d > "$logf" 2>/dev/null || : > "$logf"

# report de index/calibrate: persiste o relatório de validação p/ a UI/CLI
target="$(jq -r '.target // empty' <<<"$body")"
if [[ -n "$target" ]] && valid_id "$target" && jq -e '.validation != null' >/dev/null 2>&1 <<<"$body"; then
  : "${RUNDIR:=/home/ribas/moj/run}"; mkdir -p "$RUNDIR/validation" 2>/dev/null
  vtmp="$RUNDIR/validation/.$target.tmp"
  jq -c '.validation' <<<"$body" > "$vtmp" 2>/dev/null && mv -f "$vtmp" "$RUNDIR/validation/$target.json" \
    && val_summary_upsert "$target"
fi

# anexa last_update ao registro do host
reg_set "$host" \
  '.last_update = {repo:$repo, ok:$ok, problems_count:$pc, at:$now, log:$log}' \
  --arg repo "$repo" --argjson ok "$ok" --argjson pc "${pc:-0}" \
  --arg log "$(basename "$logf")" --argjson now "$EPOCHSECONDS" 2>/dev/null || true

[[ "$reqid" =~ ^[a-f0-9]+$ ]] && upd_done "$host" "$reqid"
reg_touch_state "$host" free 2>/dev/null || true

ok_json '{host:$h, recorded:true}' --arg h "$host"
