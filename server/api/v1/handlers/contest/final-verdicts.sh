# GET/POST /contest/final-verdicts?contest=<id>
# Opções de veredicto manual (configuráveis). Cada opção = {label (texto p/ o juiz), verdict
# (string CANÔNICA que vai ao aluno/placar — sem ':')}. Compat: string solta s ⇒ {label:s,verdict:s}.
#   GET  (Bearer, judge)        -> {verdicts:[labels], options:[{label,verdict}]}
#   POST (admin OU juiz-chefe)  -> {options:[{label,verdict}]} grava contests/<id>/final-verdicts.json
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
f="$CONTESTSDIR/$contest/final-verdicts.json"
DEFAULT='[{"label":"1 - YES","verdict":"Accepted"},{"label":"2 - NO - Compilation error","verdict":"Compilation Error"},{"label":"3 - NO - Runtime error","verdict":"Runtime Error"},{"label":"4 - NO - Time limit exceeded","verdict":"Time Limit Exceeded"},{"label":"5 - NO - Wrong answer","verdict":"Wrong Answer"},{"label":"6 - NO - Contact staff","verdict":"Contact staff"}]'

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  is_judge || fail 403 "Judge only" "judge_required"
  raw="$DEFAULT"; { [[ -f "$f" ]] && jq -e . "$f" >/dev/null 2>&1; } && raw="$(cat "$f")"
  emit_json 200 OK
  jq -cn --argjson raw "$raw" '
    ($raw | map(if type=="string" then {label:., verdict:.}
                else {label:((.label // .verdict // "")|tostring), verdict:((.verdict // .label // "")|tostring)} end)) as $opt
    | {success:true, verdicts:($opt|map(.verdict)), options:$opt}'
  exit 0
fi

require_method POST
is_admin_or_chief || fail 403 "Apenas admin ou juiz-chefe" "config_forbidden"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
# normaliza, valida (label/verdict não-vazios; verdict sem ':'/quebra-de-linha — vai p/ o history)
opts="$(jq -c '
  (.options // []) | map(
    (if type=="string" then {label:., verdict:.} else . end)
    | {label:((.label // "")|tostring), verdict:((.verdict // "")|tostring)})
  | map(select((.label|length)>0 and (.label|length)<=80
               and (.verdict|test("^[^:\n\t\r]{1,60}$"))))' <<<"$body")"
[[ -n "$opts" && "$(jq 'length' <<<"$opts")" -ge 1 ]] || fail 422 "Informe ao menos uma opção válida {label,verdict} (verdict sem ':')" "options_invalid"
mkdir -p "$CONTESTSDIR/$contest"
printf '%s' "$opts" > "$f.tmp" && mv -f "$f.tmp" "$f"
audit_log_to "$contest" final-verdicts-set "n=$(jq 'length' <<<"$opts")"
ok_json '{saved:true, options:$o}' --argjson o "$opts"
