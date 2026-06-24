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
case "$fmt" in org) pf=org;; tex) pf=latex;; *) pf=markdown;; esac
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf '%s' "$md" > "$tmp/e.$fmt"

html="$(pandoc -f "$pf" --mathml -s --embed-resources "$tmp/e.$fmt" 2>/dev/null)"
[[ -n "$html" ]] || html="$(printf '<!DOCTYPE html><html><head></head><body><pre>%s</pre></body></html>' \
  "$(printf '%s' "$md" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')")"

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

style='<style>body{font-family:system-ui,Arial,sans-serif;max-width:52rem;margin:1rem auto;padding:0 1rem;line-height:1.55;color:#111}pre{background:#f3f4f6;padding:.6rem;border-radius:6px;overflow:auto;white-space:pre-wrap}.moj-exemplo{border:1px solid #e5e7eb;border-radius:8px;padding:.2rem .8rem;margin:.6rem 0}.moj-exemplo h4{margin:.5rem 0 .2rem}img{max-width:100%}table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:.2rem .5rem}</style>'
out="$(awk -v ex="$exf" -v st="$style" '
  BEGIN{ s=""; while((getline l<ex)>0) s=s l "\n" }
  /<\/head>/{ print st }
  /<\/body>/{ printf "%s", s }
  { print }' <<<"$html")"

emit_json 200 OK
jq -cn --arg h "$(printf '%s' "$out" | base64 -w0)" '{success:true, html_b64:$h}'
