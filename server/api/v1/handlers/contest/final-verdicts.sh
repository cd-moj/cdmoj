# GET/POST /contest/final-verdicts?contest=<id>
# Opções de veredicto manual (configuráveis). Cada opção = {label (o que o JUIZ escolhe), verdict
# (CLASSE canônica — uma das 6 de lib/verdict.sh: é o que pontua/penaliza), team (texto que o
# TIME vê; opcional; Accepted não tem texto próprio — placar e página do time dependem dele)}.
# Compat: string solta s ⇒ {label:s,verdict:s}; verdict fora das 6 vira classe Wrong Answer +
# team = a string antiga (rv_options normaliza). Ver lib/review.sh e lib/verdict.sh (marcador ¦).
#   GET  (Bearer, judge)        -> {verdicts:[classes], classes:[as 6], options:[{label,verdict,team}]}
#   POST (admin OU juiz-chefe)  -> {options:[{label,verdict,team?}]} grava contests/<id>/final-verdicts.json
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
f="$CONTESTSDIR/$contest/final-verdicts.json"
source "$_LIBDIR/review.sh"   # RV_DEFAULT_OPTS + rv_options (fonte única das opções)

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  is_judge || fail 403 "Judge only" "judge_required"
  ok_json '{verdicts:($o|map(.verdict)), classes:($c|split("|")), options:$o}' \
    --argjson o "$(rv_options "$contest")" --arg c "$VERDICT_CLASSES"
  exit 0
fi

require_method POST
is_admin_or_chief || fail 403 "Apenas admin ou juiz-chefe" "config_forbidden"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
# normaliza e valida: label 1..80 (sem ¦/quebra); verdict = uma das 6 classes (422 verdict_invalid);
# team opcional ≤60, sem ':' (separador do history), sem '¦' (marcador) nem quebra de linha;
# Accepted nunca leva team (o placar e a página do time reconhecem a classe pelo texto).
bad="$(jq -r --arg cls "$VERDICT_CLASSES" '($cls|split("|")) as $C
  | [ (.options // [])[] | (if type=="string" then {label:., verdict:.} else . end) | ((.verdict // "")|tostring) | . as $v | select(($C|index($v)) == null) ] | first // empty' <<<"$body")"
[[ -z "$bad" ]] || fail 422 "Classe de veredicto inválida: '$bad' (use uma das 6: ${VERDICT_CLASSES//|/, }); o texto que o time vê vai em team" "verdict_invalid"
opts="$(jq -c '
  (.options // []) | map(
    (if type=="string" then {label:., verdict:.} else . end)
    | {label:((.label // "")|tostring), verdict:((.verdict // "")|tostring), team:((.team // "")|tostring)})
  | map(select((.label|test("^[^¦\n\t\r]{1,80}$")) and (.team|test("^[^:¦\n\t\r]{0,60}$"))))
  | map(if .verdict == "Accepted" or .team == .verdict then .team = "" else . end)' <<<"$body")"
[[ -n "$opts" && "$(jq 'length' <<<"$opts")" -ge 1 ]] || fail 422 "Informe ao menos uma opção válida {label, verdict (classe), team?} — sem ':' nem '¦' no texto do time" "options_invalid"
mkdir -p "$CONTESTSDIR/$contest"
printf '%s' "$opts" > "$f.tmp" && mv -f "$f.tmp" "$f"
audit_log_to "$contest" final-verdicts-set "n=$(jq 'length' <<<"$opts")"
ok_json '{saved:true, options:$o}' --argjson o "$opts"
