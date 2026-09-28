#!/bin/bash
# RENDERIZAÇÃO DE VERDADE dos documentos da prova — roda pandoc + soffice + pdfunite.
#
# Por que existe: `smoke-contest-docs.sh` cobre só os GATES, com PDFs falsos
# (`printf '%PDF-fake'`). Ninguém nunca rodou a cadeia real em teste — e foi assim que a
# tipografia apodreceu sem ninguém ver: capa em A4 e miolo em US Letter no MESMO caderno,
# `Heading 1` MENOR que o `Heading 2`, e itálico sintético porque a fonte do corpo não tinha
# itálico na imagem. Este teste afirma o que se vê no papel:
#   (1) toda página em A4;  (2) Computer Modern (CMU) ou Latin Modern EMBARCADA no PDF;  (3) o texto sai mesmo
#   (pdftotext não-vazio, com os rótulos no idioma pedido, inclusive es).
#
# E o .odt (25/09/2026): todo PDF gerado tem o gêmeo editável, o da rota HTML exporta de volta no MESMO
# PDF, o do caderno traz a capa editável + os enunciados; e a capa padrão sai do template etc/cover.<lang>.md.
# Precisa de pandoc + soffice + poppler (o dev tem; senão SKIP). Também roda DENTRO da imagem:
#    podman exec <container> bash /opt/moj/cdmoj/server/test/render-docs.sh
# Cobre também o EDITORIAL (2026-09-14): capa na página 1, UM problema por página, e o título
# interno da solução (`# Ideia`) NÃO abre página.
# E as FÓRMULAS COM BARRA (2026-09-24, relato do Arthur Botelho): o pandoc marca todo `|` do
# MathML como `form="prefix"` e o LibreOffice Math desenhava um `¿` vermelho em volta dele no
# caderno e no editorial — o `lib/odt-math-bars.py` reescreve as barras no ODT (ver
# `smoke-odt-math-bars.sh`); aqui se afirma o papel: nenhum `¿` e a fórmula presente. E a fórmula
# na fonte do corpo (nenhum DejaVu Serif no PDF — o fallback do LibreOffice Math sem settings).
# E as IMAGENS: nenhuma além da área útil do papel (o LibreOffice cortava a que passava da página).
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
<h2>Saída</h2><p>Uma linha com a soma. Paralelepípedo inconstitucionalíssimo, otorrinolaringologista,
anticonstitucionalissimamente e desproporcionalidades — palavras longas p/ a hifenização ter onde agir. 🌲</p>
<section class="moj-exemplos"><h2>Exemplos</h2>
<div class="moj-exemplo"><h3>Entrada</h3><pre data-sample="sample1" data-kind="input">2 3</pre>
<h3>Saída</h3><pre data-sample="sample1" data-kind="output">5</pre>
<div class="moj-exemplo-nota"><h3>Explicação</h3><p>2 + 3 = 5.</p></div></div>
</section>
</body></html>
HTML

# pacotes com docs/solucao.md (editorial) — pkg_path lê MOJ_PROBLEMS_DIR
export MOJ_PROBLEMS_DIR="$FIX/problems"
for p in pa pb; do mkdir -p "$FIX/problems/col/$p/docs"; done
printf '# Ideia\n\nSome os dois números.\n\n## Complexidade\n\n$O(1)$, e com barras: $O(n \\cdot |P|)$; ordenar é $O(n \\log n)$.\n' > "$FIX/problems/col/pa/docs/solucao.md"
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
  'Delimitadores: $(x_1, y_1)$, $[l, r)$, $x \in [0, 1)$, $a \# b$, $\alpha + \beta$ e $f(n) = \begin{cases} 1 & n = 0 \\ 2 & n > 0 \end{cases}$.' \
  'Índice sozinho: $t \in \mathbb{R}^+$ e $w \in \Sigma^*$.' \
  'Valores $\le 10^9$ e $\begin{aligned} S &= a \\ &= 10 \end{aligned}$.' \
  '' '::: center' 'Linha QZXW centralizada' ':::' \
  | pandoc -f markdown -t html5 --mathml 2>/dev/null)"
for f in "$C/enunciados/col#pa.html" "$C/enunciados/col#pa.en.html"; do
  M="$MATHP" awk '$0 == "@@MATH@@" { print ENVIRON["M"]; next } { print }' "$f" > "$f.tmp" && mv -f "$f.tmp" "$f"
