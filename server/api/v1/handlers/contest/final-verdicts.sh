# GET /contest/final-verdicts?contest=<id>   (Bearer, judge) -> JSON
# Lista de veredictos finais selecionáveis pelo juiz. Lê contests/<id>/final-verdicts.json
# (array de strings) se existir, senão usa o conjunto padrão.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_judge || fail 403 "Judge only" "judge_required"

emit_json 200 OK
f="$CONTESTSDIR/$contest/final-verdicts.json"
if [[ -f "$f" ]] && jq -e . "$f" >/dev/null 2>&1; then
  jq -c '{success:true, verdicts:.}' "$f"
else
  jq -cn '{success:true, verdicts:[
    "Accepted",
    "Wrong Answer",
    "Time Limit Exceeded",
    "Runtime Error",
    "Compilation Error",
    "Presentation Error",
    "Memory Limit Exceeded",
    "Output Limit Exceeded",
    "Restricted Function",
    "Judge Error"
  ]}'
fi
