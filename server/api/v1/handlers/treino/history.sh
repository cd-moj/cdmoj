# GET /treino/history?id=<problem>   (Bearer) -> TXT, histórico do usuário no problema.
# 7 campos por linha: tempo:username:problemid:lang:verdict:epoch:subid
require_auth_contest treino
id="$(param id)"
[[ -n "$id" ]] || fail 400 "Missing problem id" "id_missing"
valid_id "$id" || fail 400 "Invalid problem id" "id_invalid"
emit_text
hist="$CONTESTSDIR/treino/controle/history"
[[ -f "$hist" ]] || exit 0
awk -F: -v u="$SESSION_LOGIN" -v p="$id" '$2==u && $3==p' "$hist"
