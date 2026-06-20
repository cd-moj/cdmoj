# POST /admin/passwd   (Bearer, admin)
# body: {contest, login, newpass}
# Substitui a senha (campo 2) da linha do usuário em contests/<contest>/passwd,
# preservando os demais campos (fullname, email/telegram, ...).
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

passwd="$CONTESTSDIR/$contest/passwd"
[[ -f "$passwd" ]] || fail 404 "passwd not found" "passwd_notfound"
cut -d: -f1 "$passwd" | grep -qxF -- "$login" || fail 404 "User not found" "user_notfound"

# reescreve atomicamente: troca só o 2º campo da linha cujo 1º campo == login
tmp="$passwd.tmp.$$"
awk -F: -v OFS=: -v u="$login" -v np="$newpass" '
  $1==u { $2=np } { print }
' "$passwd" > "$tmp" && mv -f "$tmp" "$passwd"

ok_json '{action:"passwd", contest:$c, login:$l}' --arg c "$contest" --arg l "$login"
