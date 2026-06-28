# GET /contest/news-file?contest=<id>&id=<news_id>   (Bearer)
# Baixa o ARQUIVO anexado a uma notícia (qualquer usuário logado no contest). O nome do
# arquivo vem do news.json (campo .file.name); o conteúdo de news-files/<news_id>/<name>.
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

nid="$(param id)"
[[ "$nid" =~ ^[A-Za-z0-9]+$ ]] || fail 400 "id inválido" "id_invalid"
f="$CONTESTSDIR/$contest/news.json"
[[ -f "$f" ]] || fail 404 "Sem notícias" "notfound"
fn="$(jq -r --arg id "$nid" '.[]? | select(.id==$id) | .file.name // empty' "$f" 2>/dev/null | head -1)"
[[ -n "$fn" ]] || fail 404 "Anexo não encontrado" "notfound"
safe="$(basename "$fn" | tr -cd 'A-Za-z0-9._-')"; [[ -n "$safe" ]] || fail 404 "Anexo inválido" "notfound"
path="$CONTESTSDIR/$contest/news-files/$nid/$safe"
[[ -f "$path" ]] || fail 404 "Arquivo ausente" "notfound"

printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/octet-stream\r\n'
printf 'Content-Disposition: attachment; filename="%s"\r\n' "$safe"
printf '\r\n'
cat "$path"