done
# IMAGENS GRANDES no enunciado PT do A (24/09/2026: "não podem ficar gigantes nem sair da página"): um
# PNG de 1561 px sem DPI (o `rede-anel-estelar` da produção) e um de 700×3000 (mais alto que a página).
# Sem o passo de imagens do odt-math-bars.py o pandoc os punha a 1 px = 1 pt e o LibreOffice os CORTAVA.
python3 - "$C/enunciados/col#pa.html" <<'PY'
import sys, zlib, struct, base64
def png(w, h):
    raw = b''.join(b'\x00' + b'\x30\x70\xb0' * w for _ in range(h))
    ch = lambda t, d: struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + ch(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
            + ch(b'IDAT', zlib.compress(raw, 9)) + ch(b'IEND', b''))
u = lambda b: 'data:image/png;base64,' + base64.b64encode(b).decode()
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
img = '<p><img src="%s" alt="larga"></p>\n<p><img src="%s" alt="alta"></p>\n' % (u(png(1561, 1561)), u(png(700, 3000)))
open(p, 'w', encoding='utf-8').write(s.replace('<h2>Entrada</h2>', img + '<h2>Entrada</h2>', 1))
PY
# B: só PROSA, sem fórmula nem imagem — é nele que a entrelinha do corpo é medida (fórmula inline
# parte a linha do pdftotext e não serve de régua)
{ printf '<!DOCTYPE html><html><head><meta charset="utf-8"></head><body><h1 class="moj-title">Subtração</h1><p>'
  for i in 1 2 3 4 5 6; do printf 'Subtraia os dois números dados e escreva o resultado numa linha só, sem espaços sobrando no fim e com a quebra de linha que todo juiz espera. '; done
  printf '</p></body></html>'; } > "$C/enunciados/col#pb.html"
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
    ck "$t/$l informa odt_bytes (p/ a tela mostrar o ✎ .odt)" '[[ "$(jq -r ".odt_bytes // 0" <<<"$e")" -gt 0 ]]'
    [[ -s "$p" ]] || continue
    # A4 = 595 x 842 pt (o Letter que vinha do reference.odt é 612 x 792)
    ck "$t/$l em A4"           'pages_a4 "$p"'
    ck "$t/$l com Computer Modern (CMU) ou Latin Modern" 'pdffonts "$p" 2>/dev/null | grep -qi "CMUSerif\|CMUTypewriter\|LMRoman\|LatinModern\|LMMono"'
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

echo "== .odt: todo PDF gerado tem o gêmeo editável (25/09/2026) =="
# a organização baixa o .odt, ajusta no LibreOffice o que o Markdown deixou torto e sobe o PDF final
for l in pt en es; do for t in info-sheet times contest editorial; do
  o="$(doc_file rd "$t" "$l" odt)"
  ck "$t/$l gera .odt (ODT de texto)" '[[ -s "$o" && "$(unzip -p "$o" mimetype 2>/dev/null)" == application/vnd.oasis.opendocument.text ]]'
done; done
# o .odt da rota HTML (info sheet) É o intermediário: exportado de volta, dá o MESMO PDF
ox="$(mktemp -d)"
soffice --headless -env:UserInstallation="file://$ox/lo" --convert-to pdf --outdir "$ox" "$(doc_file rd info-sheet pt odt)" >/dev/null 2>&1
ck "info-sheet: o .odt exportado = mesmas páginas e mesmo texto do PDF" '[[ "$(pdfinfo "$ox/info-sheet.pt.pdf" 2>/dev/null | awk "/^Pages:/{print \$2}")" == "$(pdfinfo "$(doc_file rd info-sheet pt pdf)" | awk "/^Pages:/{print \$2}")" && "$(pdftotext "$ox/info-sheet.pt.pdf" - 2>/dev/null | tr -d "[:space:]")" == "$(pdftotext "$(doc_file rd info-sheet pt pdf)" - 2>/dev/null | tr -d "[:space:]")" ]]'
rm -rf "$ox"
# caderno: UM .odt com a capa editável (Title/Subtitle/Center) + os enunciados pela MESMA rota do miolo
CX="$(unzip -p "$(doc_file rd contest pt odt)" content.xml 2>/dev/null)"
ck "caderno .odt: capa com o nome em Title e a sessão em Subtitle" 'grep -q "style-name=\"Title\">Prova de Renderização" <<<"$CX" && grep -q "style-name=\"Subtitle\">Caderno de Problemas" <<<"$CX"'
ck "caderno .odt: os dois enunciados, com a linha centralizada em Center" 'grep -q "Soma Simples" <<<"$CX" && grep -q "Subtração" <<<"$CX" && grep -q "style-name=\"Center\">Linha QZXW" <<<"$CX"'
ck "caderno .odt: as fórmulas passaram pelo conserto das barras (nenhuma barra solta prefixa)" '[[ "$(unzip -p "$(doc_file rd contest pt odt)" "Object 1/content.xml" 2>/dev/null | grep -c "form=\"prefix\">|<")" == 0 ]]'

