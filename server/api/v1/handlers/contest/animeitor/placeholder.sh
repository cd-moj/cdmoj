# GET/POST /contest/animeitor/placeholder?contest=<id>   (Bearer: .animeitor ou admin)
# O PADRÃO do contest — o que a API devolve para o time que não mandou o seu (e o que vai no
# pacote .zip no lugar dele). Quem escolhe é a mesa do telão. Dois tipos, o mesmo desenho:
#   GET                                  -> {custom, bytes, mtime, music:{custom,bytes,mtime}}
#                                           (os campos do topo são os da FOTO — contrato antigo)
#   POST {file_b64}                      -> troca a FOTO padrão (webp 1000px + miniatura)
#   POST {kind:"music", file_b64}        -> troca a MÚSICA padrão (mp3, sem conversão)
#   POST {action:"reset"[,kind:"music"]} -> volta à de fábrica (apaga a do contest — mesmo
#                                           idioma do "remove" da capa do caderno)
# ⚠ Corpo em ARQUIVO (read_body_file): a música padrão pode ter 15 MB (~20 MB de base64).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
# a sede (.cstaff/.staff) VÊ/OUVE o padrão (é o que vai ao telão de quem não mandou o seu), mas
# não troca: o padrão vale para o contest INTEIRO, não só para a sede dela.
{ is_animeitor || is_admin || is_cstaff || is_staff; } || fail 403 "Apenas a conta de placar (.animeitor), a sede (.cstaff/.staff) ou o admin" "animeitor_required"
source "$_LIBDIR/team-photo.sh"
source "$_LIBDIR/team-music.sh"

MUSIC_MAX_MB=15

_ph_json(){
  local f m
  f="$(tp_placeholder "$contest")"; m="$(tm_placeholder "$contest")"
  ok_json '{custom:$c, bytes:$b, mtime:$t, music:{custom:$mc, bytes:$mb, mtime:$mt}}' \
    --argjson c  "$(tp_placeholder_custom "$contest" && echo true || echo false)" \
    --argjson b  "$(stat -c %s "$f" 2>/dev/null || echo 0)" \
    --argjson t  "$(stat -c %Y "$f" 2>/dev/null || echo 0)" \
    --argjson mc "$(tm_placeholder_custom "$contest" && echo true || echo false)" \
    --argjson mb "$(stat -c %s "$m" 2>/dev/null || echo 0)" \
    --argjson mt "$(stat -c %Y "$m" 2>/dev/null || echo 0)"
}

if [[ "${REQUEST_METHOD:-GET}" != POST ]]; then _ph_json; exit 0; fi
{ is_animeitor || is_admin; } || fail 403 "O padrão é do contest inteiro: só a mesa do telão (.animeitor) ou o admin trocam" "animeitor_required"

bodyf="$(read_body_file)"
trap 'rm -f "$bodyf" "$bodyf.b64"' EXIT
jq -e . >/dev/null 2>&1 < "$bodyf" || fail 400 "JSON inválido" "bad_json"
kind="$(jq -r '.kind // "photo"' < "$bodyf")"
[[ "$kind" == photo || "$kind" == music ]] || fail 422 "kind deve ser photo|music" "kind_invalid"

if [[ "$(jq -r '.action // empty' < "$bodyf")" == reset ]]; then
  if [[ "$kind" == music ]]; then tm_placeholder_reset "$contest"; else tp_placeholder_reset "$contest"; fi
  audit_log_to "$contest" animeitor-placeholder "reset kind=$kind by=$SESSION_LOGIN"
  _ph_json
  exit 0
fi

jq -r '(.file_b64 // .image_b64 // .music_b64 // "") | sub("^data:[^,]*,";"")' < "$bodyf" > "$bodyf.b64"
b64sz="$(stat -c %s "$bodyf.b64" 2>/dev/null || echo 0)"
(( b64sz > 16 )) || fail 400 "Arquivo ausente" "file_missing"

if [[ "$kind" == music ]]; then
  (( b64sz <= MUSIC_MAX_MB * 1024 * 1024 * 4 / 3 + 4096 )) \
    || fail 413 "Arquivo muito grande (máx ${MUSIC_MAX_MB}MB)" "file_large"
  out="$(tm_placeholder_store "$contest" "$bodyf.b64")"
  case "$?" in
    1) fail 400 "Base64 inválido" "file_b64";;
    2) fail 400 "O arquivo não é um MP3" "music_bad";;
  esac
else
  (( b64sz <= 11000000 )) || fail 413 "Arquivo muito grande (máx ~8MB)" "file_large"
  out="$(tp_placeholder_store "$contest" "$(cat "$bodyf.b64")")"
  case "$?" in
    1) fail 400 "Base64 inválido" "file_b64";;
    2) fail 400 "Não foi possível processar a imagem" "img_bad";;
  esac
fi
audit_log_to "$contest" animeitor-placeholder "upload kind=$kind bytes=$(stat -c %s "$out" 2>/dev/null) by=$SESSION_LOGIN"
_ph_json
