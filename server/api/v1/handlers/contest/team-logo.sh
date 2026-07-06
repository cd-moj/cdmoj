# GET /contest/team-logo?contest=<id>&user=<login>   -> PNG do brasão do time (máx 128)
# Gate = o do PLACAR (público; contest SECRETO exige sessão do contest). 404 sem brasão.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_not_secret_or_auth "$contest"
quser="$(param user)"
[[ -n "$quser" ]] || fail 400 "Missing user" "user_missing"
valid_id "$quser" || fail 400 "Invalid user" "user_invalid"
f="$(user_dir "$contest" "$quser")/logo.png"
[[ -f "$f" ]] || fail 404 "Sem brasão" "no_logo"
printf 'Status: 200 OK\r\nContent-Type: image/png\r\nCache-Control: max-age=60\r\n\r\n'
cat "$f"
