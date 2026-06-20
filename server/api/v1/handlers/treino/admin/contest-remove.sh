# POST /treino/admin/contest-remove  (.admin) {contest}
# Move um contest CRIADO PELA INTERFACE para contests/.trash (reversível). Não toca em contests legados.
require_method POST
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
cid="$(jq -r '.contest // empty' <<<"$body")"
[[ -n "$cid" ]] || fail 400 "Informe o contest" "missing"
valid_id "$cid" || fail 400 "contest inválido" "contest_invalid"
d="$CONTESTSDIR/$cid"
[[ -d "$d" && -f "$d/conf" ]] || fail 404 "Contest não encontrado" "notfound"
[[ -f "$d/created-by" ]] || fail 403 "Só é possível remover contests criados pela interface" "not_user_created"
trash="$CONTESTSDIR/.trash"; mkdir -p "$trash"
mv "$d" "$trash/$cid-$EPOCHSECONDS" 2>/dev/null || fail 500 "Falha ao remover" "remove_fail"
audit_log contest-remove "id=$cid"
ok_json '{removed:true, contest:$c}' --arg c "$cid"
