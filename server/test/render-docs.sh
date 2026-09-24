#!/bin/bash
# RENDERIZAÇÃO DE VERDADE dos documentos da prova — roda pandoc + soffice + pdfunite.
#
# Por que existe: `smoke-contest-docs.sh` cobre só os GATES, com PDFs falsos
# (`printf '%PDF-fake'`). Ninguém nunca rodou a cadeia real em teste — e foi assim que a
# tipografia apodreceu sem ninguém ver: capa em A4 e miolo em US Letter no MESMO caderno,
# `Heading 1` MENOR que o `Heading 2`, e itálico sintético porque a fonte do corpo não tinha
# itálico na imagem. Este teste afirma o que se vê no papel:
#   (1) toda página em A4;  (2) Latin Modern EMBARCADA no PDF;  (3) o texto sai mesmo
#   (pdftotext não-vazio, com os rótulos no idioma pedido, inclusive es).
#
# Precisa de pandoc + soffice + poppler (o dev tem; senão SKIP). Também roda DENTRO da imagem:
#    podman exec <container> bash /opt/moj/cdmoj/server/test/render-docs.sh
# Cobre também o EDITORIAL (2026-09-14): capa na página 1, UM problema por página, e o título
# interno da solução (`# Ideia`) NÃO abre página.
# E as FÓRMULAS COM BARRA (2026-09-24, relato do Arthur Botelho): o pandoc marca todo `|` do
# MathML como `form="prefix"` e o LibreOffice Math desenhava um `¿` vermelho em volta dele no
# caderno e no editorial — o `lib/odt-math-bars.py` reescreve as barras no ODT (ver
# `smoke-odt-math-bars.sh`); aqui se afirma o papel: nenhum `¿` e a fórmula presente.
set -u
# ROOT pelo caminho do script — mas o jeito de rodar isto é copiando o arquivo para dentro da
# imagem (`podman cp … :/tmp/`), e aí o caminho derivado não acha as libs: cai no /opt do container.
ROOT="${MOJ_SERVER_ROOT:-$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)}"
[[ -f "$ROOT/api/v1/lib/contest-docs.sh" ]] || ROOT=/opt/moj/cdmoj/server
for b in pandoc soffice pdfinfo pdffonts pdftotext; do
  command -v "$b" >/dev/null 2>&1 || { echo "SKIP: sem $b (rode dentro da imagem)"; exit 0; }
done

FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
export CONTESTSDIR="$FIX" _DIR="$ROOT/api/v1" SESSION_LOGIN=render.admin
NOW="$EPOCHSECONDS"
C="$FIX/rd"; mkdir -p "$C/docs" "$C/enunciados" "$C/var"
{ printf 'CONTEST_ID=rd\nCONTEST_NAME=Prova\\ de\\ Renderização\nCONTEST_TYPE=icpc\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\nMEMLIMITMB=1024\n' "$((NOW-3600))" "$((NOW+3600))"
  printf "PROBS=( x col#pa 'Soma Simples' A col#pa x col#pb 'Subtração' B col#pb )\n"; } > "$C/conf"
# um enunciado com os elementos que denunciam tipografia: itálico, negrito, código e tabela
cat > "$C/enunciados/col#pa.html" <<'HTML'
<!DOCTYPE html><html><head><meta charset="utf-8"><title>Soma</title></head><body>
<h1 class="moj-title">Soma Simples</h1>
<p>Dados dois inteiros <em>a</em> e <em>b</em>, com <strong>1 ≤ a, b ≤ 10⁹</strong>, escreva a
soma. Este parágrafo existe para haver texto suficiente para o justificado mostrar a que veio,
com pelo menos três linhas de corpo em A4.</p>
@@MATH@@
<h2>Entrada</h2><p>Uma linha com <em>a</em> e <em>b</em>.</p>
<h2>Saída</h2><p>Uma linha com a soma.</p>
<pre>2 3
5</pre>
</body></html>
HTML