echo "== capa padrão = template (etc/cover.<lang>.md) =="
CV="$(pdftotext -f 1 -l 1 -layout "$(doc_file rd contest pt pdf)" - 2>/dev/null)"
ck "capa PT: nome, sessão, contagem com as páginas e versão" 'grep -q "Prova de Renderização" <<<"$CV" && grep -q "Caderno de Problemas" <<<"$CV" && grep -q "contém 2 problemas; páginas numeradas de 1 a" <<<"$CV" && grep -q "v1.0" <<<"$CV"'
ck "capa PT: sem sedes nem nota, os blocos opcionais somem" '! grep -q "Sedes participantes" <<<"$CV"'
CVE="$(pdftotext -f 1 -l 1 -layout "$(doc_file rd contest es pdf)" - 2>/dev/null)"
ck "capa ES: no idioma" 'grep -q "Cuadernillo de Problemas" <<<"$CVE"'

echo "== molde dos cadernos da SBC (28/09/2026: \"pouca cara de LaTeX\" na XIV Maratona UnB) =="
CP="$(doc_file rd contest pt pdf)"
NP="$(pdfinfo "$CP" 2>/dev/null | awk '/^Pages:/{print $2}')"
ck "capa: \"páginas de 1 a N\" = as numeradas (a capa não conta)" 'grep -q "numeradas de 1 a $(( NP - 1 ))" <<<"$CV"'
# entrelinha do corpo = a do LaTeX 11pt (13,6pt); a "simples" do LibreOffice com Latin Modern dava 15,6
PITCH="$(pdftotext -f "$NP" -l "$NP" -bbox-layout "$CP" /dev/stdout 2>/dev/null | python3 -c '
import re, sys, collections
g = collections.Counter()
for pg in sys.stdin.read().split("<page ")[1:]:
    # só linha LONGA de corpo (> 300pt): a do exemplo é curta e tem outra entrelinha (mono a 100%)
    ys = sorted(float(y2) for x1, y1, x2, y2 in re.findall(r"<line xMin=\"([\d.]+)\" yMin=\"([\d.]+)\" xMax=\"([\d.]+)\" yMax=\"([\d.]+)\"", pg) if float(x2) - float(x1) > 300)
    g.update(round(b - a, 1) for a, b in zip(ys, ys[1:]) if 10 < b - a < 17)
print(g.most_common(1)[0][0] if g else 0)')"
ck "entrelinha do corpo ≈ 13,6pt (LaTeX 11pt), não os 15,6 de antes (medida: $PITCH)" 'awk -v p="$PITCH" "BEGIN{exit !(p >= 12.8 && p <= 14.2)}"'
L2="$(pdftotext -f 2 -l "$NP" -layout "$CP" - 2>/dev/null)"
# exemplos: PADRÃO = empilhados como no site (decisão do Ribas: exemplo com linha longa quebra na meia
# página da célula); a tabela da SBC é opt-in do contest (`samples_table` no docs/config.json)
ck "exemplos (padrão): empilhados, sem tabela" 'grep -qx " *Exemplos *" <<<"$L2" && ! grep -q "Exemplo de entrada 1" <<<"$L2" && ! unzip -p "$(doc_file rd contest pt odt)" content.xml 2>/dev/null | grep -q "MojSampleTbl"'
cp -f "$C/docs/config.json" "$C/docs/config.json.bak" 2>/dev/null
jq -c '.samples_table = true' "$C/docs/config.json.bak" > "$C/docs/config.json" 2>/dev/null \
  || printf '{"samples_table":true}\n' > "$C/docs/config.json"
