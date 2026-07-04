# GET  /treino/profile/photo?user=X   -> serve a foto de perfil (png 100x100)
# POST /treino/profile/photo  {image_b64}  -> upload (redimensiona/recorta p/ 100x100)

if [[ "$REQUEST_METHOD" == GET ]]; then
  quser="$(param user)"
  [[ -n "$quser" ]] || { load_session && quser="$SESSION_LOGIN"; }
  [[ -n "$quser" ]] || fail 400 "Missing user" "user_missing"
  valid_id "$quser" || fail 400 "Invalid user" "user_invalid"
  isowner=0; isadm=0
  if load_session && [[ "$SESSION_CONTEST" == treino ]]; then
    [[ "$SESSION_LOGIN" == "$quser" ]] && isowner=1; is_admin && isadm=1
  fi
  if ! profile_is_public treino "$quser" && (( !isowner && !isadm )); then fail 404 "Sem foto" "no_photo"; fi
  f="$(photo_file treino "$quser")"
  [[ -f "$f" ]] || fail 404 "Sem foto" "no_photo"
  printf 'Status: 200 OK\r\nContent-Type: image/png\r\nCache-Control: no-cache\r\n\r\n'
  cat "$f"
  exit 0
fi

require_method POST
require_auth_contest treino
login="$SESSION_LOGIN"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
img="$(jq -r '.image_b64 // empty' <<<"$body")"
[[ -n "$img" ]] || fail 400 "Imagem ausente" "img_missing"
img="${img#data:*;base64,}"                         # tolera data-url
(( ${#img} <= 5500000 )) || fail 413 "Imagem muito grande (máx ~4MB)" "img_large"

out="$(photo_file treino "$login")"
mkdir -p "$(dirname "$out")"
tmp="$(mktemp)"
printf '%s' "$img" | base64 -d > "$tmp" 2>/dev/null || { rm -f "$tmp"; fail 400 "Base64 inválido" "img_b64"; }
# redimensiona+recorta centralizado p/ 100x100 png, remove metadados
if convert "$tmp" -auto-orient -strip -thumbnail '100x100^' -gravity center -extent 100x100 "png:$out.tmp" 2>/dev/null; then
  mv -f "$out.tmp" "$out"; rm -f "$tmp"
else
  rm -f "$tmp" "$out.tmp"; fail 400 "Não foi possível processar a imagem" "img_bad"
fi
ok_json '{updated:true}'
