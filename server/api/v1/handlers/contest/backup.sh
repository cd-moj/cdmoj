# /contest/backup?contest=<id>   (Bearer)
#   GET                          -> lista os backups do PRÓPRIO usuário
#   POST {filename, file_b64}    -> guarda um backup (versão de solução; não perde trabalho)
#   POST {action:"delete", id}   -> remove um backup próprio
# Armazenamento: contests/<c>/backups/<login>/<id> (conteúdo) + <id>.meta ({name,size,time}).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

login="$SESSION_LOGIN"
valid_id "$login" || fail 400 "login inválido" "login_invalid"
bdir="$CONTESTSDIR/$contest/backups/$login"

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  set +o noglob; shopt -s nullglob
  items=()
  for m in "$bdir"/*.meta; do
    [[ -f "$m" ]] || continue
    bid="$(basename "$m" .meta)"
    items+=("$(jq -c --arg id "$bid" '. + {id:$id}' "$m" 2>/dev/null)")
  done
  shopt -u nullglob
  out="$( ((${#items[@]})) && printf '%s\n' "${items[@]}" | jq -cs 'sort_by(-.time)' || echo '[]')"
  ok_json '{backups:$b}' --argjson b "$out"
  exit 0
fi

require_method POST
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
action="$(jq -r '.action // "upload"' <<<"$body")"

case "$action" in
  delete)
    id="$(jq -r '.id // empty' <<<"$body")"
    [[ "$id" =~ ^[A-Za-z0-9_]+$ ]] || fail 400 "id inválido" "id_invalid"
    rm -f "$bdir/$id" "$bdir/$id.meta"
    ok_json '{deleted:true, id:$id}' --arg id "$id"
    ;;
  *)
    fn="$(jq -r '.filename // empty' <<<"$body")"
    fb="$(jq -r '.file_b64 // empty' <<<"$body")"
    [[ -n "$fn" && -n "$fb" ]] || fail 422 "Informe filename e file_b64" "missing"
    safe="$(basename "$fn" | tr -cd 'A-Za-z0-9._ -')"; safe="${safe## }"; [[ -n "$safe" ]] || safe="arquivo"
    mkdir -p "$bdir"
    id="$(printf '%s%s%s' "$EPOCHSECONDS" "$RANDOM" "$login" | md5sum | cut -c1-20)"
    if ! printf '%s' "$fb" | base64 -d > "$bdir/$id" 2>/dev/null; then rm -f "$bdir/$id"; fail 422 "Arquivo inválido (base64)" "file_b64"; fi
    sz="$(stat -c%s "$bdir/$id" 2>/dev/null || echo 0)"
    if (( ${sz:-0} > 10485760 )); then rm -f "$bdir/$id"; fail 413 "Arquivo muito grande (máx 10MB)" "too_large"; fi
    jq -cn --arg n "$safe" --argjson s "${sz:-0}" --argjson t "$EPOCHSECONDS" '{name:$n, size:$s, time:$t}' > "$bdir/$id.meta"
    ok_json '{saved:true, id:$id, name:$n, size:$s, time:$t}' --arg id "$id" --arg n "$safe" --argjson s "${sz:-0}" --argjson t "$EPOCHSECONDS"
    ;;
esac
