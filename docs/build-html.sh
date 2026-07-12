#!/bin/bash
# docs/build-html.sh — compila os .md de docs/ em HTML legível (docs/html/) usando pandoc.
# Gera uma página por documento (com TOC + navegação) e um index.html. Build-free no resto
# do projeto, mas a documentação usa pandoc (já presente; também gera os enunciados do MOJ).
#   uso:  bash docs/build-html.sh
set -u
DOCS="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
OUT="$DOCS/html"; mkdir -p "$OUT"
command -v pandoc >/dev/null 2>&1 || { echo "ERRO: pandoc não encontrado (instale pandoc)"; exit 1; }

cat > "$OUT/moj-docs.css" <<'CSS'
:root{--fg:#1f2d3d;--mut:#64748b;--ac:#1e57c4;--bd:#e3e9f2;--code:#f6f8fb}
*{box-sizing:border-box}
body{font:16px/1.6 -apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;color:var(--fg);max-width:900px;margin:0 auto;padding:1.4rem 1.2rem 4rem}
nav.moj-nav{display:flex;gap:.9rem;flex-wrap:wrap;border-bottom:1px solid var(--bd);padding-bottom:.6rem;margin-bottom:1.5rem;font-size:.9rem}
nav.moj-nav a{color:var(--ac);text-decoration:none;font-weight:600}
nav.moj-nav a:hover{text-decoration:underline}
h1,h2,h3,h4{line-height:1.25;margin-top:1.7rem}
h1{border-bottom:2px solid var(--bd);padding-bottom:.3rem}
a{color:var(--ac)}
code{background:var(--code);padding:.1em .35em;border-radius:4px;font-size:.88em}
pre{background:var(--code);border:1px solid var(--bd);border-radius:8px;padding:.9rem 1rem;overflow-x:auto;font-size:.84em;line-height:1.45}
pre code{background:none;padding:0}
table{border-collapse:collapse;width:100%;margin:1rem 0;font-size:.9em}
th,td{border:1px solid var(--bd);padding:.4rem .6rem;text-align:left;vertical-align:top}
th{background:#f1f5fb}
blockquote{border-left:4px solid var(--ac);margin:1rem 0;padding:.2rem 1rem;color:var(--mut);background:#f8fafd;border-radius:0 6px 6px 0}
#TOC{background:#f8fafd;border:1px solid var(--bd);border-radius:8px;padding:.5rem 1rem;font-size:.9em}
#TOC::before{content:"Conteúdo";font-weight:700;color:var(--mut);font-size:.85em}
CSS

ORDER=(OVERVIEW.md FLOW.md API.md PACOTE.md SCOREBOARD.md DEPLOY.md ADMIN.md MANUAL-TREINO.md MANUAL-CONTEST.md MANUAL-LINGUAGENS.md MANUAL-STAFF.md MANUAL-JUIZ.md PLAN.md README.md)
title_of(){ local t; t="$(grep -m1 '^# ' "$1" 2>/dev/null | sed 's/^#\+ //')"; printf '%s' "${t:-$(basename "$1" .md)}"; }

# lista final de docs: ORDER primeiro, depois o resto em ordem alfabética (sem duplicar)
mapfile -t REST < <(cd "$DOCS" && ls *.md 2>/dev/null | grep -vxF -f <(printf '%s\n' "${ORDER[@]}"))
DOCLIST=(); for m in "${ORDER[@]}" "${REST[@]}"; do [[ -f "$DOCS/$m" ]] && DOCLIST+=("$m"); done

# barra de navegação compartilhada
NAV="$OUT/.nav.html"
{ printf '<nav class="moj-nav"><a href="index.html">🏠 Índice</a>'
  for m in "${DOCLIST[@]}"; do printf '<a href="%s.html">%s</a>' "${m%.md}" "${m%.md}"; done
  printf '</nav>'; } > "$NAV"

for m in "${DOCLIST[@]}"; do
  pandoc "$DOCS/$m" -f gfm -t html5 -s --toc --toc-depth=2 \
    --metadata title="$(title_of "$DOCS/$m") — MOJ docs" \
    -c moj-docs.css -B "$NAV" -o "$OUT/${m%.md}.html" \
    || { echo "ERRO ao compilar $m"; rm -f "$NAV"; exit 1; }
done

# index.html
{ printf '<nav class="moj-nav"><a href="index.html">🏠 Índice</a></nav>\n'
  printf '<h1>MOJ — Documentação</h1>\n<p>Versão API-first do MOJ. Comece por <b>OVERVIEW</b>.</p>\n<ul>\n'
  for m in "${DOCLIST[@]}"; do printf '<li><a href="%s.html"><b>%s</b></a> — %s</li>\n' "${m%.md}" "${m%.md}" "$(title_of "$DOCS/$m")"; done
  printf '</ul>\n'; } | pandoc -f html -t html5 -s --metadata title="MOJ — Documentação" -c moj-docs.css -o "$OUT/index.html"

rm -f "$NAV"
echo "✓ $(ls "$OUT"/*.html | wc -l) páginas em $OUT — abra $OUT/index.html"
