# GET /index/status  (PÚBLICO) — health do MOJ para a página de status.
# Agrega: fila de submissões (total + por lista), spool, juízes (modelo PULL: registro +
# heartbeat) e liveness dos daemons locais. Cache de 20s (RUNDIR/status.json). Não expõe
# hostnames/IPs (só contagens + agregados de capacidade).
: "${RUNDIR:=/home/ribas/moj/run}"
CACHE="$RUNDIR/status.json"
now="$EPOCHSECONDS"

emit_json 200 OK

# cache fresco (< 20s)? devolve direto.
if [[ -f "$CACHE" ]]; then
  ca="$(jq -r '.time // 0' "$CACHE" 2>/dev/null)"
  if [[ "$ca" =~ ^[0-9]+$ ]] && (( now - ca < 20 )); then cat "$CACHE"; exit 0; fi
fi

# --- fila por lista (users/*/history via count_pending) + spool ---
set +o noglob; shopt -s nullglob
declare -a LISTS; total=0
for cdir in "$CONTESTSDIR"/*/; do
  cdir="${cdir%/}"; cid="${cdir##*/}"
  [[ -f "$cdir/conf" ]] || continue
  n="$(count_pending "$cid")"; n="${n//[^0-9]/}"; n="${n:-0}"
  if (( n > 0 )); then
    ((total+=n))
    # contest SUPER SECRETO: conta no total mas NÃO expõe id/nome na página pública
    contest_is_secret "$cid" && continue
    cname="$( . "$cdir/conf" 2>/dev/null; printf '%s' "${CONTEST_NAME:-$cid}" )"
    LISTS+=("$(jq -cn --arg c "$cid" --arg nm "$cname" --argjson n "$n" '{contest:$c,name:$nm,pending:$n}')")
  fi
done
shopt -u nullglob
lists="$( ((${#LISTS[@]})) && printf '%s\n' "${LISTS[@]}" | jq -cs 'sort_by(-.pending)' || echo '[]')"
spool=0; [[ -d "$SPOOLDIR" ]] && spool="$(find "$SPOOLDIR" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | wc -l)"

# --- juízes (modelo PULL): online = heartbeat fresco; ocupado = state busy ---
: "${REGISTRYDIR:=$RUNDIR/registry}"; : "${QUEUEDIR:=$RUNDIR/queue}"; : "${REG_TTL:=30}"
jonline=0; jbusy=0; jtotal=0; cpus=0; gpus=0
while IFS= read -r rf; do
  ((jtotal++))
  ls="$(jq -r '.last_seen // 0' "$rf" 2>/dev/null)"; [[ "$ls" =~ ^[0-9]+$ ]] || ls=0
  (( ls >= now - REG_TTL )) || continue
  ((jonline++))
  [[ "$(jq -r '.state // ""' "$rf" 2>/dev/null)" == busy ]] && ((jbusy++))
  c="$(jq -r '.cpu // 0' "$rf" 2>/dev/null)"; [[ "$c" =~ ^[0-9]+$ ]] && ((cpus+=c))
  [[ "$(jq -r 'if (.gpu // null)==null or .gpu=="" then "n" else "y" end' "$rf" 2>/dev/null)" == y ]] && ((gpus++))
done < <(find "$REGISTRYDIR" -maxdepth 1 -name '*.json' 2>/dev/null)

# --- daemons (liveness local) ---
dj=false; pgrep -f 'server/daemons/judged.sh' >/dev/null 2>&1 && dj=true
dr=false; pgrep -f 'judge-gw/result-sink.sh' >/dev/null 2>&1 && dr=true
# fila do modelo pull (bandas) + alerta: trabalho pendente e NENHUM juiz online
band_queue=0; [[ -d "$QUEUEDIR" ]] && band_queue="$(find "$QUEUEDIR" -mindepth 2 -name '*.json' 2>/dev/null | wc -l)"
judges_alert=false; (( jonline == 0 )) && (( band_queue + total > 0 )) && judges_alert=true

out="$(jq -cn \
  --argjson t "$now" \
  --argjson total "$total" --argjson spool "${spool:-0}" --argjson lists "$lists" \
  --argjson bq "${band_queue:-0}" \
  --argjson on "${jonline:-0}" --argjson jt "${jtotal:-0}" --argjson busy "${jbusy:-0}" \
  --argjson cpus "${cpus:-0}" --argjson gpus "${gpus:-0}" \
  --argjson dj "$dj" --argjson dr "$dr" \
  --argjson alert "$judges_alert" \
  '{success:true, time:$t,
    queue:{total_pending:$total, spool_queued:$spool, band_queued:$bq, lists:$lists},
    judge:{online:$on, total:$jt, busy:$busy, healthy:($on>0),
           cpus_online:$cpus, gpus_online:$gpus},
    alert:{no_judges:$alert},
    daemons:{judged:$dj, result_sink:$dr}}')"
mkdir -p "$RUNDIR" 2>/dev/null
printf '%s' "$out" > "$CACHE.tmp" 2>/dev/null && mv -f "$CACHE.tmp" "$CACHE" 2>/dev/null
printf '%s' "$out"
