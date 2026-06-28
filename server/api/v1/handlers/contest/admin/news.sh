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
    # anexo opcional (aluno baixa): grava em news-files/<id>/<filename> e guarda {name,size}
    fileobj='null'
    fb64="$(jq -r '.file_b64 // empty' <<<"$body")"; fname="$(jq -r '.filename // empty' <<<"$body")"
    if [[ -n "$fb64" && -n "$fname" ]]; then
      safe="$(basename "$fname" | tr -cd 'A-Za-z0-9._-')"; [[ -n "$safe" ]] || safe="arquivo"
      ndir="$CONTESTSDIR/$contest/news-files/$id"; mkdir -p "$ndir"
      if printf '%s' "$fb64" | base64 -d > "$ndir/$safe" 2>/dev/null; then
        sz="$(stat -c%s "$ndir/$safe" 2>/dev/null || echo 0)"
        fileobj="$(jq -cn --arg n "$safe" --argjson s "${sz:-0}" '{name:$n, size:$s}')"
      else
        rm -rf "$ndir"; fail 422 "Arquivo inválido (base64)" "file_b64"
      fi
    fi
    new="$(jq -cn --argjson cur "$cur" --arg id "$id" --arg t "$title" --arg x "$text" --argjson d "$EPOCHSECONDS" --argjson file "$fileobj" \
      '$cur + [ {id:$id, title:$t, text:$x, date:$d} + (if $file==null then {} else {file:$file} end) ]')"
    ;;
  remove)
    id="$(jq -r '.id // empty' <<<"$body")"
    [[ -n "$id" ]] || fail 400 "Informe o id" "id_missing"
    [[ "$id" =~ ^[A-Za-z0-9]+$ ]] && rm -rf "$CONTESTSDIR/$contest/news-files/$id" 2>/dev/null   # limpa o anexo
    new="$(jq -cn --argjson cur "$cur" --arg id "$id" '[ $cur[] | select(.id != $id) ]')"
    ;;
  *) fail 400 "action inválida (add|remove)" "action_invalid" ;;
esac
printf '%s' "$new" > "$f.tmp" && mv -f "$f.tmp" "$f"
audit_log_to "$contest" "news-$action" "$(jq -r '.title // .id // ""' <<<"$body" | head -c 120)"
ok_json '{saved:true, items:$n}' --argjson n "$new"
