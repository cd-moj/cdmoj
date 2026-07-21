# POST /problems/preview   (Bearer)   body: {enunciado_md, examples?, id?, images?}
# Renderiza o enunciado (Markdown canônico) em HTML — MESMO pandoc do build (`-f markdown
# --mathml -s`, então `% Título` e $math$ funcionam) — e injeta os exemplos (como o
# gen-problem-json). Devolve html_b64 p/ o editor mostrar num iframe. Imagens: coladas viram
# data:URI no texto (imunes); IMAGEM-ARQUIVO (`![](fig.png)` com a figura em docs/) só embute
# se ela estiver no diretório do render — por isso: com `id` (e permissão de edição) as
# imagens de docs/ do PACOTE são copiadas p/ o tempdir; `images:[{name,content_b64}]` cobre
# figura ainda não enviada (o moj preview manda as locais). Sem isso, o preview renderizava o
# texto num mktemp VAZIO e a figura sumia SÓ no preview (o servido embutia) — relato do Edson.
require_method POST
require_auth
source "$_DIR/lib/problems.sh"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
md="$(jq -r '.enunciado_md // ""' <<<"$body")"
fmt="$(jq -r '.enunciado_format // .format // "md"' <<<"$body")"
title="$(jq -r '.title // ""' <<<"$body")"
pid="$(jq -r '.id // empty' <<<"$body")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf '%s' "$md" > "$tmp/e.$fmt"

# imagens do PACOTE (id + permissão de edição — sem permissão, 403 do require, nada vaza)
if [[ -n "$pid" ]] && valid_id "$pid"; then
  require_problem_edit "$pid"
  _ppkg="$MOJ_PROBLEMS_DIR/${pid%%#*}/${pid##*#}"
  if [[ -d "$_ppkg/docs" ]]; then
    find "$_ppkg/docs" -maxdepth 1 -type f \
      \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' \
         -o -iname '*.svg' -o -iname '*.webp' \) -exec cp -t "$tmp" {} + 2>/dev/null
  fi
fi
# imagens AVULSAS do body (ainda não enviadas): nome saneado, só extensão de imagem, cap 16
i=0
while IFS= read -r -d '' inm && IFS= read -r -d '' ib64; do
  i=$((i+1)); (( i > 16 )) && break
  inm="${inm##*/}"
  [[ "$inm" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.(png|jpg|jpeg|gif|svg|webp|PNG|JPG|JPEG|GIF|SVG|WEBP)$ ]] || continue
  printf '%s' "$ib64" | base64 -d > "$tmp/$inm" 2>/dev/null || rm -f "$tmp/$inm"
done < <(jq --raw-output0 '.images[]? | (.name // ""), (.content_b64 // "")' <<<"$body" 2>/dev/null)

esc(){ sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }
exf="$tmp/ex.html"; : > "$exf"
if [[ "$(jq '(.examples // []) | length' <<<"$body" 2>/dev/null)" -gt 0 ]]; then
  { printf '<section class="moj-exemplos"><h2>Exemplos</h2>'
    while IFS= read -r p; do
      printf '<div class="moj-exemplo"><h4>Entrada</h4><pre>'; jq -r '.input'  <<<"$p" | esc
      printf '</pre><h4>Saída</h4><pre>';                      jq -r '.output' <<<"$p" | esc
      printf '</pre>'
      expl="$(jq -r '.explanation // ""' <<<"$p")"
      if [[ -n "$expl" ]]; then
        # mesmo pandoc do gen-problem-json, com resource-path no tempdir: imagem-arquivo
        # citada NA NOTA também aparece no preview
        nh="$(printf '%s' "$expl" | pandoc -f markdown -t html --embed-resources --resource-path="$tmp" 2>/dev/null)"
        [[ -n "$nh" ]] || nh="<p>$(printf '%s' "$expl" | esc)</p>"
        printf '<div class="moj-exemplo-nota">%s</div>' "$nh"
      fi
      printf '</div>'
    done < <(jq -c '.examples[]?' <<<"$body")
    printf '</section>'; } > "$exf"
fi

# MESMO renderizador usado p/ servir o enunciado ao aluno (render-statement.sh): o que você
# pré-visualiza é exatamente o que é gerado no índice do treino (gen-problem-json.sh).
bash "$MOJTOOLS_DIR/render-statement.sh" "$tmp/e.$fmt" "$fmt" "$exf" "$title" > "$tmp/out.html" 2>/dev/null
[[ -s "$tmp/out.html" ]] || fail 500 "Falha ao renderizar o enunciado" "render_fail"
# b64 em ARQUIVO -> --rawfile: statement grande (ex.: ~1.5MB) estourava o ARG_MAX no --arg -> preview vazio.
base64 -w0 < "$tmp/out.html" | tr -d '\n' > "$tmp/h.b64"
emit_json 200 OK
jq -cn --rawfile h "$tmp/h.b64" '{success:true, html_b64:$h}'
