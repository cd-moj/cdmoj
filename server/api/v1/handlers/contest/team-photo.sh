# GET /contest/team-photo?contest=<id>&user=<login>[&thumb=1]   -> foto do time
# Gate = o do PLACAR (público; contest SECRETO exige sessão do contest). 404 sem foto.
#   sem thumb  -> a foto (webp; png no acervo antigo) — é o que o 📷 do placar abre
#   &thumb=1   -> a MINIATURA de 320px (~7 KB), para a galeria do .animeitor
# O cliente manda `&v=<mtime>` na URL, então a miniatura pode ter cache longo: mudou a foto,
# muda o v e o browser busca de novo (o repo não tem ETag/304 em lugar nenhum).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_not_secret_or_auth "$contest"
quser="$(param user)"
[[ -n "$quser" ]] || fail 400 "Missing user" "user_missing"
valid_id "$quser" || fail 400 "Invalid user" "user_invalid"
source "$_LIBDIR/team-photo.sh"

if [[ -n "$(param thumb)" ]]; then
  f="$(tp_thumb "$contest" "$quser")"; maxage=86400
else
  f="$(tp_file "$contest" "$quser")";  maxage=60
fi
[[ -n "$f" ]] || fail 404 "Sem foto" "no_photo"
printf 'Status: 200 OK\r\nContent-Type: %s\r\nCache-Control: max-age=%s\r\n\r\n' "$(tp_ctype "$f")" "$maxage"
cat "$f"
