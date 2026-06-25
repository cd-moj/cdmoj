# POST /judge/calib-report   (Bearer mojw_<token>)
# O juiz reporta o LOG de calibração de um problema, por host. Guardamos em
# run/calib/<id>/<host>.json {host, checksum, at, log} p/ o autor inspecionar, no editor,
# como cada solução se comportou em cada juiz.
#   body: {host, id, checksum, log}
require_method POST
require_worker
source "$_DIR/../../judge-gw/sched-lib.sh"   # valid_hostname
: "${RUNDIR:=/home/ribas/moj/run}"; : "${CALIB_DIR:=$RUNDIR/calib}"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
host="$(jq -r '.host // empty' <<<"$body")"; valid_hostname "$host" || fail 400 "Invalid host" "host_invalid"
id="$(jq -r '.id // empty' <<<"$body")"; valid_id "$id" || fail 400 "Invalid id" "id_invalid"
cks="$(jq -r '.checksum // empty' <<<"$body")"; [[ "$cks" =~ ^[a-f0-9]{0,64}$ ]] || cks=""

d="$CALIB_DIR/$id"; mkdir -p "$d" 2>/dev/null
f="$d/$host.json"; tmp="$f.tmp.$$"
( umask 077; jq -c --arg h "$host" --arg c "$cks" --argjson now "$EPOCHSECONDS" \
    '{host:$h, checksum:$c, at:$now, log:(.log // "")}' <<<"$body" ) > "$tmp" 2>/dev/null \
  && mv -f "$tmp" "$f" || { rm -f "$tmp"; fail 500 "Could not store calib log" "calib_store_fail"; }
audit_log "calib-report" "id=$id host=$host cks=${cks:0:8}"
ok_json '{recorded:true, id:$id, host:$h}' --arg id "$id" --arg h "$host"
