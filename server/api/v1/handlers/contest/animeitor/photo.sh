# POST /contest/animeitor/photo?contest=<id>   (Bearer: .animeitor ou admin do contest)
# Sobe/troca a foto de UM time (um arquivo por POST, como o painel de Times já faz — evita o
# teto de corpo do nginx):
#   {login:"<login>", file_b64:"…"}        — grava (converte p/ webp, ver lib/team-photo.sh)
#   {action:"delete", login:"<login>"}     — remove
# O `login` também pode vir como NOME DE ARQUIVO (`fulano.jpg`): a página manda o lote pelo
# nome, igual ao painel do admin.
# ⚠ Ao contrário do /contest/admin/team-assets, NÃO recusa contest com USERS_FROM: a foto é um
# asset LOCAL do contest (é assim que o capitão a envia na inscrição) e o esquenta — o caso de
# uso — usa USERS_FROM=treino.
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_animeitor || is_admin; } || fail 403 "Apenas a conta de placar (.animeitor) ou o admin" "animeitor_required"
source "$_LIBDIR/team-photo.sh"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"

# resolve <nome-de-arquivo|login> -> login existente (case-insensitive), como no team-assets
resolve_login(){
  local want="$1" d login
  want="$(basename "$want")"; want="${want%.*}"; want="${want,,}"
  [[ -n "$want" ]] || return 1
  user_exists "$contest" "$want" && { printf '%s' "$want"; return 0; }
  while IFS= read -r d; do
    login="${d##*/}"
    [[ "${login,,}" == "$want" ]] && { printf '%s' "$login"; return 0; }
  done < <(find "$CONTESTSDIR/$contest/users" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
  return 1
}

want="$(jq -r '.login // .filename // empty' <<<"$body")"
[[ -n "$want" ]] || fail 400 "Informe login" "login_missing"
login="$(resolve_login "$want")" || fail 404 "Nenhum time casa com '$want'" "user_not_found"
case "$login" in *.admin|*.judge|*.cjudge|*.staff|*.cstaff|*.mon|*.animeitor)
  fail 422 "Conta de papel não tem foto de time" "role_account";; esac

if [[ "$(jq -r '.action // empty' <<<"$body")" == delete ]]; then
  tp_remove "$contest" "$login"
  audit_log_to "$contest" animeitor-photo "delete login=$login by=$SESSION_LOGIN"
  _score_dirty "$contest"
  ok_json '{deleted:true, login:$l}' --arg l "$login"
  exit 0
fi

img="$(jq -r '.file_b64 // .image_b64 // empty' <<<"$body")"
[[ -n "$img" ]] || fail 400 "Arquivo ausente" "file_missing"
(( ${#img} <= 11000000 )) || fail 413 "Arquivo muito grande (máx ~8MB)" "file_large"

out="$(tp_store "$contest" "$login" "$img" 1000)"
case "$?" in
  1) fail 400 "Base64 inválido" "file_b64";;
  2) fail 400 "Não foi possível processar a imagem" "img_bad";;
esac
_score_dirty "$contest"
bytes="$(stat -c %s "$out" 2>/dev/null || echo 0)"
audit_log_to "$contest" animeitor-photo "upload login=$login bytes=$bytes by=$SESSION_LOGIN"
ok_json '{saved:true, login:$l, bytes:$b, format:"webp"}' --arg l "$login" --argjson b "$bytes"
