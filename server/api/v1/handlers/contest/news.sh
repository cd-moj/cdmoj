# GET /contest/news?contest=<id>   (Bearer)
# Notícias específicas do contest (opcional). Lê contests/<id>/news.json se existir
# (array de {id,title,text,date}); senão {success:true, items:[]}.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

f="$CONTESTSDIR/$contest/news.json"
emit_json 200 OK
if [[ -f "$f" ]] && jq -e . "$f" >/dev/null 2>&1; then
  jq -c '{success:true, items:.}' "$f"
else
  jq -cn '{success:true, items:[]}'
fi
