# POST /problems/preview   (Bearer)   body: {enunciado_md, examples?, id?, images?, lang?, title?}
#                                        ou {kind:"editorial", markdown, id?, images?, lang?}
# Renderiza o enunciado (Markdown canônico) em HTML — MESMO pandoc do build (`-f markdown
# --mathml -s`, então `% Título` e $math$ funcionam) — e injeta os exemplos (como o
# gen-problem-json). Devolve html_b64 p/ o editor mostrar num iframe. Imagens: coladas viram
# data:URI no texto (imunes); IMAGEM-ARQUIVO (`![](fig.png)` com a figura em docs/) só embute
# se ela estiver no diretório do render — por isso: com `id` (e permissão de edição) as
# imagens de docs/ do PACOTE são copiadas p/ o tempdir; `images:[{name,content_b64}]` cobre
# figura ainda não enviada (o moj preview manda as locais). Sem isso, o preview renderizava o
# texto num mktemp VAZIO e a figura sumia SÓ no preview (o servido embutia) — relato do Edson.
#
# IDIOMA (2026-09-15): `lang` (pt|en|es, default pt) escolhe os rótulos dos exemplos
# (Exemplos/Entrada/Saída/Explicação nos 3 idiomas) e o `<html lang>`. O cliente manda o texto e
# as explicações JÁ no idioma que está editando (o fallback nota-PT é decisão do editor). Os
# exemplos são materializados num pacote TEMPORÁRIO (tests/input|output/sampleN + docs/notes) e
# o HTML deles sai do `stmt_samples_html` do mojtools — o MESMO gerador do gen-problem-json (a
# cópia local com <h4> que divergia do <h3> servido acabou aqui).
# `kind:"editorial"` renderiza SÓ markdown (sem exemplos e sem <h1> de título): é o botão
# "Pré-visualizar" da aba Resolução.
require_method POST
require_auth
source "$_DIR/lib/problems.sh"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
kind="$(jq -r '.kind // "statement"' <<<"$body")"
[[ "$kind" == statement || "$kind" == editorial ]] || fail 400 "kind inválido (statement|editorial)" "kind_invalid"
lang="$(jq -r '.lang // "pt"' <<<"$body")"
stmt_lang_ok "$lang" || fail 400 "lang inválido ($(stmt_langs_all))" "lang_invalid"
if [[ "$kind" == editorial ]]; then md="$(jq -r '.markdown // .editorial_md // ""' <<<"$body")"; fmt=md; title=""
else md="$(jq -r '.enunciado_md // ""' <<<"$body")"; fmt="$(jq -r '.enunciado_format // .format // "md"' <<<"$body")"; title="$(jq -r '.title // ""' <<<"$body")"; fi
[[ "$fmt" =~ ^(md|org|tex)$ ]] || fmt=md
pid="$(jq -r '.id // empty' <<<"$body")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/docs" "$tmp/tests/input" "$tmp/tests/output"
printf '%s' "$md" > "$tmp/docs/e.$fmt"

# imagens do PACOTE (id + permissão de edição — sem permissão, 404 do require_problem_edit, nada vaza)
if [[ -n "$pid" ]] && valid_id "$pid"; then
  require_problem_edit "$pid"
  _ppkg="$MOJ_PROBLEMS_DIR/${pid%%#*}/${pid##*#}"
  if [[ -d "$_ppkg/docs" ]]; then
    find "$_ppkg/docs" -maxdepth 1 -type f \
      \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' \
         -o -iname '*.svg' -o -iname '*.webp' \) -exec cp -t "$tmp/docs" {} + 2>/dev/null
  fi
fi
# imagens AVULSAS do body (ainda não enviadas): nome saneado, só extensão de imagem, cap 16
i=0
while IFS= read -r -d '' inm && IFS= read -r -d '' ib64; do
  i=$((i+1)); (( i > 16 )) && break
  inm="${inm##*/}"
  [[ "$inm" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.(png|jpg|jpeg|gif|svg|webp|PNG|JPG|JPEG|GIF|SVG|WEBP)$ ]] || continue
  printf '%s' "$ib64" | base64 -d > "$tmp/docs/$inm" 2>/dev/null || rm -f "$tmp/docs/$inm"
done < <(jq --raw-output0 '.images[]? | (.name // ""), (.content_b64 // "")' <<<"$body" 2>/dev/null)

# exemplos -> pacote temporário (sampleN + nota), HTML pelo gerador ÚNICO do mojtools
exf="$tmp/ex.html"; : > "$exf"
if [[ "$kind" == statement && "$(jq '(.examples // []) | length' <<<"$body" 2>/dev/null)" -gt 0 ]]; then
  n=0; samples=()
  while IFS= read -r -d '' xin && IFS= read -r -d '' xout && IFS= read -r -d '' xexp; do
    n=$((n+1)); (( n > 50 )) && break
    printf '%s' "$xin" > "$tmp/tests/input/sample$n"; printf '%s' "$xout" > "$tmp/tests/output/sample$n"
    if [[ -n "$xexp" ]]; then mkdir -p "$tmp/docs/notes"; printf '%s' "$xexp" > "$tmp/docs/notes/sample$n.md"; fi
    samples+=("sample$n")
  done < <(jq --raw-output0 '.examples[]? | (.input // ""), (.output // ""), (.explanation // "")' <<<"$body" 2>/dev/null)
  (( ${#samples[@]} )) && stmt_samples_html "$tmp" "$lang" "${samples[@]}" > "$exf"
fi

# MESMO renderizador usado p/ servir o enunciado ao aluno (render-statement.sh): o que você
# pré-visualiza é exatamente o que é gerado no índice do treino (gen-problem-json.sh).
bash "$MOJTOOLS_DIR/render-statement.sh" "$tmp/docs/e.$fmt" "$fmt" "$exf" "$title" "$lang" > "$tmp/out.html" 2>/dev/null
[[ -s "$tmp/out.html" ]] || fail 500 "Falha ao renderizar o enunciado" "render_fail"
# b64 em ARQUIVO -> --rawfile: statement grande (ex.: ~1.5MB) estourava o ARG_MAX no --arg -> preview vazio.
base64 -w0 < "$tmp/out.html" | tr -d '\n' > "$tmp/h.b64"
emit_json 200 OK
jq -cn --rawfile h "$tmp/h.b64" --arg l "$lang" --arg k "$kind" '{success:true, html_b64:$h, lang:$l, kind:$k}'
