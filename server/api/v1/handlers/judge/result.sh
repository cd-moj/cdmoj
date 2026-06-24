# POST /judge/result   (Bearer mojw_<token>)
# O worker devolve o resultado do julgamento. Para o judged.sh seguir sendo o ÚNICO
# escritor do history, gravamos o payload num arquivo de spool "result" que o daemon
# ingere (instala report.html, escreve results/<id>.json, atualiza history/data/placar).
# body: {host, id, contest, problem_id, login, lang, verdict, score, correct,
#        total_tests, duration_s, tl_used, tests:[{name,verdict,code,time,tl}], report_html_b64}
require_method POST
require_worker
source "$_DIR/../../judge-gw/sched-lib.sh"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
host="$(jq -r '.host // empty' <<<"$body")"
contest="$(jq -r '.contest // empty' <<<"$body")"
problem="$(jq -r '.problem_id // empty' <<<"$body")"
[[ -n "$id" && -n "$host" && -n "$contest" ]] || fail 400 "Missing id/host/contest" "result_incomplete"
valid_id "$id"        || fail 400 "Invalid id" "id_invalid"
valid_hostname "$host"|| fail 400 "Invalid host" "host_invalid"
valid_id "$contest"   || fail 400 "Invalid contest" "contest_invalid"

# remove o job reivindicado (idempotente) e marca o worker livre p/ o próximo beat
q_done "$host" "$id"
reg_touch_state "$host" free 2>/dev/null || true

# grava o payload no spool p/ o judged.sh finalizar (escritor único do history).
# nome: <contest>:<epoch>:<id>:<host>:result:<problem>  (.in.* = escrita atômica)
AGORA="$EPOCHSECONDS"
spoolname="$contest:$AGORA:$id:$host:result:$problem"
mkdir -p "$SPOOLDIR" 2>/dev/null
tmp="$SPOOLDIR/.in.result.$id.$$"
printf '%s' "$body" > "$tmp" && mv -f "$tmp" "$SPOOLDIR/$spoolname"

ok_json '{id:$i, accepted:true}' --arg i "$id"