doc_build rd contest pt >/dev/null 2>&1
NPT="$(pdfinfo "$CP" 2>/dev/null | awk '/^Pages:/{print $2}')"
LT="$(pdftotext -f 2 -l "$NPT" -layout "$CP" - 2>/dev/null)"
ck "exemplos (samples_table): TABELA, entrada e saída lado a lado" 'grep -q "Exemplo de entrada 1 *Exemplo de saída 1" <<<"$LT"'
ck "exemplos (samples_table): \"Explicação do exemplo 1\"" 'grep -q "Explicação do exemplo 1" <<<"$LT"'
ck "exemplos (samples_table): título \"Exemplos\" some" '! grep -qx " *Exemplos *" <<<"$LT"'
if [[ -f "$C/docs/config.json.bak" ]]; then mv -f "$C/docs/config.json.bak" "$C/docs/config.json"; else rm -f "$C/docs/config.json"; fi
doc_build rd contest pt >/dev/null 2>&1
ck "rodapé: \"evento – Problema A – título\" e a página à direita" 'grep -q "Prova de Renderização – Problema A – Soma Simples *1 *$" <<<"$L2"'
ck "título do problema em sans (CMU Sans)" 'pdffonts "$CP" 2>/dev/null | grep -q "CMUSansSerif"'
ck "corpo em CMU Serif, sem DejaVu Serif" 'pdffonts "$CP" 2>/dev/null | grep -q "CMUSerif-Roman" && ! pdffonts "$CP" 2>/dev/null | grep -q "DejaVuSerif"'
# símbolo que a CMU não tem, digitado no TEXTO (o `1 ≤ a, b ≤ 10⁹` do fixture): o odt-caderno.py marca ≤ com a
# Latin Modern Math e troca o ⁹ pelo 9 da CMU em sobrescrito. Sem isso o LibreOffice escolhia sozinho — DejaVu
# Serif no 25.2 da imagem (que nem consulta o fontconfig p/ isso), DejaVu Sans no 26.2 do dev.
if fc-list 'Latin Modern Math' family 2>/dev/null | grep -q .; then
  ck "símbolo do texto em Latin Modern Math, nenhum DejaVu no caderno" 'pdffonts "$CP" 2>/dev/null | grep -q "LatinModernMath" && ! pdffonts "$CP" 2>/dev/null | grep -q "DejaVu"'
  ck "10⁹ do texto sai como 10 + 9 sobrescrito (ODT)" 'unzip -p "$(doc_file rd contest pt odt)" content.xml 2>/dev/null | grep -q "10<text:span text:style-name=\"MojSup\">9</text:span>"'
else echo "  (sem a Latin Modern Math — pulei o \"nenhum DejaVu\")"; fi
SX="$(unzip -p "$(doc_file rd contest pt odt)" styles.xml 2>/dev/null | tr '\n' ' ')"
ck "ODT: hifenização ligada e idioma pt-BR (antes en-US p/ tudo)" 'grep -q "fo:hyphenate=\"true\"" <<<"$SX" && grep -q "fo:language=\"pt\"" <<<"$SX" && grep -q "fo:country=\"BR\"" <<<"$SX"'
ck "ODT es: idioma es" 'unzip -p "$(doc_file rd contest es odt)" styles.xml 2>/dev/null | grep -q "fo:language=\"es\""'
# Emoji: a fonte COLRv1 (Fedora, o dev) sai embutida como TrueType mas EM BRANCO — o LibreOffice não
# desenha COLRv1 no PDF; a CBDT (Debian `fonts-noto-color-emoji`, a da imagem) sai como Type 3 com o
# bitmap colorido. Com CBDT no sistema exige-se Type 3 (desenhado); sem ela, só a presença.
EMF="$(fc-list ':charset=1f332' file family 2>/dev/null | grep -i 'emoji' | sort -t: -k2,2 | grep -i -m1 'color' | cut -d: -f1)"
if [[ -n "$(fc-list :charset=1f332 family 2>/dev/null)" ]]; then
  ck "emoji com fonte de emoji (🌲 não some)" 'pdffonts "$CP" 2>/dev/null | grep -qi "emoji"'
  if [[ -f "$EMF" ]] && head -c 1024 "$EMF" | grep -qa CBDT; then
    ck "emoji DESENHADO (fonte CBDT → Type 3 no PDF)" 'pdffonts "$CP" 2>/dev/null | grep -i "emoji" | grep -q "Type 3"'
  else echo "  (fonte de emoji não é CBDT (${EMF:-?}; COLRv1 sai em branco no PDF) — a prova do desenho é na imagem)"; fi
