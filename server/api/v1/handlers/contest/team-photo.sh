# GET /contest/team-photo?contest=<id>&user=<login>   -> foto do time (webp; png no legado)
# Gate = o do PLACAR (público; contest SECRETO exige sessão do contest). 404 sem foto.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_not_secret_or_auth "$contest"
quser="$(param user)"
[[ -n "$quser" ]] || fail 400 "Missing user" "user_missing"
valid_id "$quser" || fail 400 "Invalid user" "user_invalid"
source "$_LIBDIR/team-photo.sh"
# webp é o formato de hoje; photo.png é o acervo antigo (ainda servido — ver lib/team-photo.sh)
f="$(tp_file "$contest" "$quser")"
[[ -n "$f" ]] || fail 404 "Sem foto" "no_photo"
printf 'Status: 200 OK\r\nContent-Type: %s\r\nCache-Control: max-age=60\r\n\r\n' "$(tp_ctype "$f")"
cat "$f"
