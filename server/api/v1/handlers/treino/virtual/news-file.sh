# GET /treino/virtual/news-file?contest=<cid>&id=<news_id>   (Bearer do TREINO)
# O ANEXO de uma notícia do contest, pela MESMA regra de tempo do /treino/virtual/clarifications (10/11/2026): a notícia
# só existe para a run a partir do instante relativo em que saiu; a publicada depois do fim, só com a run terminada.
# Fora da janela = 404 igual ao de anexo inexistente. O arquivo é o do /contest/news-file (news-files/<id>/<nome>).
require_method GET
require_auth_contest treino
source "$_LIBDIR/virtual.sh"
cid="$(param contest)"; vr_gate "$cid"
vr_clock "$SESSION_LOGIN" "$cid" || fail 403 "Comece a participação virtual para ver os avisos" "virtual_not_started"
nid="$(param id)"
[[ "$nid" =~ ^[A-Za-z0-9]+$ ]] || fail 400 "id inválido" "id_invalid"
f="$CONTESTSDIR/$cid/news.json"
[[ -s "$f" ]] || fail 404 "Anexo não encontrado" "notfound"
fn="$(jq -r --arg id "$nid" --argjson st "$VR_START" --argjson dur "$VR_DUR" --argjson el "$VR_ELAPSED" \
        --argjson ended "$( (( VR_ENDED )) && echo true || echo false )" "$VR_TIME_JQ"'
  first(.[]? | objects | select((.id // "" | tostring) == $id)
    | select(vr_vis(vr_at([.date, .edited_at])))
    | .file.name // empty)' "$f" 2>/dev/null)"
[[ -n "$fn" ]] || fail 404 "Anexo não encontrado" "notfound"
safe="$(basename "$fn" | tr -cd 'A-Za-z0-9._-')"; [[ -n "$safe" ]] || fail 404 "Anexo não encontrado" "notfound"
path="$CONTESTSDIR/$cid/news-files/$nid/$safe"
[[ -f "$path" ]] || fail 404 "Anexo não encontrado" "notfound"
printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/octet-stream\r\n'
printf 'Content-Disposition: attachment; filename="%s"\r\n' "$safe"
printf 'Content-Length: %s\r\n' "$(stat -c%s "$path" 2>/dev/null || echo 0)"
printf '\r\n'
cat "$path"