else echo "  (sem fonte de emoji no sistema — pulei)"; fi
# logo no cabeçalho (Evento › Documentos): o caderno e a capa ganham a imagem
magick -size 600x120 xc:'#1d4e89' "$C/docs/header-logo.png" 2>/dev/null
NI0="$(pdfimages -list "$CP" 2>/dev/null | awk 'NR>2' | wc -l)"
doc_build rd contest pt >/dev/null 2>&1
NI1="$(pdfimages -list "$CP" 2>/dev/null | awk 'NR>2' | wc -l)"
ck "logo: capa + uma por página numerada ($NI0 → $NI1 imagens)" '(( NI1 >= NI0 + NP ))'
ck "logo: o .odt tem a imagem em Pictures/" 'unzip -l "$(doc_file rd contest pt odt)" 2>/dev/null | grep -q "Pictures/moj-header-logo.png"'
rm -f "$C/docs/header-logo.png"; doc_build rd contest pt >/dev/null 2>&1

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
# nome de função inteiro: no pandoc 3.1 + LibreOffice 25.2 da imagem `O(n \log n)` saía "O(n l n)"
ck "editorial PT: \\log sai inteiro"       'tr -d " " <<<"$ED_PT" | grep -qF "nlog"'
# fórmula na fonte do CORPO: sem o settings.xml de fórmula (odt-math-bars.py) o LibreOffice Math
# usa o default dele, Liberation Serif — ausente na imagem, cai no DejaVu Serif, maior e largo.
# No caderno só o regular/itálico conta: o `DejaVuSerif-Bold` é o `≤`/`⁹` do <strong> em TEXTO do
# fixture (o Latin Modern Roman Bold não tem esses glifos) — não é fórmula.
# o grego do fixture (`\alpha`) só tem fonte com o fonts-cmu (CMU Serif); sem ele cai no DejaVu Serif
if [[ -n "$(fc-list 'CMU Serif:charset=3b1' family 2>/dev/null)" ]]; then
  ck "caderno PT: fórmula sem DejaVu Serif" '! pdffonts "$(doc_file rd contest pt pdf)" 2>/dev/null | grep -Eqi "DejaVuSerif(-Italic)?[[:space:]]"'
else
  echo "  SKIP: caderno PT: fórmula sem DejaVu Serif — falta o fonts-cmu (o grego cai no DejaVu Serif)"
fi
# delimitadores (odt-math-bars.py, fix_brackets/fix_syntax): `[l, r)` e `\#` eram ¿ — o "nenhum ¿" acima
# já cobre; aqui, que saem MESMO
ck "caderno PT: [l, r) e [0, 1) saem"    'tr -d " " <<<"$CT_PT" | grep -qF "[l,r)" && tr -d " " <<<"$CT_PT" | grep -qF "[0,1)"'
ck "caderno PT: a # b sai"               'tr -d " " <<<"$CT_PT" | grep -qF "a#b"'
# `::: center` (odt-center.lua + o estilo Center do reference-doc): a linha fica no MEIO da área útil
# (A4, margens iguais: o meio da página), medido no papel pelas caixas das palavras
ctr_off(){ pdftotext -bbox "$1" - 2>/dev/null | python3 -c '
import re, sys
s = sys.stdin.read(); W = float(re.search(r"<page width=\"([\d.]+)\"", s).group(1))
w = {m.group(3): (float(m.group(1)), float(m.group(2))) for m in re.finditer(r"<word xMin=\"([\d.]+)\" yMin=\"[\d.]+\" xMax=\"([\d.]+)\" yMax=\"[\d.]+\">([^<]*)</word>", s)}
a, b = w.get("Linha"), w.get("centralizada")
print("%.1f" % abs((a[0] + b[1]) / 2 - W / 2) if a and b else "sem-linha")'; }
CO="$(ctr_off "$(doc_file rd contest pt pdf)")"
ck "caderno PT: ::: center no meio da página (desvio $CO pt)" '[[ "$CO" != sem-linha ]] && awk -v d="$CO" "BEGIN{exit !(d < 3)}"'
ck "editorial PT: fórmula sem DejaVu Serif" '! pdffonts "$(doc_file rd editorial pt pdf)" 2>/dev/null | grep -qi "DejaVuSerif"'

echo "== imagens: nenhuma sai da página (tamanho DESENHADO = px ÷ ppi, pelo pdfimages) =="
# área útil do caderno-reference.odt: 16 cm = 6,30 pol de largura; altura máx. de imagem 619,94 pt =
# 8,61 pol (90% do corpo, margem inferior de 1,8 cm desde o molde SBC). 2% de folga p/ o ppi que o pdfimages arredonda. Antes: 21,7 pol, cortada.
IMGS="$(pdfimages -list "$(doc_file rd contest pt pdf)" 2>/dev/null | awk '$3=="image" && $13>0 && $14>0 {printf "%.3f %.3f\n", $4/$13, $5/$14}')"
DBG="$IMGS"
ck "caderno PT: as 2 imagens grandes estão lá"   '[[ "$(grep -c . <<<"$IMGS")" -ge 2 ]]'
ck "caderno PT: nenhuma imagem além da área útil" '[[ -z "$(awk '"'"'$1 > 6.30*1.02 || $2 > 8.61*1.02'"'"' <<<"$IMGS")" ]]'

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
