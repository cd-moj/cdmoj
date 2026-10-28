# GET /treino/admin/audit-log[?day=YYYY-MM-DD]  (.admin)
# Ações administrativas registradas (deslogar, travar, notícias): epoch, admin, ação, detalhes.
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
day="$(param day)"
log="$CONTESTSDIR/treino/var/admin-audit.log"
# o que este viewer não pode ver (problema privado alheio, org de que não é membro) sai — a mesma regra do
# activity-log (lib/admin-feed.sh); o SUPERADMIN vê tudo
source "$_LIBDIR/admin-feed.sh"
HID="$(mktemp)" || fail 500 "Falha ao criar temporário" "tmp_failed"
trap 'rm -f "$HID"' EXIT
feed_hidden_file "$HID"
[[ -f "$log" ]] || { ok_json '{day:"", entries:[]}'; exit 0; }

if [[ -n "$day" ]]; then
  [[ "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || fail 400 "Dia inválido (YYYY-MM-DD)" "day_invalid"
  start="$(date -d "$day 00:00:00" +%s 2>/dev/null)" || fail 400 "Dia inválido" "day_invalid"
  rows="$(awk -F'\t' -v a="$start" -v b="$((start+86400))" '$1>=a && $1<b' "$log")"
else
  rows="$(tail -n 1000 "$log")"
fi

# corpo ANTES do cabeçalho: falha do jq = 500 honesto, nunca 200 vazio
body="$(printf '%s\n' "$rows" | jq -R -cs --arg day "$day" --slurpfile hid "$HID" "$FEED_VISIBLE_DEF"'
  { success:true, day:$day,
    entries: ( split("\n") | map(select(length>0) | split("\t") |
       { time:(.[0]|tonumber? // 0), admin:.[1], action:.[2], details:(.[3] // "") })
       | map(select(feed_visible($hid[0]))) | reverse ) }' 2>/dev/null)"
[[ -n "$body" ]] || fail 500 "Falha ao montar o audit" "audit_render_failed"
emit_json 200 OK
printf '%s\n' "$body"
