# POST /treino/admin/news/preview  {body}  (.admin) -> {html_b64}
# Pré-visualização ao vivo do markdown da notícia (mesmo renderizador do detalhe).
require_method POST
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
md="$(jq -r '.body // ""' <<<"$body")"
# b64 do HTML em ARQUIVO -> --rawfile (notícia grande estouraria o ARG_MAX no --arg)
hb="$(mktemp)"; printf '%s' "$md" | render_markdown_html | base64 -w0 | tr -d '\n' > "$hb"
emit_json 200 OK
jq -cn --rawfile h "$hb" '{success:true, html_b64:$h}'; rm -f "$hb"
