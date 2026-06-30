# GET/POST /contest/auto-verdicts?contest=<id>
# Matriz de veredicto AUTOMÁTICO por problema × linguagem × veredicto. Com MANUAL_VERDICT=1, o
# daemon entrega direto ao aluno o veredicto computado SE (cid, lang, verdict) estiver listado;
# senão segura p/ revisão de 2 juízes. cid = 'coleção#problema' (mesma chave do history); lang
# minúsculo ou '*' (qualquer linguagem).
#   GET  (Bearer, judge)       -> {matrix, problems:[cid], verdicts:[canônicos]}
#   POST (admin OU juiz-chefe) -> {matrix:{ "<cid>": { "<lang|*>": ["<verdict>",...] } }}
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
f="$CONTESTSDIR/$contest/auto-verdicts.json"

# cids canônicos dos problemas do contest (subshell: não vaza PROBS p/ o handler)
cids_json="$( ( PROBS=(); source "$CONTESTSDIR/$contest/conf" 2>/dev/null
  for ((i=0; i<${#PROBS[@]}; i+=5)); do
    c="${PROBS[i+4]:-}"; [[ "$c" == *"#"* ]] || c="${PROBS[i+1]//\//#}"
    printf '%s\n' "$c"
  done ) | jq -R . | jq -cs 'map(select(length>0)) | unique')"
[[ -n "$cids_json" ]] || cids_json='[]'

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  is_judge || fail 403 "Judge only" "judge_required"
  matrix='{}'; { [[ -f "$f" ]] && jq -e . "$f" >/dev/null 2>&1; } && matrix="$(cat "$f")"
  vf="$CONTESTSDIR/$contest/final-verdicts.json"; optraw='[]'
  { [[ -f "$vf" ]] && jq -e . "$vf" >/dev/null 2>&1; } && optraw="$(cat "$vf")"
  emit_json 200 OK
  jq -cn --argjson m "$matrix" --argjson p "$cids_json" --argjson o "$optraw" '
    ($o | map(if type=="string" then . else (.verdict // .label // "") end)) as $ov
    | (["Accepted","Wrong Answer","Time Limit Exceeded","Runtime Error","Compilation Error","Presentation Error","Memory Limit Exceeded","Output Limit Exceeded","Contact staff"] + $ov
       | map(select(length>0)) | unique) as $voc
    | {success:true, matrix:$m, problems:$p, verdicts:$voc}'
  exit 0
fi

require_method POST
is_admin_or_chief || fail 403 "Apenas admin ou juiz-chefe" "config_forbidden"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
jq -e '(.matrix // {}) | type=="object"' >/dev/null 2>&1 <<<"$body" || fail 422 "matrix inválida" "matrix_invalid"
# saneia: só cids do contest; langs ^[a-z0-9_+.*-]+$; verdicts sem ':'/quebra; arrays únicos
clean="$(jq -c --argjson cids "$cids_json" '
  (.matrix // {}) | to_entries
  | map(select(.key as $k | $cids | index($k)))
  | map({ key:.key, value:(
      (.value // {}) | to_entries
      | map(select(.key | test("^[a-z0-9_+.*-]+$")))
      | map({ key:.key, value:((.value // []) | map(tostring | select(test("^[^:\n\t\r]{1,60}$"))) | unique) })
      | map(select((.value|length) > 0)) | from_entries) })
  | map(select((.value | length) > 0)) | from_entries' <<<"$body")"
[[ -n "$clean" ]] || clean='{}'
mkdir -p "$CONTESTSDIR/$contest"
printf '%s' "$clean" > "$f.tmp" && mv -f "$f.tmp" "$f"
audit_log_to "$contest" auto-verdicts-set "problemas=$(jq 'keys|length' <<<"$clean")"
ok_json '{saved:true, matrix:$m}' --argjson m "$clean"
