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
insp="$(python3 - "$FIX/a0.odt" "$FIX/a.odt" <<'PY'
import sys, zipfile, re
a, b = zipfile.ZipFile(sys.argv[1]), zipfile.ZipFile(sys.argv[2])
ib = b.infolist()
print('first', ib[0].filename, ib[0].compress_type == zipfile.ZIP_STORED)
print('names', sorted(a.namelist()) == sorted(b.namelist()))
changed = [n for n in a.namelist() if a.read(n) != b.read(n)]
print('changed', all(re.match(r'^[^/]+/content\.xml$', n) for n in changed), len(changed))
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
ck "só mudou content.xml de fórmula (3)"             'grep -qx "changed True 3" <<<"$insp"'
ck "nenhuma barra de par sem fence"                  'grep -qx "bad 0" <<<"$insp"'
ck "a do meio virou ∣"                               'grep -qx "mid 1" <<<"$insp"'
ck "zip íntegro"                                     'grep -qx "test True" <<<"$insp"'
s1="$(sha "$FIX/a.odt")"; n2="$(python3 "$PY" "$FIX/a.odt")"
DBG="n2=$n2"
ck "idempotente: 2ª passada não muda nada"           '[[ "$n2" == 0 && "$(sha "$FIX/a.odt")" == "$s1" ]]'
n3="$(python3 "$PY" "$FIX/b.odt")"
DBG="n3=$n3"
ck "documento sem barra fica byte a byte"            '[[ "$n3" == 0 && "$(sha "$FIX/b.odt")" == "$(sha "$FIX/b0.odt")" ]]'
head -c 3000 "$FIX/a0.odt" > "$FIX/q.odt"; sq="$(sha "$FIX/q.odt")"
python3 "$PY" "$FIX/q.odt" >/dev/null 2>&1; rcq=$?
DBG="rc=$rcq"
ck "ODT quebrado: saída ≠ 0 e arquivo intacto"      '[[ $rcq != 0 && "$(sha "$FIX/q.odt")" == "$sq" ]]'
ck "…sem temporário largado no diretório"            '[[ -z "$(find "$FIX" -name "tmp*.odt")" ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
