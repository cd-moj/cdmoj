# GET /index/news  -> {success:true, news:[...], all_news_url}
# Lista as notícias de $NEWSDIR/*.json (cada arquivo é 1 objeto JSON), datas em EPOCH.
emit_json 200 OK
set +o noglob
shopt -s nullglob
files=("$NEWSDIR"/*.json)
shopt -u nullglob
if (( ${#files[@]} == 0 )); then
  jq -cn '{success:true, news:[], all_news_url:"https://github.com/cd-moj/cdmoj/wiki"}'
  exit 0
fi
# mais recentes primeiro (ordena por mtime desc)
jq -cs '{success:true, news:., all_news_url:"https://github.com/cd-moj/cdmoj/wiki"}' \
  $(ls -t "${files[@]}")
