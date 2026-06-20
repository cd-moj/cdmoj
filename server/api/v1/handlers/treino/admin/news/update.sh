# POST /treino/admin/news/update  {key, title, summary?, url?, body?, date?}  (.admin)
require_method POST
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
key="$(jq -r '.key // empty' <<<"$body")"
[[ -n "$key" ]] || fail 400 "key é obrigatória" "key_missing"
[[ "$key" =~ ^[A-Za-z0-9_-]+$ ]] || fail 400 "key inválida" "key_invalid"
f="$NEWSDIR/$key.json"
[[ -f "$f" ]] || fail 404 "Notícia não encontrada" "not_found"
title="$(jq -r '.title // empty' <<<"$body")"
[[ -n "$title" ]] || fail 400 "Título é obrigatório" "title_missing"
summary="$(jq -r '.summary // ""' <<<"$body")"
url="$(jq -r '.url // ""' <<<"$body")"
btext="$(jq -r '.body // ""' <<<"$body")"
date="$(jq -r '.date // empty' <<<"$body")"; [[ "$date" =~ ^[0-9]+$ ]] || date="$(jq -r '.date // empty' "$f")"
[[ "$date" =~ ^[0-9]+$ ]] || date="$EPOCHSECONDS"

jq --arg t "$title" --arg s "$summary" --arg u "$url" --arg b "$btext" --argjson d "$date" \
  '. + {title:$t, summary:$s, url:$u, body:$b, date:$d}' "$f" > "$f.tmp" && mv -f "$f.tmp" "$f"
audit_log news-edit "key=$key title=\"$title\""
ok_json '{updated:true, key:$k}' --arg k "$key"
