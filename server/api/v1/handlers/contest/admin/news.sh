# POST /contest/admin/news?contest=<id>  (admin/judge/mon) {action:add|remove, ...}
# Gerencia as notícias públicas do contest (contests/<id>/news.json: [{id,title,text,date}]).
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_admin || is_judge || is_mon; } || fail 403 "Apenas admin/judge/monitor" "news_forbidden"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
action="$(jq -r '.action // empty' <<<"$body")"
f="$CONTESTSDIR/$contest/news.json"
cur="$( [[ -f "$f" ]] && jq -c 'if type=="array" then . else [] end' "$f" 2>/dev/null || echo '[]')"
[[ -n "$cur" ]] || cur='[]'

case "$action" in
  add)
    title="$(jq -r '.title // empty' <<<"$body")"; text="$(jq -r '.text // ""' <<<"$body")"
    [[ -n "$title" ]] || fail 422 "Informe o título" "title_missing"
    id="$(printf '%s%s%s' "$contest" "$EPOCHSECONDS" "$RANDOM" | md5sum | cut -d' ' -f1)"
    new="$(jq -cn --argjson cur "$cur" --arg id "$id" --arg t "$title" --arg x "$text" --argjson d "$EPOCHSECONDS" \
      '$cur + [{id:$id, title:$t, text:$x, date:$d}]')"
    ;;
  remove)
    id="$(jq -r '.id // empty' <<<"$body")"
    [[ -n "$id" ]] || fail 400 "Informe o id" "id_missing"
    new="$(jq -cn --argjson cur "$cur" --arg id "$id" '[ $cur[] | select(.id != $id) ]')"
    ;;
  *) fail 400 "action inválida (add|remove)" "action_invalid" ;;
esac
printf '%s' "$new" > "$f.tmp" && mv -f "$f.tmp" "$f"
audit_log_to "$contest" "news-$action" "$(jq -r '.title // .id // ""' <<<"$body" | head -c 120)"
ok_json '{saved:true, items:$n}' --argjson n "$new"
