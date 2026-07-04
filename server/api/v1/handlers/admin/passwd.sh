# POST /admin/passwd   (Bearer, admin)
# body: {contest, login, newpass}
# Troca a senha no account.json do usuário (user_set_password; demais campos preservados).
require_method POST
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
contest="$(jq -r '.contest // empty' <<<"$body")"
login="$(jq -r '.login // empty' <<<"$body")"
newpass="$(jq -r '.newpass // empty' <<<"$body")"

[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Admin only" "admin_required"

[[ -n "$login" && -n "$newpass" ]] || fail 400 "Missing login or newpass" "incomplete"
valid_id "$login" || fail 400 "Invalid login" "login_invalid"
[[ "$newpass" == *:* || "$newpass" == *$'\n'* ]] && fail 400 "Invalid newpass" "newpass_invalid"

user_exists "$contest" "$login" || fail 404 "User not found" "user_notfound"
user_set_password "$contest" "$login" "$newpass" \
  || fail 500 "Could not set password" "passwd_failed"

ok_json '{action:"passwd", contest:$c, login:$l}' --arg c "$contest" --arg l "$login"
