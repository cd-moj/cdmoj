# POST /treino/admin/news/delete  {key}  (.admin) -> remove uma notícia
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
title="$(jq -r '.title // ""' "$f" 2>/dev/null)"
rm -f "$f"
audit_log news-delete "key=$key title=\"$title\""
ok_json '{deleted:true, key:$k}' --arg k "$key"
