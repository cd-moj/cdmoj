# GET /contest/admin/dashboard?contest=<id>   (admin DO contest)
# Visão de SITUAÇÃO acionável p/ o admin: estado de cada juiz (saúde do cluster), fila,
# pendentes com tempo de espera, métricas de espera/resposta, atividade por problema,
# submissões recentes e timeline (picos). Janela = últimas $WINDOW submissões (campo `window`).
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

# --- juízes: estado POR HOST (saúde do cluster) + contagens + fila ---
judges="$( { find "$REGISTRYDIR" -maxdepth 1 -name '*.json' 2>/dev/null | sort | while IFS= read -r jf; do
      jq -c --argjson now "$now" --argjson ttl "$REG_TTL" '{
         host, state:(.state//"?"), capability:(.capability//""),
         online:((.last_seen//0) >= ($now-$ttl)), last_seen:(.last_seen//0), age_s:($now-(.last_seen//0)),
         problems_count:(.problems_count // ((.problems//{})|length)), langs:(.langs // []) }' "$jf" 2>/dev/null
    done; } | jq -cs 'sort_by(.host)')"
[[ -n "$judges" ]] || judges='[]'
queue_depth="$(find "$QUEUEDIR" -mindepth 2 -maxdepth 2 -name '*.json' 2>/dev/null | wc -l | tr -d '[:space:]')"
assigned="$(find "$ASSIGNEDDIR" -mindepth 2 -maxdepth 2 -name '*.json' 2>/dev/null | wc -l | tr -d '[:space:]')"

# --- submissões recentes (TSV: id login problem pending sub_epoch verdict) ---
rows=""
[[ -f "$hist" ]] && rows="$(tail -n "$WINDOW" "$hist" 2>/dev/null | awk -F: '
  NF>=6 {
    pending = ($0 ~ /:(Not Answered Yet|On queue|on queue|Running|running):/) ? 1 : 0
    v=$5; for(i=6;i<=NF-2;i++) v=v":"$i
    printf "%s\t%s\t%s\t%s\t%s\t%s\n", $(NF), $2, $3, pending, $(NF-1), v
  }')"

# finalized_at das submissões já julgadas (uma varredura dos results da janela)
declare -a RF
if [[ -n "$rows" ]]; then
  while IFS=$'\t' read -r id login problem pending sub verdict; do
    [[ "$pending" == 0 && -f "$resdir/$id.json" ]] && RF+=("$resdir/$id.json")
  done <<< "$rows"
fi
finmap='{}'
((${#RF[@]})) && finmap="$(jq -s 'map(select(.id) | {key:.id, value:(.finalized_at//0)}) | from_entries' "${RF[@]}" 2>/dev/null)"
[[ -n "$finmap" ]] || finmap='{}'

metrics="$(printf '%s\n' "$rows" | jq -R -cs --argjson fin "$finmap" --argjson now "$now" '
  [ split("\n")[] | select(length>0) | split("\t")
    | { id:.[0], login:.[1], problem:.[2], pending:(.[3]=="1"), sub:(.[4]|tonumber? // 0), verdict:.[5] } ] as $subs
  | ($subs | map(select(.pending))) as $pend
  | ($subs | map(select(.pending|not) | . + {response:(($fin[.id] // 0) - .sub)}) | map(select(.response > 0))) as $done
  | ($pend | map({id, login, problem, submitted_at:.sub, waiting_s:($now - .sub)}) | sort_by(-.waiting_s)) as $pendlist
  | ($done | map(.response) | sort) as $rt
  | ( $subs | group_by(.problem)
        | map({ problem:.[0].problem, submits:length,
                pending:(map(select(.pending))|length),
                accepted:(map(select(.verdict|test("Accepted";"i")))|length) })
        | sort_by(.problem) ) as $perprob
  | ( $subs | sort_by(-.sub) | .[:15]
        | map({ login, problem, verdict, pending,
                response_s:(if (($fin[.id] // 0) > 0) then (($fin[.id]) - .sub) else null end), at:.sub }) ) as $recent
  | ( $subs | map(. + {wait:(if (($fin[.id] // 0) > 0) then (($fin[.id]) - .sub) else ($now - .sub) end)})
        | group_by((.sub/60)|floor)
        | map({ t:(((.[0].sub/60)|floor)*60), submits:length,
                avg_wait_s:(((map(.wait)|add)/length)|floor), max_wait_s:(map(.wait)|max) })
        | sort_by(.t) | .[-20:] ) as $timeline
  | { total:($subs|length), pending:($pend|length), pending_list:$pendlist,
      max_wait_s:(($pendlist|map(.waiting_s)) + [0] | max),
      response:{ n:($done|length),
                 avg_s:(if ($done|length)==0 then 0 else (($done|map(.response)|add)/($done|length)|floor) end),
                 max_s:(($done|map(.response)) + [0] | max),
                 p50_s:(if ($rt|length)==0 then 0 else $rt[(($rt|length-1)*0.5)|floor] end),
                 p95_s:(if ($rt|length)==0 then 0 else $rt[(($rt|length-1)*0.95)|floor] end) },
      per_problem:$perprob, recent:$recent, timeline:$timeline }')"
[[ -n "$metrics" ]] || metrics='{}'

ok_json '{now:$now, window:$win,
          judges:{online:($j|map(select(.online))|length), busy:($j|map(select(.state=="busy"))|length),
                  total:($j|length), queue_depth:$qd, assigned:$asg, list:$j},
          submissions:$m}' \
  --argjson now "$now" --argjson win "$WINDOW" --argjson j "$judges" \
  --argjson qd "${queue_depth:-0}" --argjson asg "${assigned:-0}" --argjson m "$metrics"
