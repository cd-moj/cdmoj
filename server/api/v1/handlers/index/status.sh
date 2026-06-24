# GET /index/status  (PÚBLICO) — health do MOJ para a página de status.
# Agrega: fila de submissões (total + por lista), spool, máquinas de julgamento
# (via master :27000), e liveness dos daemons locais. Cache de 20s (RUNDIR/status.json)
# para não sondar o escalonador a cada request. Não expõe hostnames/IPs/specs (só contagens).
: "${JUDGE_HOST:=localhost}"; : "${JUDGE_PORT:=27000}"
: "${RUNDIR:=/home/ribas/moj/run}"
CACHE="$RUNDIR/status.json"
now="$EPOCHSECONDS"

emit_json 200 OK

# cache fresco (< 20s)? devolve direto.
if [[ -f "$CACHE" ]]; then
  ca="$(jq -r '.time // 0' "$CACHE" 2>/dev/null)"
  if [[ "$ca" =~ ^[0-9]+$ ]] && (( now - ca < 20 )); then cat "$CACHE"; exit 0; fi
fi

# --- fila por lista (controle/history) + spool ---
set +o noglob; shopt -s nullglob
declare -a LISTS; total=0
for h in "$CONTESTSDIR"/*/controle/history; do
  [[ -f "$h" ]] || continue
  cdir="${h%/controle/history}"; cid="${cdir##*/}"
  n="$(grep -cE ':(Not Answered Yet|On queue|on queue|Running|running):' "$h" 2>/dev/null)"; n="${n:-0}"
  if (( n > 0 )); then
    cname="$( . "$cdir/conf" 2>/dev/null; printf '%s' "${CONTEST_NAME:-$cid}" )"
    LISTS+=("$(jq -cn --arg c "$cid" --arg nm "$cname" --argjson n "$n" '{contest:$c,name:$nm,pending:$n}')")
    ((total+=n))
  fi
done
shopt -u nullglob
lists="$( ((${#LISTS[@]})) && printf '%s\n' "${LISTS[@]}" | jq -cs 'sort_by(-.pending)' || echo '[]')"
spool=0; [[ -d "$SPOOLDIR" ]] && spool="$(find "$SPOOLDIR" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | wc -l)"

# --- máquinas / master (:27000) — só contagens, com timeouts curtos ---
mtotal=0; monline=0; master_up=false; busy=false
lm="$(printf '{ "cmd": "listmachines" }\n' | timeout 8 nc -w 6 "$JUDGE_HOST" "$JUDGE_PORT" 2>/dev/null)"
if [[ -n "$lm" ]] && jq -e '.machines' >/dev/null 2>&1 <<<"$lm"; then
  mtotal="$(jq -r '(.count // (.machines|length)) // 0' <<<"$lm")"
  monline="$(jq -r '.online_count // 0' <<<"$lm")"
  master_up=true
else
  rep="$(printf '{ "cmd": "reportmachine" }\n' | timeout 4 nc -w 3 "$JUDGE_HOST" "$JUDGE_PORT" 2>/dev/null)"
  [[ -n "$rep" ]] && jq -e 'has("hostname")' >/dev/null 2>&1 <<<"$rep" && master_up=true
fi
if [[ "$master_up" == true ]]; then
  lk="$(printf '{ "cmd": "islocked" }\n' | timeout 4 nc -w 3 "$JUDGE_HOST" "$JUDGE_PORT" 2>/dev/null | jq -r '.status // empty' 2>/dev/null)"
  [[ "$lk" == "true" ]] && busy=true
fi

# --- daemons (liveness local) ---
dj=false; pgrep -f 'server/daemons/judged.sh' >/dev/null 2>&1 && dj=true
dr=false; pgrep -f 'judge-gw/result-sink.sh' >/dev/null 2>&1 && dr=true
# workers registrados e vivos — registro novo <host>.json (modelo pull, heartbeat)
: "${REGISTRYDIR:=$RUNDIR/registry}"; : "${QUEUEDIR:=$RUNDIR/queue}"; : "${REG_TTL:=30}"
wreg=0; agents_busy=0
while IFS= read -r rf; do
  ls="$(jq -r '.last_seen // 0' "$rf" 2>/dev/null)"; (( ls >= now - REG_TTL )) || continue
  ((wreg++)); [[ "$(jq -r '.state // ""' "$rf" 2>/dev/null)" == busy ]] && ((agents_busy++))
done < <(find "$REGISTRYDIR" -maxdepth 1 -name '*.json' 2>/dev/null)
# fila do modelo pull (bandas) + alerta: trabalho pendente e NENHUM juiz online
band_queue=0; [[ -d "$QUEUEDIR" ]] && band_queue="$(find "$QUEUEDIR" -mindepth 2 -name '*.json' 2>/dev/null | wc -l)"
judges_alert=false; (( wreg == 0 )) && (( band_queue + total > 0 )) && judges_alert=true

out="$(jq -cn \
  --argjson t "$now" \
  --argjson total "$total" --argjson spool "${spool:-0}" --argjson lists "$lists" \
  --argjson bq "${band_queue:-0}" \
  --argjson mt "${mtotal:-0}" --argjson mo "${monline:-0}" \
  --argjson mup "$master_up" --argjson busy "$busy" \
  --argjson dj "$dj" --argjson dr "$dr" --argjson wreg "${wreg:-0}" --argjson ab "${agents_busy:-0}" \
  --argjson alert "$judges_alert" \
  '{success:true, time:$t,
    queue:{total_pending:$total, spool_queued:$spool, band_queued:$bq, lists:$lists},
    judge:{master_up:$mup, busy:$busy, machines_online:$mo, machines_total:$mt,
           workers_registered:$wreg, agents_busy:$ab},
    alert:{no_judges:$alert},
    daemons:{judged:$dj, result_sink:$dr}}')"
mkdir -p "$RUNDIR" 2>/dev/null
printf '%s' "$out" > "$CACHE.tmp" 2>/dev/null && mv -f "$CACHE.tmp" "$CACHE" 2>/dev/null
printf '%s' "$out"
