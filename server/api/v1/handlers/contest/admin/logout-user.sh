# POST /contest/admin/logout-user?contest=<id>  (admin) {login}
# Encerra as sessões de um usuário no contest.
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
login="$(jq -r '.login // empty' <<<"$body")"
[[ -n "$login" ]] || fail 400 "Informe o login" "missing"
valid_id "$login" || fail 422 "login inválido" "login_invalid"
removed="$(remove_contest_sessions "$contest" "$login")"
audit_log_to "$contest" logout-user "login=$login removed=$removed"
ok_json '{logged_out:true, login:$l, sessions_removed:$n}' --arg l "$login" --argjson n "${removed:-0}"
