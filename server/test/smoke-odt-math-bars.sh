#!/bin/bash
# smoke-odt-math-bars.sh — as BARRAS VERTICAIS das fórmulas no PDF da prova (lib/odt-math-bars.py).
#
# Relato do Arthur Botelho (24/09/2026): no caderno gerado, todo `|` de fórmula saía com um `¿`
# vermelho em volta. O pandoc marca todo `|` do MathML como `form="prefix"` (inclusive o que fecha) e
# o LibreOffice Math não monta isso; o `odt-math-bars.py` reescreve as barras no ODT, entre o pandoc e
# o soffice (`_doc_html2pdf_odt`). Este teste prende:
#   1. o PAPEL de cada barra (abre/fecha/meio/solta) sobre o MathML DE VERDADE do `pandoc --mathml`
#      — as formas que os pacotes usam e as armadilhas do texmath (`<mi>−</mi>` depois de barra;
#      `\bigr|` saindo `form="prefix"`; no pandoc 3.1 da IMAGEM, `\|` nu e `vmatrix` com `<mi>∣</mi>`).
#      ⚠ O pandoc do dev (3.7) e o da imagem (3.1.11) agrupam diferente as entradas AMBÍGUAS; ali a
#      coluna aceita as duas leituras (`A / B`) — as duas desenham as barras sem ¿. Rode DENTRO do
#      container depois do deploy: o 1º deploy deste conserto passou no dev e deixou ¿ na produção;
#   2. o ZIP: mimetype 1º e sem compressão, o resto intacto, nenhuma barra sem `fence`, idempotente,
#      documento sem barra intocado, ODT quebrado = arquivo intacto e saída ≠ 0 (fail-open).
#   3. NOME DE FUNÇÃO: `<mo>log</mo>` (pandoc 3.1 da imagem; o LibreOffice 25.2 desenhava só "l",
#      `O(n \log n)` virava "O(n l n)") sai `<mi>log</mi>`.
#   4. TIPOGRAFIA: o settings.xml de TODA fórmula (com barra ou não) sai com o tamanho do corpo do
#      reference-doc (11pt), a família CMU Serif (fonts-cmu; sem ele, a do corpo, Latin Modern Roman)
#      e o itálico das variáveis DEPOIS do nome — sem isso o LibreOffice Math desenhava a fórmula em
#      12pt e no DejaVu Serif, no meio do texto.
#   5. IMAGENS: no menor entre o tamanho da web (px × 0,75 pt) e o do DPI do arquivo (nunca cresce),
#      nunca além da área útil (a imagem de 1561 px
#      saía com 1561 pt e o LibreOffice a CORTAVA), proporção mantida, `{width=50%}` do autor vira
#      `rel-width` (passo `--html-widths`, antes do pandoc), fórmula intocada, idempotente.
#   6. PARÊNTESES/SINTAXE (--fix): par comum sem esticar (`(x_1, y_1)`, `|a_i|`), esticado só em volta
#      de conteúdo alto (fração, \binom, vmatrix); `[l, r)` com delimitadores literais (era ¿); `cases`
#      com o fecho vazio (era a chave espelhada); `\#`/`\&`/`\_` como texto (eram ¿ / ∧ / índice);
#      relação na ponta do grupo (`$\le 10^9$`, `aligned`) com o grupo vazio `{}` (era ¿).
# O papel impresso (nenhum `¿` no pdftotext) é afirmado pelo render-docs.sh, que roda o soffice.
# Precisa de pandoc + python3 (dev e imagem têm); senão SKIP. Roda também dentro da imagem.
set -u
ROOT="${MOJ_SERVER_ROOT:-$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)}"
[[ -f "$ROOT/api/v1/lib/odt-math-bars.py" ]] || ROOT=/opt/moj/cdmoj/server
PY="$ROOT/api/v1/lib/odt-math-bars.py"
for b in pandoc python3; do
  command -v "$b" >/dev/null 2>&1 || { echo "SKIP: sem $b"; exit 0; }
done
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:-}"; ((fail++)); fi; }
mml(){ printf '$%s$\n' "$1" | pandoc -f markdown -t html5 --mathml 2>/dev/null; }

