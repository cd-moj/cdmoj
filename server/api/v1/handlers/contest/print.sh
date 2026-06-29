# /contest/print?contest=<id>   (Bearer)
#   GET                          -> lista os pedidos de impressão do PRÓPRIO usuário
#                                   (+ flags staff_exists / allow_print p/ guiar a UI)
#   POST {filename, file_b64}    -> cria um pedido (gera nº sequencial; auditado)
# Armazenamento: contests/<c>/print-requests/<id>.{json,src} (ver lib/print.sh).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
source "$_LIBDIR/print.sh"

login="$SESSION_LOGIN"
valid_id "$login" || fail 400 "login inválido" "login_invalid"
dir="$(pr_dir "$contest")"

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  set +o noglob; shopt -s nullglob
  items=()
  for j in "$dir"/*.json; do
    [[ -f "$j" ]] || continue
    [[ "$(jq -r '.login // ""' "$j" 2>/dev/null)" == "$login" ]] || continue
    items+=("$(jq -c '{id,seq,filename,mime,size,time,status,pages,claimed_by,processed_at,delivered_at}' "$j" 2>/dev/null)")
  done
  shopt -u nullglob
  out="$( ((${#items[@]})) && printf '%s\n' "${items[@]}" | jq -cs 'sort_by(-.seq)' || echo '[]')"
  se="$(staff_exists "$contest" && echo true || echo false)"
  ap="$(print_enabled "$contest" && echo true || echo false)"
  ok_json '{requests:$r, staff_exists:$se, allow_print:$ap}' --argjson r "$out" --argjson se "$se" --argjson ap "$ap"
  exit 0
fi

require_method POST
# precisa existir staff E impressão habilitada (a API sempre rejeita se indisponível)
staff_exists "$contest"  || fail 403 "Impressão indisponível (sem staff neste contest)" "print_unavailable"
print_enabled "$contest" || fail 403 "Impressão desabilitada pelo administrador do contest" "print_disabled"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
fn="$(jq -r '.filename // empty' <<<"$body")"
fb="$(jq -r '.file_b64 // empty' <<<"$body")"
[[ -n "$fn" && -n "$fb" ]] || fail 422 "Informe filename e file_b64" "missing"
safe="$(basename "$fn" | tr -cd 'A-Za-z0-9._ -')"; safe="${safe## }"; [[ -n "$safe" ]] || safe="arquivo"

mkdir -p "$dir"
id="$(printf '%s%s%s' "$EPOCHSECONDS" "$RANDOM" "$login" | md5sum | cut -c1-20)"
if ! printf '%s' "$fb" | base64 -d > "$dir/$id.src" 2>/dev/null; then rm -f "$dir/$id.src"; fail 422 "Arquivo inválido (base64)" "file_b64"; fi
sz="$(stat -c%s "$dir/$id.src" 2>/dev/null || echo 0)"
if (( ${sz:-0} > 10485760 )); then rm -f "$dir/$id.src"; fail 413 "Arquivo muito grande (máx 10MB)" "too_large"; fi
mime="$(file -b --mime-type "$dir/$id.src" 2>/dev/null)"; [[ -n "$mime" ]] || mime="application/octet-stream"
team="$(pr_resolve_team "$contest" "$login")"
univ="$(pr_resolve_univ "$contest" "$login")"
fullname="$(user_fullname "$contest" "$login")"; [[ -n "$fullname" ]] || fullname="$SESSION_NAME"
seq="$(pr_next_seq "$contest")"

jq -cn --arg id "$id" --argjson seq "$seq" --arg login "$login" --arg fn "$fullname" \
  --arg team "$team" --arg univ "$univ" --arg file "$safe" --arg mime "$mime" --argjson size "${sz:-0}" \
  --argjson time "$EPOCHSECONDS" '{
    id:$id, seq:$seq, login:$login, fullname:$fn, team:$team, univ:$univ, filename:$file, mime:$mime,
    size:$size, time:$time, status:"pending", pages:0,
    claimed_by:"", claimed_at:0, processed_by:"", processed_at:0, delivered_by:"", delivered_at:0
  }' > "$dir/$id.json"

audit_log_to "$contest" print-request "seq=$seq login=$login arquivo=$safe tipo=$mime tamanho=${sz:-0}"
ok_json '{id:$id, seq:$seq, status:"pending"}' --arg id "$id" --argjson seq "$seq"