# pacotes com docs/solucao.md (editorial) — pkg_path lê MOJ_PROBLEMS_DIR
export MOJ_PROBLEMS_DIR="$FIX/problems"
for p in pa pb; do mkdir -p "$FIX/problems/col/$p/docs"; done
printf '# Ideia\n\nSome os dois números.\n\n## Complexidade\n\n$O(1)$, e com barras: $O(n \\cdot |P|)$.\n' > "$FIX/problems/col/pa/docs/solucao.md"
printf 'Subtraia. Texto sem título interno.\n' > "$FIX/problems/col/pb/docs/solucao.md"
# IDIOMAS (2026-09-15): o problema A tem tradução EN — enunciado no contest (<skey>.en.html), editorial
# no pacote (solucao.en.md) e título no banco (statements.en.title); o B só PT. O caderno/editorial
# EN tem de trazer o texto EN de A e o PT de B; ES (sem tradução) cai no PT inteiro.
printf '# Idea\n\nAdd the two numbers.\n' > "$FIX/problems/col/pa/docs/solucao.en.md"
cat > "$C/enunciados/col#pa.en.html" <<'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>Simple Sum</title></head><body>
<h1 class="moj-title">Simple Sum</h1>
<p>Given two integers <em>a</em> and <em>b</em>, write their sum. ENGLISHTEXT.</p>
<h2>Input</h2><p>One line with <em>a</em> and <em>b</em>.</p>
<h2>Output</h2><p>One line with the sum.</p>
@@MATH@@
</body></html>
HTML
# fórmulas com barra no MathML de VERDADE (o `pandoc --mathml` do render-statement.sh), nas duas
# línguas do A: as formas que os pacotes usam (|S|, |a-b|, fração, O(n·|P|)) + a dupla e o \mid
MATHP="$(printf '%s\n' 'Barras: $1 \leq |S| \leq 10^5$, $|a-b|$, $\|v\|$, $a \mid b$, $\dfrac{|T - B|}{2}$, $O(n \cdot |P|)$ e $\begin{vmatrix}a&b\\c&d\end{vmatrix}$.' \
  | pandoc -f markdown -t html5 --mathml 2>/dev/null)"
for f in "$C/enunciados/col#pa.html" "$C/enunciados/col#pa.en.html"; do
  M="$MATHP" awk '$0 == "@@MATH@@" { print ENVIRON["M"]; next } { print }' "$f" > "$f.tmp" && mv -f "$f.tmp" "$f"
done
mkdir -p "$FIX/treino/var/jsons"
jq -cn --arg h "$(base64 -w0 < "$C/enunciados/col#pa.html")" --arg e "$(base64 -w0 < "$C/enunciados/col#pa.en.html")" \
  '{id:"col#pa", title:"Soma Simples", public:true, statement_html_b64:$h, statement_langs:["pt","en"], statements:{en:{title:"Simple Sum", html_b64:$e}}}' \
  > "$FIX/treino/var/jsons/col#pa.json"
printf '{"published":[], "editorial_note":"Nota do editorial."}' > "$C/docs/config.json"
source "$ROOT/api/v1/lib/common.sh" 2>/dev/null || true
source "$ROOT/api/v1/lib/contest-create.sh" 2>/dev/null || true
source "$ROOT/api/v1/lib/tl-store.sh" 2>/dev/null || true
source "$ROOT/api/v1/lib/contest-docs.sh"

pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; ((fail++)); fi; }
# o pdfinfo diz "595.304 x 841.89 pts (A4)" — o marcador (A4) é o que interessa (US Letter
# sairia "612 x 792 pts (letter)")
pages_a4(){ pdfinfo "$1" 2>/dev/null | grep -m1 '^Page size:' | grep -qi '(a4)'; }

for l in pt en es; do
  echo "== $l =="
  for t in info-sheet times contest editorial; do
    e="$(doc_build rd "$t" "$l" 2>/dev/null)"
    p="$(doc_file rd "$t" "$l" pdf)"
    ck "$t/$l gera PDF"        '[[ -s "$p" ]]'
    [[ -s "$p" ]] || continue
    # A4 = 595 x 842 pt (o Letter que vinha do reference.odt é 612 x 792)
    ck "$t/$l em A4"           'pages_a4 "$p"'
    ck "$t/$l com Latin Modern" 'pdffonts "$p" 2>/dev/null | grep -qi "LMRoman\|LatinModern\|LMMono"'
    # a folha de time limits é curta de propósito (uma tabela); o resto tem prosa
    ck "$t/$l com texto"       '[[ "$(pdftotext "$p" - 2>/dev/null | tr -d "[:space:]" | wc -c)" -gt 60 ]]'
  done
  # o rótulo tem de sair NO IDIOMA pedido (o es caía na chave crua antes da tabela)
  case "$l" in
    pt) want='Limites de tempo da prova';;
    en) want='Time Limits for the Contest';;
    es) want='Límites de tiempo';;
  esac
  ck "times/$l no idioma certo" 'pdftotext "$(doc_file rd times "$l" pdf)" - 2>/dev/null | grep -qF "$want"'
done

echo "== caderno: capa + problema no mesmo tamanho de página =="
sizes="$(pdfinfo -l 99 "$(doc_file rd contest pt pdf)" 2>/dev/null | grep -c 'x 792 pts')"
ck "nenhuma página em Letter" '[[ "${sizes:-0}" == 0 ]]'

