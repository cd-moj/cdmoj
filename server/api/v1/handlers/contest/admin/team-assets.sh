# POST /contest/admin/team-assets?contest=<id>   (admin DO contest)
# Upload de FOTO do time (photo.png, lado máx 1000 — é p/ VER, clicável no placar) e de
# BRASÃO (logo.png, máx 128 — aparece na célula do time). UM arquivo por POST (o front
# manda em sequência com progresso; evita o client_max_body_size de 25m do nginx):
#   {kind:"photo"|"logo", filename:"<login>.<ext>", file_b64}
#     — o basename SEM extensão é o login (case-insensitive contra os usuários existentes).
#   {action:"delete", kind, login}  — remove o asset.
# Limite 8MB/arquivo; login inexistente → 404; USERS_FROM → 409. Auditado (team-asset).
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"

shared="$(grep -m1 '^USERS_FROM=' "$CONTESTSDIR/$contest/conf" 2>/dev/null | cut -d= -f2-)"
[[ -n "$shared" ]] && fail 409 "Contest com usuários compartilhados (users_from)" "shared_users"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
kind="$(jq -r '.kind // empty' <<<"$body")"
[[ "$kind" == photo || "$kind" == logo ]] || fail 422 "kind deve ser photo|logo" "kind_invalid"

# resolve <nome-de-arquivo|login> -> login existente (case-insensitive) ou vazio
resolve_login(){
  local want="$1" d login
  want="${want,,}"
  user_exists "$contest" "$want" && { printf '%s' "$want"; return; }
  while IFS= read -r d; do
    login="${d##*/}"
    [[ "${login,,}" == "$want" && -f "$d/account.json" ]] && { printf '%s' "$login"; return; }
  done < <(find "$CONTESTSDIR/$contest/users" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
}

if [[ "$(jq -r '.action // empty' <<<"$body")" == delete ]]; then
  login="$(jq -r '.login // empty' <<<"$body")"
  [[ -n "$login" ]] && valid_id "$login" || fail 400 "login inválido" "login_invalid"
  user_exists "$contest" "$login" || fail 404 "Usuário não existe" "user_not_found"
  rm -f "$(user_dir "$contest" "$login")/$kind.png"
  audit_log_to "$contest" team-asset "delete kind=$kind login=$login"
  ok_json '{deleted:true, login:$l, kind:$k}' --arg l "$login" --arg k "$kind"
  exit 0
fi

fname="$(jq -r '.filename // empty' <<<"$body")"
[[ -n "$fname" ]] || fail 400 "Informe filename" "filename_missing"
base="$(basename "$fname")"; base="${base%.*}"
login="$(resolve_login "$base")"
[[ -n "$login" ]] || fail 404 "Nenhum usuário casa com '$base'" "user_not_found"

img="$(jq -r '.file_b64 // empty' <<<"$body")"
[[ -n "$img" ]] || fail 400 "Arquivo ausente" "file_missing"
img="${img#data:*;base64,}"                          # tolera data-url
(( ${#img} <= 11000000 )) || fail 413 "Arquivo muito grande (máx ~8MB)" "file_large"

out="$(user_dir "$contest" "$login")/$kind.png"
tmp="$(mktemp)"
printf '%s' "$img" | base64 -d > "$tmp" 2>/dev/null || { rm -f "$tmp"; fail 400 "Base64 inválido" "file_b64"; }
# normaliza p/ PNG sem metadados; '>' = só ENCOLHE (não infla imagem pequena)
size='1000x1000>'; [[ "$kind" == logo ]] && size='128x128>'
if convert "$tmp" -auto-orient -strip -resize "$size" "png:$out.tmp" 2>/dev/null; then
  mv -f "$out.tmp" "$out"; rm -f "$tmp"
else
  rm -f "$tmp" "$out.tmp"; fail 400 "Não foi possível processar a imagem" "img_bad"
fi
audit_log_to "$contest" team-asset "upload kind=$kind login=$login bytes=$(stat -c %s "$out" 2>/dev/null)"
ok_json '{saved:true, login:$l, kind:$k}' --arg l "$login" --arg k "$kind"
