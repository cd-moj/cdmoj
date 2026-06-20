# POST /admin/adduser   (Bearer, admin)
# body: {contest, login, fullname, email?, password?}
# Acrescenta uma linha em contests/<contest>/passwd: login:pass:fullname[:email]
# Gera senha aleatória se não informada. Retorna a senha (em claro) p/ entrega.
require_method POST
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
contest="$(jq -r '.contest // empty' <<<"$body")"
login="$(jq -r '.login // empty' <<<"$body")"
fullname="$(jq -r '.fullname // empty' <<<"$body")"
email="$(jq -r '.email // empty' <<<"$body")"
password="$(jq -r '.password // empty' <<<"$body")"

[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Admin only" "admin_required"

[[ -n "$login" && -n "$fullname" ]] || fail 400 "Missing login or fullname" "incomplete"
valid_id "$login" || fail 400 "Invalid login" "login_invalid"
# campos não podem conter ':' nem nova linha (corromperia o passwd)
[[ "$fullname" == *:* || "$fullname" == *$'\n'* ]] && fail 400 "Invalid fullname" "fullname_invalid"
[[ "$email" == *:* || "$email" == *$'\n'* ]] && fail 400 "Invalid email" "email_invalid"

passwd="$CONTESTSDIR/$contest/passwd"
if [[ -f "$passwd" ]] && cut -d: -f1 "$passwd" | grep -qxF -- "$login"; then
  fail 409 "User already exists" "user_exists"
fi

[[ -n "$password" ]] || password="$(tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c 10)"
[[ "$password" == *:* || "$password" == *$'\n'* ]] && fail 400 "Invalid password" "password_invalid"

line="$login:$password:$fullname"
[[ -n "$email" ]] && line="$line:$email"
printf '%s\n' "$line" >> "$passwd"

ok_json '{action:"adduser", contest:$c, login:$l, password:$p}' \
  --arg c "$contest" --arg l "$login" --arg p "$password"
