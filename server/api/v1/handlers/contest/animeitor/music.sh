# POST /contest/animeitor/music?contest=<id>   (Bearer: .animeitor ou admin do contest)
# Sobe/troca a MÚSICA de UM time (a faixa que o telão toca quando ele resolve):
#   {login:"<login>", file_b64:"…"}        — grava (mp3, ver lib/team-music.sh)
#   {action:"delete", login:"<login>"}     — remove
# O `login` também pode vir como NOME DE ARQUIVO (`fulano.mp3`) — é assim que o envio em lote da
# página manda, igual às fotos.
# ⚠ O corpo vem em ARQUIVO (read_body_file), não em variável: 15 MB de mp3 são ~20 MB de base64
# e um `body="$(read_body)"` desses derruba o handler. O base64 vai do arquivo direto para o
# `base64 -d` da lib.
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_animeitor || is_admin || is_cstaff; } || fail 403 "Apenas a conta de placar (.animeitor), o chefe de sede (.cstaff) ou o admin" "animeitor_required"
source "$_LIBDIR/team-music.sh"
is_cstaff && source "$_LIBDIR/print.sh"

MUSIC_MAX_MB=15                      # ~10 min a 192 kbps; o nginx de produção aceita bem mais
bodyf="$(read_body_file)"
trap 'rm -f "$bodyf" "$bodyf.b64"' EXIT
jq -e . >/dev/null 2>&1 < "$bodyf" || fail 400 "JSON inválido" "bad_json"

want="$(jq -r '.login // .filename // empty' < "$bodyf")"
[[ -n "$want" ]] || fail 400 "Informe login" "login_missing"
login="$(user_resolve_name "$contest" "$want")" || fail 404 "Nenhum time casa com '$want'" "user_not_found"
case "$login" in *.admin|*.judge|*.cjudge|*.staff|*.cstaff|*.mon|*.animeitor)
  fail 422 "Conta de papel não tem música de time" "role_account";; esac
# CHEFE DE SEDE só mexe em quem ele enxerga (mesma regra da foto)
is_cstaff && ! staff_can_see "$contest" "$SESSION_LOGIN" "$login" \
  && fail 403 "Time fora da sua sede" "staff_scope"

if [[ "$(jq -r '.action // empty' < "$bodyf")" == delete ]]; then
  tm_remove "$contest" "$login"
  audit_log_to "$contest" animeitor-music "delete login=$login by=$SESSION_LOGIN"
  ok_json '{deleted:true, login:$l}' --arg l "$login"
  exit 0
fi

# o base64 sai do JSON para um arquivo (sem passar por variável) — a lib decodifica de lá.
# O prefixo de data-url é tirado no próprio jq (o FileReader do navegador manda `data:…;base64,`).
jq -r '(.file_b64 // .music_b64 // "") | sub("^data:[^,]*,";"")' < "$bodyf" > "$bodyf.b64"
b64sz="$(stat -c %s "$bodyf.b64" 2>/dev/null || echo 0)"
(( b64sz > 16 )) || fail 400 "Arquivo ausente" "file_missing"     # jq -r de vazio ainda dá 1 byte
(( b64sz <= MUSIC_MAX_MB * 1024 * 1024 * 4 / 3 + 4096 )) \
  || fail 413 "Arquivo muito grande (máx ${MUSIC_MAX_MB}MB)" "file_large"

out="$(tm_store "$contest" "$login" "$bodyf.b64")"
case "$?" in
  1) fail 400 "Base64 inválido" "file_b64";;
  2) fail 400 "O arquivo não é um MP3" "music_bad";;
esac
bytes="$(stat -c %s "$out" 2>/dev/null || echo 0)"
audit_log_to "$contest" animeitor-music "upload login=$login bytes=$bytes by=$SESSION_LOGIN"
ok_json '{saved:true, login:$l, bytes:$b}' --arg l "$login" --argjson b "$bytes"
