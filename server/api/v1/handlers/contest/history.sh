# GET /contest/history?contest=<id>   (Bearer) -> TXT
# Submissões DO PRÓPRIO usuário no contest, do controle/history.
# 7 campos por linha: tempo:username:problemid:lang:verdict:epoch:subid
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

emit_text
hist="$CONTESTSDIR/$contest/controle/history"
[[ -f "$hist" ]] || exit 0
awk -F: -v u="$SESSION_LOGIN" '$2==u' "$hist"
