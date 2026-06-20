# GET  /treino/admin/news        (.admin) -> lista as notícias (com 'key' = nome do arquivo)
# POST /treino/admin/news  {title, summary?, url?, body?, date?}  -> cria notícia
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
ND="$NEWSDIR"

if [[ "$REQUEST_METHOD" == GET ]]; then
  emit_json 200 OK
  set +o noglob; shopt -s nullglob
  files=("$ND"/*.json); shopt -u nullglob
  if (( ${#files[@]} == 0 )); then jq -cn '{success:true, news:[]}'; exit 0; fi
  for f in "${files[@]}"; do
    b="${f##*/}"; jq -c --arg k "${b%.json}" '. + {key:$k}' "$f" 2>/dev/null
  done | jq -cs '{success:true, news:(sort_by(-(.date // 0)))}'
  exit 0
fi

require_method POST
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
title="$(jq -r '.title // empty' <<<"$body")"
[[ -n "$title" ]] || fail 400 "Título é obrigatório" "title_missing"
summary="$(jq -r '.summary // ""' <<<"$body")"
url="$(jq -r '.url // ""' <<<"$body")"
btext="$(jq -r '.body // ""' <<<"$body")"
date="$(jq -r '.date // empty' <<<"$body")"; [[ "$date" =~ ^[0-9]+$ ]] || date="$EPOCHSECONDS"

key="n${EPOCHSECONDS}${RANDOM}"
mkdir -p "$ND"
jq -n --arg k "$key" --arg t "$title" --argjson d "$date" --arg s "$summary" --arg u "$url" --arg b "$btext" \
  '{id:$k, key:$k, title:$t, date:$d, summary:$s, url:$u, body:$b}' > "$ND/$key.json"
audit_log news-add "key=$key title=\"$title\""
ok_json '{created:true, key:$k}' --arg k "$key"
