# GET /treino/contest-create/permission  (auth treino) -> o usuário pode criar contest?
require_method GET
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
if cc_can_create "$SESSION_LOGIN"; then can=true; else can=false; fi
if [[ "$SESSION_LOGIN" == *.admin ]]; then modes='["icpc","obi","treino","heuristic","outro"]'; else modes='["icpc","obi","treino","heuristic"]'; fi
ok_json '{can_create:$c, is_admin:$adm, reason:$r, solved_count:$s, threshold:$t, in_allow:$ia, in_deny:$idn, allowed_modes:$modes, login:$lg, name:$nm}' \
  --argjson c "$can" --argjson adm "$CC_ISADMIN" --arg r "$CC_REASON" \
  --argjson s "${CC_SOLVED:-0}" --argjson t "${CC_THRESHOLD:-0}" \
  --argjson ia "$CC_INALLOW" --argjson idn "$CC_INDENY" --argjson modes "$modes" \
  --arg lg "$SESSION_LOGIN" --arg nm "$SESSION_NAME"
