#!/bin/bash
# docs/build-html.sh — compila os .md de docs/ em HTML legível (docs/html/) usando pandoc.
# Gera uma página por documento (com TOC + navegação) e um index.html. Build-free no resto
# do projeto, mas a documentação usa pandoc (já presente; também gera os enunciados do MOJ).
#   uso:  bash docs/build-html.sh
set -u
DOCS="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
OUT="$DOCS/html"; mkdir -p "$OUT"
command -v pandoc >/dev/null 2>&1 || { echo "ERRO: pandoc não encontrado (instale pandoc)"; exit 1; }
# docs traduzidos (pt · en · es): a lista única mora no docs/i18n.sh (ver docs/I18N.md, "Documentação")
source "$DOCS/i18n.sh"
# limpa build anterior (senão .md apagado — ou doc tirado da lista — deixa .html órfão servido)
rm -f "$OUT"/*.html "$OUT"/en/*.html "$OUT"/es/*.html

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
html[lang=en] #TOC::before{content:"Contents"}
html[lang=es] #TOC::before{content:"Contenido"}
nav.moj-nav .moj-langs{margin-left:auto;display:flex;gap:.5rem}
nav.moj-nav .moj-langs b{color:var(--fg)}
nav.moj-nav .moj-tech{flex-basis:100%;color:var(--mut);font-size:.85em;display:flex;gap:.7rem;flex-wrap:wrap}
nav.moj-nav .moj-tech a{font-weight:400}
CSS

ORDER=(OVERVIEW.md FLOW.md API.md PACOTE.md ENUNCIADO.md MANUAL-ORGS-COLECOES.md SCOREBOARD.md VIRTUAL.md I18N.md DEPLOY.md PULL-REQUESTS.md ADMIN.md MANUAL-ADMIN.md MANUAL-TREINO.md MANUAL-CONTEST.md MANUAL-LINGUAGENS.md MANUAL-STAFF.md MANUAL-JUIZ.md MANUAL-ANIMEITOR.md WEBCAST.md PLAN.md README.md)
title_of(){ local t; t="$(grep -m1 '^# ' "$1" 2>/dev/null | sed 's/^#\+ //')"; printf '%s' "${t:-$(basename "$1" .md)}"; }

# lista final de docs: ORDER primeiro, depois o resto em ordem alfabética (sem duplicar)
mapfile -t REST < <(cd "$DOCS" && ls *.md 2>/dev/null | grep -vxF -f <(printf '%s\n' "${ORDER[@]}"))
DOCLIST=(); for m in "${ORDER[@]}" "${REST[@]}"; do [[ -f "$DOCS/$m" ]] && DOCLIST+=("$m"); done

is_i18n(){ local x; for x in "${DOCS_I18N[@]}"; do [[ "$x" == "$1" ]] && return 0; done; return 1; }
# docs traduzidos na ORDEM do índice PT
I18NLIST=(); for m in "${DOCLIST[@]}"; do is_i18n "${m%.md}" && I18NLIST+=("${m%.md}"); done
TRANSLATED="$(IFS=,; printf '%s' "${I18NLIST[*]}")"

# seletor PT · EN · ES de um doc traduzido, visto do idioma <cur> (vazio p/ doc só-PT)
langs_of(){ local d="$1" cur="$2" up="" l
  is_i18n "$d" || return 0
  [[ "$cur" != pt ]] && up="../"
  printf '<span class="moj-langs">'
  for l in pt en es; do
    if [[ "$l" == "$cur" ]]; then printf '<b>%s</b>' "${l^^}"
    elif [[ "$l" == pt ]]; then printf '<a href="%s%s.html" hreflang="pt">PT</a>' "$up" "$d"
    else printf '<a href="%s%s/%s.html" hreflang="%s">%s</a>' "$up" "$l" "$d" "$l" "${l^^}"; fi
  done
  printf '</span>'; }

# ---------------------------------------------------------------- PT (a fonte; todos os docs)
for m in "${DOCLIST[@]}"; do
  NAV="$OUT/.nav.html"
  { printf '<nav class="moj-nav"><a href="index.html">🏠 Índice</a>'
    for n in "${DOCLIST[@]}"; do printf '<a href="%s.html">%s</a>' "${n%.md}" "${n%.md}"; done
    langs_of "${m%.md}" pt
    printf '</nav>'; } > "$NAV"
  # --mathml: as fórmulas ($…$) saem como MathML, desenhadas pelo navegador — sem ele o pandoc
  # aproxima em texto e deixa `\frac` e cia. como TeX cru (o ENUNCIADO.md é feito de fórmulas)
  pandoc "$DOCS/$m" -f gfm -t html5 -s --mathml --toc --toc-depth=2 \
    --lua-filter "$DOCS/md2html-links.lua" -M lang=pt-BR \
    --metadata title="$(title_of "$DOCS/$m") — MOJ docs" \
    -c moj-docs.css -B "$NAV" -o "$OUT/${m%.md}.html" \
    || { echo "ERRO ao compilar $m"; rm -f "$NAV"; exit 1; }
done

# index.html
{ printf '<nav class="moj-nav"><a href="index.html">🏠 Índice</a>'
  if (( ${#I18NLIST[@]} )); then printf '<span class="moj-langs"><b>PT</b><a href="en/index.html" hreflang="en">EN</a><a href="es/index.html" hreflang="es">ES</a></span>'; fi
  printf '</nav>\n<h1>MOJ — Documentação</h1>\n<p>Versão API-first do MOJ. Comece por <b>OVERVIEW</b>.</p>\n<ul>\n'
  for m in "${DOCLIST[@]}"; do printf '<li><a href="%s.html"><b>%s</b></a> — %s</li>\n' "${m%.md}" "${m%.md}" "$(title_of "$DOCS/$m")"; done
  printf '</ul>\n'; } | pandoc -f html -t html5 -s -M lang=pt-BR --metadata title="MOJ — Documentação" -c moj-docs.css -o "$OUT/index.html"

# ---------------------------------------------------------------- EN / ES (só os traduzidos)
# Nav: os traduzidos, depois a documentação TÉCNICA, que existe só em português (../X.html).
if (( ${#I18NLIST[@]} )); then
  for l in "${DOC_LANGS_I18N[@]}"; do
    mkdir -p "$OUT/$l"
    case "$l" in
      en) L_HOME="🏠 Index"; L_TECH="Technical documentation (Portuguese):"; L_TITLE="MOJ — Documentation"
          L_INTRO="User documentation of MOJ. The technical documentation is only in Portuguese." ;;
      es) L_HOME="🏠 Índice"; L_TECH="Documentación técnica (portugués):"; L_TITLE="MOJ — Documentación"
          L_INTRO="Documentación de usuario del MOJ. La documentación técnica está solo en portugués." ;;
    esac
    tech(){ printf '<span class="moj-tech">%s' "$L_TECH"
      for n in "${DOCLIST[@]}"; do is_i18n "${n%.md}" || printf '<a href="../%s.html" hreflang="pt">%s</a>' "${n%.md}" "${n%.md}"; done
      printf '</span>'; }
    for d in "${I18NLIST[@]}"; do
      src="$DOCS/$l/$d.md"; [[ -f "$src" ]] || { echo "ERRO: falta $l/$d.md (docs/i18n.sh status)"; exit 1; }
      NAV="$OUT/$l/.nav.html"
      { printf '<nav class="moj-nav"><a href="index.html">%s</a>' "$L_HOME"
        for n in "${I18NLIST[@]}"; do printf '<a href="%s.html">%s</a>' "$n" "$n"; done
        langs_of "$d" "$l"; tech
        printf '</nav>'; } > "$NAV"
      pandoc "$src" -f gfm -t html5 -s --mathml --toc --toc-depth=2 \
        --lua-filter "$DOCS/md2html-links.lua" -M lang="$l" -M moj-lang="$l" -M moj-translated="$TRANSLATED" \
        --metadata title="$(title_of "$src") — MOJ docs" \
        -c ../moj-docs.css -B "$NAV" -o "$OUT/$l/$d.html" \
        || { echo "ERRO ao compilar $l/$d.md"; rm -f "$NAV"; exit 1; }
      rm -f "$NAV"
    done
    { printf '<nav class="moj-nav"><a href="index.html">%s</a><span class="moj-langs">' "$L_HOME"
      for x in pt en es; do
        if [[ "$x" == "$l" ]]; then printf '<b>%s</b>' "${x^^}"
        elif [[ "$x" == pt ]]; then printf '<a href="../index.html" hreflang="pt">PT</a>'
        else printf '<a href="../%s/index.html" hreflang="%s">%s</a>' "$x" "$x" "${x^^}"; fi
      done
      printf '</span></nav>\n<h1>%s</h1>\n<p>%s</p>\n<ul>\n' "$L_TITLE" "$L_INTRO"
      for d in "${I18NLIST[@]}"; do printf '<li><a href="%s.html"><b>%s</b></a> — %s</li>\n' "$d" "$d" "$(title_of "$DOCS/$l/$d.md")"; done
      printf '</ul>\n<p>%s</p>\n<ul>\n' "$L_TECH"
      for n in "${DOCLIST[@]}"; do is_i18n "${n%.md}" || printf '<li><a href="../%s.html" hreflang="pt">%s</a> — %s</li>\n' "${n%.md}" "${n%.md}" "$(title_of "$DOCS/$n")"; done
      printf '</ul>\n'; } | pandoc -f html -t html5 -s -M lang="$l" --metadata title="$L_TITLE" -c ../moj-docs.css -o "$OUT/$l/index.html"
  done
fi

rm -f "$OUT/.nav.html"
echo "✓ $(find "$OUT" -name '*.html' | wc -l) páginas em $OUT — abra $OUT/index.html"
