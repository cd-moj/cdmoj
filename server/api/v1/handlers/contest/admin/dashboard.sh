# GET /contest/admin/dashboard?contest=<id>   (admin DO contest)
# Visão de SITUAÇÃO p/ o admin: juízes (cluster), fila, e métricas de submissão/espera
# deste contest (pendentes + tempo esperando, tempos de resposta, timeline com picos).
# Janela recente (últimas $WINDOW submissões) p/ custo baixo — o campo `window` informa.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
source "$_DIR/../../judge-gw/sched-lib.sh"

now="$EPOCHSECONDS"
cdir="$CONTESTSDIR/$contest"
hist="$cdir/controle/history"
resdir="$cdir/results"
WINDOW=500

# --- juízes (cluster global) + fila ---
trim(){ tr -d '[:space:]'; }
judges_total="$(find "$REGISTRYDIR" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | trim)"
judges_online="$(reg_live_hosts | wc -l | trim)"
judges_busy="$(reg_live_hosts busy | wc -l | trim)"
queue_depth="$(find "$QUEUEDIR" -mindepth 2 -maxdepth 2 -name '*.json' 2>/dev/null | wc -l | trim)"
assigned="$(find "$ASSIGNEDDIR" -mindepth 2 -maxdepth 2 -name '*.json' 2>/dev/null | wc -l | trim)"

# --- submissões recentes (TSV: id login problem pending sub_epoch) ---
rows=""
[[ -f "$hist" ]] && rows="$(tail -n "$WINDOW" "$hist" 2>/dev/null | awk -F: '
  NF>=6 {
    pending = ($0 ~ /:(Not Answered Yet|On queue|on queue|Running|running):/) ? 1 : 0
    printf "%s\t%s\t%s\t%s\t%s\n", $(NF), $2, $3, pending, $(NF-1)
  }')"

# mapa id -> finalized_at (uma única varredura dos results da janela)
declare -a RF
if [[ -n "$rows" ]]; then
  while IFS=$'\t' read -r id login problem pending sub; do
    [[ "$pending" == 0 && -f "$resdir/$id.json" ]] && RF+=("$resdir/$id.json")
  done <<< "$rows"
fi
finmap='{}'
((${#RF[@]})) && finmap="$(jq -s 'map(select(.id) | {key:.id, value:(.finalized_at//0)}) | from_entries' "${RF[@]}" 2>/dev/null)"
[[ -n "$finmap" ]] || finmap='{}'

metrics="$(printf '%s\n' "$rows" | jq -R -cs --argjson fin "$finmap" --argjson now "$now" '
  [ split("\n")[] | select(length>0) | split("\t")
    | { id:.[0], login:.[1], problem:.[2], pending:(.[3]=="1"), sub:(.[4]|tonumber? // 0) } ] as $subs
  | ($subs | map(select(.pending))) as $pend
  | ($subs | map(select(.pending|not) | . + {response:(($fin[.id] // 0) - .sub)}) | map(select(.response > 0))) as $done
  | ($pend | map({id, login, problem, submitted_at:.sub, waiting_s:($now - .sub)}) | sort_by(-.waiting_s)) as $pendlist
  | ($done | map(.response) | sort) as $rt
  | ($subs | map(. + {wait:(if (($fin[.id] // 0) > 0) then (($fin[.id]) - .sub) else ($now - .sub) end)})
          | group_by((.sub/60)|floor)
          | map({t:(((.[0].sub/60)|floor)*60), submits:length,
                 avg_wait_s:(((map(.wait)|add)/length)|floor), max_wait_s:(map(.wait)|max)})
          | sort_by(.t)) as $timeline
  | { total:($subs|length), pending:($pend|length), pending_list:$pendlist,
      max_wait_s:(($pendlist|map(.waiting_s)) + [0] | max),
      response:{ n:($done|length),
                 avg_s:(if ($done|length)==0 then 0 else (($done|map(.response)|add)/($done|length)|floor) end),
                 max_s:(($done|map(.response)) + [0] | max),
                 p50_s:(if ($rt|length)==0 then 0 else $rt[(($rt|length-1)*0.5)|floor] end),
                 p95_s:(if ($rt|length)==0 then 0 else $rt[(($rt|length-1)*0.95)|floor] end) },
      timeline:$timeline }')"
[[ -n "$metrics" ]] || metrics='{}'

ok_json '{now:$now, window:$win,
          judges:{online:$jo, busy:$jb, total:$jt, queue_depth:$qd, assigned:$asg},
          submissions:$m}' \
  --argjson now "$now" --argjson win "$WINDOW" \
  --argjson jo "${judges_online:-0}" --argjson jb "${judges_busy:-0}" --argjson jt "${judges_total:-0}" \
  --argjson qd "${queue_depth:-0}" --argjson asg "${assigned:-0}" \
  --argjson m "$metrics"
