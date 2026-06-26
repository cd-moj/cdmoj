# GET /index/news            -> {success, news:[{key,title,date,summary,url,is_local}], all_news_url}
# GET /index/news?id=<key>   -> {success, news:{...campos..., body, body_html_b64, is_local}}
# Notícias/posts vivem em $NEWSDIR/<key>.json (1 objeto/arquivo). `body` é markdown;
# `url` vazio = notícia LOCAL (texto completo servido aqui). Datas em EPOCH.
set +o noglob
id="$(param id)"

# --- detalhe de uma notícia (com body renderizado) ---
if [[ -n "$id" ]]; then
  [[ "$id" =~ ^[A-Za-z0-9_-]+$ ]] || fail 400 "id inválido" "news_id_invalid"
  f="$NEWSDIR/$id.json"
  [[ -f "$f" ]] || fail 404 "Notícia não encontrada" "news_not_found"
  bh="$(jq -r '.body // ""' "$f" | render_markdown_html | base64 -w0)"
  emit_json 200 OK
  jq -c --arg k "$id" --arg bh "$bh" \
    '{success:true, news:(. + {key:$k, is_local:((.url // "")==""), body_html_b64:$bh})}' "$f"
  exit 0
fi

# --- lista (projeção leve, sem body) ---
emit_json 200 OK
shopt -s nullglob
files=("$NEWSDIR"/*.json)
shopt -u nullglob
if (( ${#files[@]} == 0 )); then
  jq -cn '{success:true, news:[], all_news_url:"/noticias/"}'
  exit 0
fi
for f in "${files[@]}"; do
  b="${f##*/}"
  jq -c --arg k "${b%.json}" \
    '{key:$k, title, date:(.date // 0), summary:(.summary // ""), url:(.url // ""), is_local:((.url // "")=="")}' \
    "$f" 2>/dev/null
done | jq -cs '{success:true, news:(sort_by(-(.date // 0))), all_news_url:"/noticias/"}'