echo "== editorial: capa + um problema por página =="
EP="$(doc_file rd editorial pt pdf)"
pg(){ pdftotext -f "$2" -l "$2" -layout "$1" - 2>/dev/null; }
ck "3 páginas (capa, A, B)"          '[[ "$(pdfinfo "$EP" | awk "/^Pages:/{print \$2}")" == 3 ]]'
ck "pág. 1 = capa com nota e índice"  'pg "$EP" 1 | grep -q "Editorial" && pg "$EP" 1 | grep -q "Nota do editorial" && pg "$EP" 1 | grep -q "Subtração"'
ck "pág. 2 = problema A inteiro"      'pg "$EP" 2 | grep -q "Problema A" && pg "$EP" 2 | grep -q "Ideia" && pg "$EP" 2 | grep -q "Complexidade"'
ck "pág. 3 = problema B"              'pg "$EP" 3 | grep -q "Problema B"'
ck "título interno NÃO abre página"   '! pg "$EP" 3 | grep -q "Ideia"'

echo "== idiomas: caderno/editorial EN usam a tradução; ES cai no PT =="
CT_EN="$(pdftotext -layout "$(doc_file rd contest en pdf)" - 2>/dev/null)"
ck "caderno EN: texto EN do A"          'grep -q "ENGLISHTEXT" <<<"$CT_EN"'
ck "caderno EN: título EN do A"         'grep -q "Simple Sum" <<<"$CT_EN"'
ck "caderno EN: B (sem tradução) em PT" 'grep -q "Subtra" <<<"$CT_EN"'
CT_ES="$(pdftotext -layout "$(doc_file rd contest es pdf)" - 2>/dev/null)"
ck "caderno ES: cai no PT (sem texto EN)" '! grep -q "ENGLISHTEXT" <<<"$CT_ES" && grep -q "Soma Simples" <<<"$CT_ES"'
CT_PT="$(pdftotext -layout "$(doc_file rd contest pt pdf)" - 2>/dev/null)"
ck "caderno PT: PT (sem texto EN)"      '! grep -q "ENGLISHTEXT" <<<"$CT_PT"'
ED_EN="$(pdftotext -layout "$(doc_file rd editorial en pdf)" - 2>/dev/null)"
ck "editorial EN: solucao.en.md do A"   'grep -q "Add the two numbers" <<<"$ED_EN" && ! grep -q "Some os dois" <<<"$ED_EN"'
ck "editorial EN: B cai no PT"          'grep -q "Subtraia" <<<"$ED_EN"'
TL_EN="$(pdftotext -layout "$(doc_file rd times en pdf)" - 2>/dev/null)"
ck "folha de TL EN: nome do A traduzido" 'grep -q "Simple Sum" <<<"$TL_EN"'

echo "== fórmulas com barra: sem o ¿ do LibreOffice Math (caderno pt/en e editorial) =="
ED_PT="$(pdftotext -layout "$(doc_file rd editorial pt pdf)" - 2>/dev/null)"
# o pdftotext do LibreOffice 25.2 (imagem) põe espaço dentro da barra ("|S |"): compara sem espaços
ck "caderno PT: a fórmula |S| está lá"  'tr -d " " <<<"$CT_PT" | grep -qF "|S|"'
ck "caderno PT: nenhum ¿"               '! grep -qF "¿" <<<"$CT_PT"'
ck "caderno EN: nenhum ¿"               '! grep -qF "¿" <<<"$CT_EN"'
ck "editorial PT: |P| está lá, sem ¿"   'tr -d " " <<<"$ED_PT" | grep -qF "|P|" && ! grep -qF "¿" <<<"$ED_PT"'

echo "== ambiente de julgamento: título novo, linhas de compilação, veredictos, penalidade =="
IP="$(doc_file rd info-sheet en pdf)"; IT="$(pdftotext -layout "$IP" - 2>/dev/null)"
ck "título Judging environment"       'grep -q "Judging environment" <<<"$IT"'
ck "linha do g++ com -std=gnu++20"    'grep -q "g++ -lm -O2 -static -std=gnu++20" <<<"$IT"'
ck "linha do java com -Xmx1024m"      'grep -q "Xmx1024m" <<<"$IT"'
ck "lista de veredictos"              'grep -q "Compilation Error" <<<"$IT" && grep -q "Not Answered Yet" <<<"$IT"'
ck "penalidade 20 min, CE sem"        'grep -q "20 minutes" <<<"$IT" && grep -A1 "without penalty" <<<"$IT" | grep -q "Compilation Error"'
ck "outros limites"                   'grep -q "1024 KB" <<<"$IT" && grep -q "250 MB" <<<"$IT"'
ck "sem marcador cru"                 '! grep -q "{{" <<<"$IT"'
TT="$(pdftotext -layout "$(doc_file rd times en pdf)" - 2>/dev/null)"
ck "times: nota de linguagem"         'grep -q "do not depend on the programming language" <<<"$TT"'
ck "times: em segundos"               'grep -q "Times are given in seconds" <<<"$TT"'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
