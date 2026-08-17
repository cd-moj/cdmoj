# GET/POST /contest/animeitor/placeholder?contest=<id>   (Bearer: .animeitor ou admin)
# A FOTO PADRÃO do contest — a que a API devolve para time sem foto (e que vai no pacote .zip
# no lugar de quem não mandou). Quem escolhe é a mesa do telão.
#   GET                       -> {custom, bytes, mtime}
#   POST {file_b64}           -> troca (convertida p/ webp 1000px + miniatura, como a foto de time)
#   POST {action:"reset"}     -> volta à de fábrica (apaga a do contest — mesmo idioma do
#                                "remove" da capa do caderno e do colors:[] das cores)
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_animeitor || is_admin; } || fail 403 "Apenas a conta de placar (.animeitor) ou o admin" "animeitor_required"
source "$_LIBDIR/team-photo.sh"

_ph_json(){
  local f; f="$(tp_placeholder "$contest")"
  ok_json '{custom:$c, bytes:$b, mtime:$m}' \
    --argjson c "$(tp_placeholder_custom "$contest" && echo true || echo false)" \
    --argjson b "$(stat -c %s "$f" 2>/dev/null || echo 0)" \
    --argjson m "$(stat -c %Y "$f" 2>/dev/null || echo 0)"
}

if [[ "${REQUEST_METHOD:-GET}" != POST ]]; then _ph_json; exit 0; fi

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"

if [[ "$(jq -r '.action // empty' <<<"$body")" == reset ]]; then
  tp_placeholder_reset "$contest"
  audit_log_to "$contest" animeitor-placeholder "reset by=$SESSION_LOGIN"
  _ph_json
  exit 0
fi

img="$(jq -r '.file_b64 // .image_b64 // empty' <<<"$body")"
[[ -n "$img" ]] || fail 400 "Arquivo ausente" "file_missing"
(( ${#img} <= 11000000 )) || fail 413 "Arquivo muito grande (máx ~8MB)" "file_large"
out="$(tp_placeholder_store "$contest" "$img")"
case "$?" in
  1) fail 400 "Base64 inválido" "file_b64";;
  2) fail 400 "Não foi possível processar a imagem" "img_bad";;
esac
audit_log_to "$contest" animeitor-placeholder "upload bytes=$(stat -c %s "$out" 2>/dev/null) by=$SESSION_LOGIN"
_ph_json
