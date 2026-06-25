# POST /judge/calib-report   (Bearer mojw_<token>)
# O juiz reporta o LOG de calibração de um problema, por host, + o report.html POR SOLUÇÃO.
# Guardamos em run/calib/<id>/<host>.json {host,checksum,at,log,reports:[nomes]} e cada report
# em run/calib/<id>/r/<host>/<nome>.html — p/ o autor inspecionar no editor.
#   body: {host, id, checksum, log, reports:[{name, html_b64}]}
require_method POST
require_worker
source "$_DIR/../../judge-gw/sched-lib.sh"   # valid_hostname
: "${RUNDIR:=/home/ribas/moj/run}"; : "${CALIB_DIR:=$RUNDIR/calib}"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
host="$(jq -r '.host // empty' <<<"$body")"; valid_hostname "$host" || fail 400 "Invalid host" "host_invalid"
id="$(jq -r '.id // empty' <<<"$body")"; valid_id "$id" || fail 400 "Invalid id" "id_invalid"
cks="$(jq -r '.checksum // empty' <<<"$body")"; [[ "$cks" =~ ^[a-f0-9]{0,64}$ ]] || cks=""

d="$CALIB_DIR/$id"; rdir="$d/r/$host"; mkdir -p "$d" "$rdir" 2>/dev/null
# salva cada report.html por solução (decodifica base64) e coleta os nomes
rm -f "$rdir"/*.html 2>/dev/null; names='[]'
while IFS= read -r rep; do
  rn="$(jq -r '.name // empty' <<<"$rep" | tr -cd 'A-Za-z0-9._-')"; [[ -n "$rn" ]] || continue
  if jq -r '.html_b64 // ""' <<<"$rep" | base64 -d > "$rdir/$rn.html" 2>/dev/null; then
    names="$(jq -c --arg n "$rn" '. + [$n]' <<<"$names")"
  fi
done < <(jq -c '.reports[]?' <<<"$body")

f="$d/$host.json"; tmp="$f.tmp.$$"
( umask 077; jq -c --arg h "$host" --arg c "$cks" --argjson now "$EPOCHSECONDS" --argjson reps "$names" \
    '{host:$h, checksum:$c, at:$now, log:(.log // ""), reports:$reps}' <<<"$body" ) > "$tmp" 2>/dev/null \
  && mv -f "$tmp" "$f" || { rm -f "$tmp"; fail 500 "Could not store calib log" "calib_store_fail"; }
audit_log "calib-report" "id=$id host=$host cks=${cks:0:8} reports=$(jq 'length' <<<"$names")"
ok_json '{recorded:true, id:$id, host:$h}' --arg id "$id" --arg h "$host"
