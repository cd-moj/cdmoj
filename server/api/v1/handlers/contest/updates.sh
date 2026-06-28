# GET /contest/updates?contest=<id>&news_since=<epoch>&clar_since=<epoch>   (Bearer)
# Resumo LEVE p/ polling de notificações no front: últimas notícias e clarifications
# respondidas VISÍVEIS ao usuário, com contador de "não lidas" (date/answered_at > since).
# Alimenta o banner de novidades e o badge de clarifications não lidas.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

ns="$(param news_since)"; [[ "$ns" =~ ^[0-9]+$ ]] || ns=0
cs="$(param clar_since)"; [[ "$cs" =~ ^[0-9]+$ ]] || cs=0

# --- notícias: maior date + total + não lidas (date > news_since) ---
nf="$CONTESTSDIR/$contest/news.json"
if [[ -f "$nf" ]] && jq -e . "$nf" >/dev/null 2>&1; then
  news="$(jq -c --argjson s "$ns" '{last:([.[].date//0]|max//0), count:length,
      unread:([.[]|select((.date//0)>$s)]|length)}' "$nf")"
else
  news='{"last":0,"count":0,"unread":0}'
fi

# --- clarifications respondidas VISÍVEIS ao usuário (própria OU pública; admin/judge/mon: todas) ---
dir="$CONTESTSDIR/$contest/clarifications"
priv=false; { is_admin || is_judge || is_mon; } && priv=true
set +o noglob; shopt -s nullglob
arr=()
for f in "$dir"/*.json; do [[ -f "$f" ]] && arr+=("$(cat "$f")"); done
shopt -u nullglob
all="$( ((${#arr[@]})) && printf '%s\n' "${arr[@]}" | jq -cs '.' || echo '[]')"
clar="$(jq -c --arg me "$SESSION_LOGIN" --argjson priv "$priv" --argjson s "$cs" '
  [ .[] | select(($priv or .login==$me or (.public==true)) and ((.answer//"")|length)>0) ]
  | {last:([.[].answered_at//0]|max//0), count:length,
     unread:([.[]|select((.answered_at//0)>$s)]|length)}' <<<"$all")"

ok_json '{news:$n, clar:$c}' --argjson n "$news" --argjson c "$clar"