echo "== papéis (O abre, C fecha, M meio, L solta; D = barra dupla) =="
# TeX <TAB> papéis esperados, na ordem do documento
while IFS=$'\t' read -r tex want; do
  [[ -z "$tex" || "$tex" == \#* ]] && continue
  got="$(mml "$tex" | python3 "$PY" --roles 2>&1)"
  hit=0; IFS='/' read -ra alts <<<"$want"; (( ${#alts[@]} )) || alts=('')
  for a in "${alts[@]}"; do a="${a# }"; a="${a% }"; [[ "$got" == "$a" ]] && hit=1; done
  DBG="got='$got'"
  ck "$(printf '%-34s → %s' "$tex" "${want:-(nenhuma)}")" '(( hit ))'
done <<'EOF'
# as formas que os pacotes do dev usam
|x|	O C
1 \leq |P| \leq 16	O C
O(n \cdot |P|)	O C
\dfrac{|T - B| \times 70}{2}	O C
E \cdot |c| \le 10^4	O C
|j - i| \leq C	O C
# a do meio
a|b	M
P(A|B)	M
x\vert y	M
x \mid y	M
P(A \mid B)	M
\{x \mid x>0\}	M
# o pandoc 3.1 agrupa `x | |x|` como `x <mrow>| |</mrow>`: a do meio na borda do grupo sai solta
\{x | |x|<5\}	M O C / L L L
\{x\mid|x|<5\}	M O C
# aninhadas / em sequência — o `-` depois de barra vem como <mi>−</mi>
||x|-|y||	O O C O C C / O C L L O C
|a|+|b|	O C O C
|x|-|y|	O C O C
|S_1|+|S_2|\le|S|	O C O C O C
|x| \text{ e } |y|	O C O C
# dentro de índice/base de script
|x_i-x_j|	O C
\sum_{i=1}^n|a_i|	O C
|x|^2+|y|_1	O C O C
|A'|	O C
|x|!	O C
\log|x|	O C
|\{1,2,3\}|=3	O C
# duplas
\|v\|	DO DC
\lVert v\rVert	DO DC
\left\|v\right\|	DO DC
a \parallel b	DM
a \| b	DM
# esticáveis — o `\bigr|` sai `form="prefix"` no texmath: só o postfix é confiável
\left| \frac{a}{b} \right|	O C
a \left| b \right|	O C
\bigl| x \bigr|	O C
\left.f(x)\right|_0^1	L
\vert x \vert	O C
\begin{vmatrix}a&b\\c&d\end{vmatrix}	O C
# texto não é fórmula
\text{a|b}
EOF

echo "== ZIP =="
{ printf '<p>Barras: %s e %s e %s.</p>\n' "$(mml '1 \leq |S| \leq 10^5')" "$(mml '\|v\|')" "$(mml 'a|b')"
  printf '<p>Sem barra: %s.</p>\n' "$(mml 'x^2')"; } > "$FIX/a.html"
printf '<p>Só %s, nenhuma barra.</p>\n' "$(mml 'x^2 + 1')" > "$FIX/b.html"
REF="$ROOT/etc/caderno-reference.odt"; refodt=(); [[ -f "$REF" ]] && refodt=( --reference-doc="$REF" )
pandoc -f html -t odt "${refodt[@]}" "$FIX/a.html" -o "$FIX/a.odt"
pandoc -f html -t odt "${refodt[@]}" "$FIX/b.html" -o "$FIX/b.odt"
cp "$FIX/a.odt" "$FIX/a0.odt"; cp "$FIX/b.odt" "$FIX/b0.odt"
sha(){ sha256sum "$1" | cut -d' ' -f1; }

n1="$(python3 "$PY" "$FIX/a.odt")"; rc1=$?
DBG="rc=$rc1 n=$n1"
ck "reescreve as 3 fórmulas com barra (a sem barra fica)" '[[ $rc1 == 0 && "$n1" == 3 ]]'
# inspeção: mimetype 1º/stored; mesmas entradas; só content.xml de fórmula mudou; nenhuma barra
# `|`/`‖` sem fence; a do meio virou ∣
# família das fórmulas: CMU Serif (fonts-cmu, tem grego) quando instalado; senão a do corpo
MFAM='Latin Modern Roman'; [[ -n "$(fc-list 'CMU Serif:charset=3b1' family 2>/dev/null)" ]] && MFAM='CMU Serif'
insp="$(MFAM="$MFAM" python3 - "$FIX/a0.odt" "$FIX/a.odt" <<'PY'
import os, sys, zipfile, re
a, b = zipfile.ZipFile(sys.argv[1]), zipfile.ZipFile(sys.argv[2])
ib = b.infolist()
print('first', ib[0].filename, ib[0].compress_type == zipfile.ZIP_STORED)
print('names', sorted(a.namelist()) == sorted(b.namelist()))
changed = [n for n in a.namelist() if a.read(n) != b.read(n)]
print('changed', all(re.match(r'^[^/]+/(content|settings)\.xml$', n) for n in changed),
      sum(n.endswith('/content.xml') for n in changed))
# tipografia: todo settings.xml de fórmula com o corpo do reference-doc, itálico depois do nome
typo = total = 0
for n in b.namelist():
    if not re.match(r'^[^/]+/settings\.xml$', n): continue
    total += 1; x = b.read(n).decode('utf-8')
    item = lambda k: re.search(r'config:name="%s"[^>]*>([^<]*)<' % k, x)
    iv, ii = item('FontNameVariables'), item('FontVariablesIsItalic')
    if (item('BaseFontHeight') and item('BaseFontHeight').group(1) == '11' and iv and ii
            and iv.group(1) == os.environ['MFAM'] and ii.group(1) == 'true' and iv.start() < ii.start()
            and 'IsTextMode' in x):
        typo += 1
print('typo', typo, total)
bad = mid = 0
for n in b.namelist():
    if not n.endswith('/content.xml'): continue
    x = b.read(n).decode('utf-8')
    for m in re.finditer(r'<mo([^>]*)>([|‖])</mo>', x):
        if 'fence="true"' not in m.group(1): bad += 1
    mid += x.count('<mo>∣</mo>')
print('bad', bad); print('mid', mid)
print('test', b.testzip() is None)
PY
)"
DBG="$insp"
ck "mimetype é a 1ª entrada, sem compressão"       'grep -qx "first mimetype True" <<<"$insp"'
ck "as mesmas entradas"                              'grep -qx "names True" <<<"$insp"'
ck "só mudou fórmula: MathML de 3, e settings.xml"   'grep -qx "changed True 3" <<<"$insp"'
ck "tipografia nas 4 fórmulas (11pt, $MFAM)"       'grep -qx "typo 4 4" <<<"$insp"'
ck "nenhuma barra de par sem fence"                  'grep -qx "bad 0" <<<"$insp"'
ck "a do meio virou ∣"                               'grep -qx "mid 1" <<<"$insp"'
ck "zip íntegro"                                     'grep -qx "test True" <<<"$insp"'
s1="$(sha "$FIX/a.odt")"; n2="$(python3 "$PY" "$FIX/a.odt")"
DBG="n2=$n2"
ck "idempotente: 2ª passada não muda nada"           '[[ "$n2" == 0 && "$(sha "$FIX/a.odt")" == "$s1" ]]'
n3="$(python3 "$PY" "$FIX/b.odt")"
DBG="n3=$n3"
# sem barra, o MathML fica intacto; só a tipografia (settings.xml da fórmula) muda
dch="$(python3 -c 'import sys,zipfile; a,b=zipfile.ZipFile(sys.argv[1]),zipfile.ZipFile(sys.argv[2]); print(" ".join(n for n in a.namelist() if a.read(n)!=b.read(n)))' "$FIX/b0.odt" "$FIX/b.odt")"
DBG="n3=$n3 changed=$dch"
ck "documento sem barra: só a tipografia muda"       '[[ "$n3" == 0 && "$dch" =~ ^Formula-[0-9]+/settings\.xml$ ]]'
head -c 3000 "$FIX/a0.odt" > "$FIX/q.odt"; sq="$(sha "$FIX/q.odt")"
python3 "$PY" "$FIX/q.odt" >/dev/null 2>&1; rcq=$?
DBG="rc=$rcq"
ck "ODT quebrado: saída ≠ 0 e arquivo intacto"      '[[ $rcq != 0 && "$(sha "$FIX/q.odt")" == "$sq" ]]'
ck "…sem temporário largado no diretório"            '[[ -z "$(find "$FIX" -name "tmp*.odt")" ]]'

echo "== nome de função (o pandoc 3.1 da imagem emite <mo>log</mo>; o LibreOffice 25.2 desenha só \"l\") =="
# ODT feito à mão no formato do pandoc 3.1 — o pandoc do dev (3.7) já emite <mi>log</mi> e não o produz
python3 - "$FIX/fn.odt" <<'PY'
import sys, zipfile
x = ('<?xml version=\'1.0\' ?>\n<math display="inline" xmlns="http://www.w3.org/1998/Math/MathML"><mrow>'
     '<mi>O</mi><mo>(</mo><mi>n</mi><mo>log</mo><mi>n</mi><mo>)</mo><mo>+</mo>'
     '<munder><mo>lim</mo><mi>x</mi></munder><mo>≤</mo><mo>|</mo><mi>x</mi><mo>|</mo></mrow></math>')
with zipfile.ZipFile(sys.argv[1], 'w') as z:
    z.writestr('mimetype', 'application/vnd.oasis.opendocument.text', compress_type=zipfile.ZIP_STORED)
    z.writestr('Formula-1/content.xml', x, compress_type=zipfile.ZIP_DEFLATED)
PY
nf="$(python3 "$PY" "$FIX/fn.odt")"
fx="$(python3 -c 'import sys,zipfile; print(zipfile.ZipFile(sys.argv[1]).read("Formula-1/content.xml").decode())' "$FIX/fn.odt")"
DBG="n=$nf xml=$fx"
ck "reescreve a fórmula"                           '[[ "$nf" == 1 ]]'
ck "<mo>log</mo> e <mo>lim</mo> viram <mi>"        'grep -q "<mi>log</mi>" <<<"$fx" && grep -q "<mi>lim</mi>" <<<"$fx" && ! grep -qE "<mo>[A-Za-z]{2,}</mo>" <<<"$fx"'
ck "operador e parêntese ficam <mo>"               'grep -qF "<mo>≤</mo>" <<<"$fx" && grep -qF "<mo>(</mo>" <<<"$fx"'
ck "as barras nuas saem em par"                    '[[ "$(grep -o "fence=\"true\"" <<<"$fx" | wc -l)" == 2 ]]'
ck "2ª passada não muda nada"                      '[[ "$(python3 "$PY" "$FIX/fn.odt")" == 0 ]]'

echo "== imagens: tamanho da web (px × 0,75 pt) ou do DPI, teto na área útil, largura do autor =="
# Área útil do caderno-reference.odt: A4 com margens de 2,5 cm = 453,54 pt de largura; altura do corpo
# (menos o rodapé de 0,6 pol) × 0,9 = 591,26 pt. Mudou o reference-doc? Mude aqui.
MAXW=453.54; MAXH=591.26
python3 - "$FIX/img.html" "$(mml 'x^2 + |y|')" <<'PY'
import sys, zlib, struct, base64
def png(w, h, dpi=None):
    raw = b''.join(b'\x00' + b'\x80\x40\x40' * w for _ in range(h))
    ch = lambda t, d: struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    o = b'\x89PNG\r\n\x1a\n' + ch(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
    if dpi: o += ch(b'pHYs', struct.pack('>IIB', round(dpi / 0.0254), round(dpi / 0.0254), 1))
    return o + ch(b'IDAT', zlib.compress(raw, 9)) + ch(b'IEND', b'')
u = lambda b, t='image/png': 'data:%s;base64,%s' % (t, base64.b64encode(b).decode())
svg = b'<svg xmlns="http://www.w3.org/2000/svg" width="2000" height="600"><rect width="2000" height="600" fill="#48c"/></svg>'
big = u(png(1561, 1561))
h = '<html><body>\n'
h += '<p>i1 <img src="%s" alt="larga"></p>\n' % big                       # 1561x1561 sem DPI
h += '<p>i2 <img src="%s" alt="alta"></p>\n' % u(png(700, 3000))          # mais alta que a página
h += '<p>i3 <img src="%s" alt="pequena"></p>\n' % u(png(300, 200))        # cabe: tamanho da web
h += '<p>i4 <img src="%s" alt="a4-300dpi"></p>\n' % u(png(2481, 3508, 300))
h += '<p>i5 <img src="%s" alt="svg"></p>\n' % u(svg, 'image/svg+xml')
h += '<p>i6 <img src="%s" style="width:50.0%%" alt="autor"></p>\n' % big   # {width=50%} do autor
h += '<figure><img src="%s" alt="fig"><figcaption>Legenda</figcaption></figure>\n' % big
h += '<p>i8 <img src="%s" alt="obi-300dpi"></p>\n' % u(png(600, 300, 300))   # DPI de impressão: não cresce
h += '<p>fórmula %s fim.</p>\n</body></html>\n' % sys.argv[2]
open(sys.argv[1], 'w').write(h)
PY
nh="$(python3 "$PY" --html-widths "$FIX/img.html")"
DBG="nh=$nh"
ck "--html-widths: só a <img> com style muda (1)"   '[[ "$nh" == 1 ]] && grep -q "width=\"50.0%\"" "$FIX/img.html"'
pandoc -f html -t odt "${refodt[@]}" "$FIX/img.html" -o "$FIX/img.odt"
cp "$FIX/img.odt" "$FIX/img0.odt"
python3 "$PY" "$FIX/img.odt" >/dev/null
fr="$(python3 - "$FIX/img0.odt" "$FIX/img.odt" <<'PY'
import sys, zipfile, re
a, b = zipfile.ZipFile(sys.argv[1]), zipfile.ZipFile(sys.argv[2])
xa, xb = a.read('content.xml').decode(), b.read('content.xml').decode()
pt = lambda v: float(re.sub('pt$', '', v)) if v.endswith('pt') else float('nan')
for m in re.finditer(r'<draw:frame\b([^>]*)>\s*<draw:(image|object)\b', xb):
    at = dict(re.findall(r'([\w:-]+)="([^"]*)"', m.group(1)))
    print(at.get('draw:name'), m.group(2), '%.2f' % pt(at.get('svg:width', '')), '%.2f' % pt(at.get('svg:height', '')),
          at.get('style:rel-width', '-'))
obj = lambda x: re.findall(r'<draw:frame\b[^>]*>\s*<draw:object\b[^>]*>', x)
print('formula-intocada', obj(xa) == obj(xb) and len(obj(xa)) > 0)
PY
)"
DBG="$fr"
fdim(){ awk -v n="$1" '$1==n{print $3, $4, $5}' <<<"$fr"; }
ck "todo quadro de imagem ≤ largura útil e ≤ altura máx." \
  '[[ -z "$(awk -v W=$MAXW -v H=$MAXH '"'"'$2=="image" && ($3>W+0.05 || $4>H+0.05)'"'"' <<<"$fr")" ]]'
ck "1561×1561: quadrado na largura útil"             '[[ "$(fdim img1)" == "453.54 453.54 -" ]]'
ck "700×3000: altura máx., proporção 3000/700"        'awk -v H=$MAXH '"'"'{exit !($2==H && ($2/$1-3000/700)^2 < 0.0001)}'"'"' <<<"$(fdim img2)"'
ck "300×200: tamanho da WEB (225×150 pt)"              '[[ "$(fdim img3)" == "225.00 150.00 -" ]]'
ck "2481×3508 a 300 dpi: cabe e mantém a proporção"   'awk -v H=$MAXH '"'"'{exit !($2<=H+0.05 && ($2/$1-3508/2481)^2 < 0.0001)}'"'"' <<<"$(fdim img4)"'
ck "SVG 2000×600: na largura útil, proporção 0,3"     'awk -v W=$MAXW '"'"'{exit !($1==W && ($2/$1-0.3)^2 < 0.0001)}'"'"' <<<"$(fdim img5)"'
ck "{width=50%} do autor: rel-width 50%"              '[[ "$(fdim img6 | cut -d" " -f3)" == "50.0%" ]]'
ck "figura com legenda também cabe"                   '[[ "$(fdim img7)" == "453.54 453.54 -" ]]'
# (o pandoc arredonda o DPI do pHYs: dá ~144,5 pt; o da web seria 450 pt — não pode crescer)
ck "600×300 a 300 dpi: fica no tamanho do DPI (~144 pt)" 'awk '"'"'{exit !($1>143 && $1<146 && ($2*2-$1)^2 < 0.01)}'"'"' <<<"$(fdim img8)"'
ck "quadro de fórmula intocado"                       'grep -qx "formula-intocada True" <<<"$fr"'
si="$(sha "$FIX/img.odt")"; python3 "$PY" "$FIX/img.odt" >/dev/null
ck "imagens: 2ª passada não muda nada"               '[[ "$(sha "$FIX/img.odt")" == "$si" ]]'
python3 "$PY" --html-widths "$FIX/img.html" >/dev/null; hh="$(python3 "$PY" --html-widths "$FIX/img.html")"
ck "--html-widths idempotente"                         '[[ "$hh" == 0 ]]'

echo "== parênteses, colchetes e sintaxe (o que o LibreOffice recebe: --fix) =="
# o LibreOffice lê `stretchy="true"` como `left ( … right )`, que estica até a altura do conteúdo;
# `[ … )` é erro de sintaxe no StarMath; `#`/`&`/`_` num <mi> são comandos dele
fx(){ mml "$1" | python3 "$PY" --fix 2>&1; }
nost(){ grep -q '<math' <<<"$1" && ! grep -q 'stretchy="true"' <<<"$1"; }   # saída de erro não conta
X="$(fx '(x_1, y_1)')";                        DBG="$X"; ck "(x_1, y_1): parênteses sem esticar"       'nost "$X"'
X="$(fx 'O(n \log n)')";                       DBG="$X"; ck "O(n \\log n): parênteses sem esticar"     'nost "$X"'
X="$(fx '|a_i| \le 10^9')";                    DBG="$X"; ck "|a_i|: barras sem esticar"                'nost "$X" && [[ "$(grep -o "fence=\"true\"" <<<"$X" | wc -l)" == 2 ]]'
X="$(fx '\left( \frac{a}{b} \right)')";        DBG="$X"; ck "\\left( fração \\right): estica"          '[[ "$(grep -o "stretchy=\"true\"" <<<"$X" | wc -l)" == 2 ]]'
X="$(fx '\binom{n}{2}')";                      DBG="$X"; ck "\\binom: estica"                          'grep -q "stretchy=\"true\"" <<<"$X"'
X="$(fx '\begin{vmatrix}a&b\\c&d\end{vmatrix}')"; DBG="$X"; ck "vmatrix: barras esticam em volta da matriz" '[[ "$(grep -oE "<mo[^>]*(fence=\"true\"[^>]*stretchy=\"true\"|stretchy=\"true\"[^>]*fence=\"true\")" <<<"$X" | wc -l)" == 2 ]]'
X="$(fx '[l, r)')";                            DBG="$X"; ck "[l, r): colchete e parêntese literais"    'grep -qF "<mtext>[</mtext>" <<<"$X" && grep -qF "<mtext>)</mtext>" <<<"$X"'
X="$(fx 'x \in [0, 1)')";                      DBG="$X"; ck "x \\in [0, 1): literais no meio da linha" 'grep -qF "<mtext>[</mtext>" <<<"$X" && grep -qF "<mtext>)</mtext>" <<<"$X"'
X="$(fx '\left[ \frac{a}{b} \right)')";        DBG="$X"; ck "\\left[ fração \\right): par trocado alto estica" '! grep -q "<mtext>" <<<"$X" && [[ "$(grep -o "stretchy=\"true\"" <<<"$X" | wc -l)" == 2 ]]'
X="$(fx 'f(n) = \begin{cases} 1 & n = 0 \\ 2 & n > 0 \end{cases}')"; DBG="$X"
ck "cases: fecho vazio depois da tabela (right none)" 'grep -qE "</mtable><mo [^>]*form=\"postfix\"[^>]*(/>|></mo>)" <<<"$X"'
X="$(fx 'a \# b + c \& d + x\_i')";            DBG="$X"; ck "\\# \\& \\_ viram texto"                 'grep -qF "<mtext>#</mtext>" <<<"$X" && grep -qF "<mtext>&amp;</mtext>" <<<"$X" && grep -qF "<mtext>_</mtext>" <<<"$X"'
X="$(fx '\text{se "a" vale}')";                DBG="$X"; ck "aspas retas no \\text viram curvas"      'grep -qF "“a”" <<<"$X"'
# relação na ponta do grupo: o StarMath exige operando dos dois lados (`$\le 10^9$` era ¿) — ganha
# o grupo vazio `{}`; sinal/fatorial, que podem abrir/fechar, não
X="$(fx '\le 10^9')";                          DBG="$X"; ck "\\le 10^9: grupo vazio antes do ≤"       'grep -qF "<mrow /><mo>≤</mo>" <<<"$X"'
X="$(fx 'x =')";                               DBG="$X"; ck "x =: grupo vazio depois do ="            'grep -qF "<mo>=</mo><mrow />" <<<"$X"'
X="$(fx '\le')";                               DBG="$X"; ck "\\le sozinho: um grupo só na raiz"       'grep -qF "<mrow><mrow /><mo>≤</mo><mrow /></mrow>" <<<"$X"'
X="$(fx '\begin{aligned} S &= a \\ &= 10 \end{aligned}')"; DBG="$X"; ck "aligned: a coluna que começa com = ganha o vazio" '[[ "$(grep -o "<mrow /><mo>=</mo>" <<<"$X" | wc -l)" == 2 ]]'
X="$(fx '-x + n!')";                           DBG="$X"; ck "-x e n!: sem grupo vazio"               'grep -q "<math" <<<"$X" && ! grep -qF "<mrow />" <<<"$X"'
ALL="$(mml '(x_1, y_1) + [l, r) + |a| + \binom{n}{2} + \begin{cases} 1 & n = 0 \end{cases} + a \# b + \le')"
X1="$(python3 "$PY" --fix <<<"$ALL")"; X2="$(python3 "$PY" --fix <<<"$X1")"; DBG="$X1 ≠ $X2"
ck "2ª passada não muda nada"                      'grep -q "<mtext>\[</mtext>" <<<"$X1" && [[ "$X1" == "$X2" ]]'

echo "== bloco center (odt-center.lua): o '::: center' do enunciado centralizado também no PDF =="
# no site o `.center` do ui.css centraliza; na rota do caderno o pandoc descartava a classe do bloco
LUA="$ROOT/api/v1/lib/odt-center.lua"
python3 - "$FIX/ctr.html" <<'PY'
import sys, zlib, struct, base64
raw = b''.join(b'\x00' + b'\x80\x40\x40' * 40 for _ in range(20))
ch = lambda t, d: struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
png = b'\x89PNG\r\n\x1a\n' + ch(b'IHDR', struct.pack('>IIBBBBB', 40, 20, 8, 2, 0, 0, 0)) + ch(b'IDAT', zlib.compress(raw)) + ch(b'IEND', b'')
u = 'data:image/png;base64,' + base64.b64encode(png).decode()
open(sys.argv[1], 'w').write(
    '<html><body><p>antes</p>'
    '<div class="center"><figure><img src="%s" alt="leg"><figcaption>Legenda dentro</figcaption></figure>'
    '<p>texto dentro</p></div>'
    '<figure><img src="%s" alt="fora"><figcaption>Legenda fora</figcaption></figure></body></html>' % (u, u))
PY
pandoc -f html -t odt "${refodt[@]}" --lua-filter="$LUA" "$FIX/ctr.html" -o "$FIX/ctr.odt" 2>/dev/null
cst="$(python3 - "$FIX/ctr.odt" <<'PY'
import sys, zipfile, re
x = zipfile.ZipFile(sys.argv[1]).read('content.xml').decode()
paras = re.findall(r'<text:p text:style-name="([^"]+)"[^>]*>(.*?)</text:p>', x, re.S)
tag = lambda body: 'img' if 'draw:image' in body else re.sub(r'<[^>]+>', '', body).strip()
for st, body in paras: print(st + '|' + tag(body))
PY
)"
DBG="$cst"
ck "dentro do bloco: imagem, legenda e texto no estilo Center" '[[ "$(grep -c "^Center|" <<<"$cst")" == 3 ]] && grep -qx "Center|Legenda dentro" <<<"$cst" && grep -qx "Center|texto dentro" <<<"$cst"'
ck "fora do bloco: a figura fica como era"            'grep -q "^FigureWithCaption|img" <<<"$cst" && grep -qx "FigureCaption|Legenda fora" <<<"$cst"'
ck "reference-doc: o estilo Center é centralizado"    'unzip -p "$ROOT/etc/caderno-reference.odt" styles.xml | tr -d "\n" | grep -qE "style:name=\"Center\"[^>]*>[^<]*<style:paragraph-properties[^>]*fo:text-align=\"center\""'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
