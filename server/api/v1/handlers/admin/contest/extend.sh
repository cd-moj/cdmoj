# POST /admin/contest/extend   (Bearer, admin)
# body: {contest, end_epoch}
# Estende a vigência: acrescenta "CONTEST_END=<epoch>" ao final do conf
# (o source pega o último valor). Padrão já usado nos confs reais.
require_method POST
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
contest="$(jq -r '.contest // empty' <<<"$body")"
end_epoch="$(jq -r '.end_epoch // empty' <<<"$body")"

[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Admin only" "admin_required"

[[ -n "$end_epoch" ]] || fail 400 "Missing end_epoch" "end_missing"
[[ "$end_epoch" =~ ^[0-9]+$ ]] || fail 400 "Invalid end_epoch" "end_invalid"

conf="$CONTESTSDIR/$contest/conf"
printf 'CONTEST_END=%s\n' "$end_epoch" >> "$conf"

ok_json '{action:"extend", contest:$c, end_epoch:$e}' \
  --arg c "$contest" --argjson e "$end_epoch"
