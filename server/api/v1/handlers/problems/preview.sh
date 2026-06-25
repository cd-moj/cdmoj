# POST /problems/preview   (Bearer)   body: {enunciado_md, examples?}
# Renderiza o enunciado (Markdown canônico) em HTML — MESMO pandoc do build (`-f markdown
# --mathml -s`, então `% Título` e $math$ funcionam) — e injeta os exemplos (como o
# gen-problem-json). Devolve html_b64 p/ o editor mostrar num iframe. Imagens coladas viram
# data:URI no texto e `--embed-resources` as mantém embutidas.
require_method POST
require_auth

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
md="$(jq -r '.enunciado_md // ""' <<<"$body")"
fmt="$(jq -r '.enunciado_format // .format // "md"' <<<"$body")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf '%s' "$md" > "$tmp/e.$fmt"

esc(){ sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }
exf="$tmp/ex.html"; : > "$exf"
if [[ "$(jq '(.examples // []) | length' <<<"$body" 2>/dev/null)" -gt 0 ]]; then
  { printf '<section class="moj-exemplos"><h2>Exemplos</h2>'
    while IFS= read -r p; do
      printf '<div class="moj-exemplo"><h4>Entrada</h4><pre>'; jq -r '.input'  <<<"$p" | esc
      printf '</pre><h4>Saída</h4><pre>';                      jq -r '.output' <<<"$p" | esc
      printf '</pre></div>'
    done < <(jq -c '.examples[]?' <<<"$body")
    printf '</section>'; } > "$exf"
fi

# MESMO renderizador usado p/ servir o enunciado ao aluno (render-statement.sh): o que você
# pré-visualiza é exatamente o que é gerado no índice do treino (gen-problem-json.sh).
out="$(bash "$MOJTOOLS_DIR/render-statement.sh" "$tmp/e.$fmt" "$fmt" "$exf")"

emit_json 200 OK
jq -cn --arg h "$(printf '%s' "$out" | base64 -w0)" '{success:true, html_b64:$h}'
