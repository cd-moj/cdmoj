#!/usr/bin/env python3
# odt-math-bars.py — conserta as BARRAS VERTICAIS das fórmulas de um ODT gerado pelo pandoc,
# para o LibreOffice Math não desenhar o "¿" vermelho em volta delas no PDF.
#
# Por que existe (relato do Arthur Botelho, 24/09/2026 — "a barra vertical fica com um ¿ em
# volta; a gente tem que escapar?"): o caderno e o editorial da prova vão por
# `pandoc -f html -t odt` → `soffice --convert-to pdf` (lib/contest-docs.sh, _doc_html2pdf_odt).
# O pandoc (texmath) não diz qual barra abre e qual fecha (o 3.7 marca TODO `|` como
# `<mo stretchy="false" form="prefix">|</mo>`, inclusive o que FECHA) e o importador de MathML do
# LibreOffice não consegue montar isso: desenha o erro de sintaxe (¿). O enunciado está certo (o
# navegador desenha o MathML) e não há contorno do lado do autor: `\lvert…\rvert`, `\left|…\right|`,
# `\vert` e `\|` quebram igual.
# O que o LibreOffice aceita (testado variante por variante): a barra que ABRE como
# `<mo fence="true" form="prefix">`, a que FECHA como `<mo fence="true" form="postfix">`, EM PAR;
# a do MEIO (`a|b`, `P(A|B)`) como `<mo>∣</mo>` (U+2223, o `\mid`, que já funcionava).
#
# O papel de cada barra sai da vizinhança, numa linha ACHATADA (mrow/mstyle entram em linha, e a
# BASE de msub/msup também — é o que faz o `|` de `|x|^2` fechar o par), com uma pilha por tipo
# (simples | dupla):
#   stretchy + form=postfix (`\right|`) ......................... fecha (o `form` do texmath só
#     vale aí: `\bigr|` também sai prefix, e o `|` comum sai SEMPRE prefix)
#   sem operando antes, com operando depois ..................... abre
#   com operando antes, sem operando depois ..................... fecha
#   operando dos dois lados: fecha se há par aberto; senão abre se ela e as seguintes do mesmo
#     tipo somam um número PAR (`|x| \text{ e } |y|`), senão é a do meio (`a|b`)
#   par que sobra aberto / fecho sem abertura ................... solta (`<mtext>|</mtext>`)
#   a do meio sem vizinho dos dois lados no grupo REAL ........... solta (o LibreOffice monta cada
#     <mrow> à parte: `∣` na borda do grupo é operador sem operando)
# Índices, frações, raízes e células são linhas próprias (recursão). Toda barra é candidata
# (`|`, `∣`, `∥`, `‖`, em <mo> ou <mi>, com ou sem atributo); o `\mid` do autor sai do meio de novo.
# ⚠ O MathML MUDA com a versão do pandoc — e a IMAGEM não tem o pandoc do dev: o 3.7 (dev) marca todo
# `|` com `stretchy="false" form="prefix"`; o 3.1.11 (Debian trixie, produção) já emite `|x|` como
# par esticável, o `\|` como `<mo>∥</mo>` nu, o `vmatrix` como `<mi>∣</mi>…<mo>∣</mo>` e agrupa
# `x | |x|` como `x <mrow>| |</mrow>`. O LibreOffice também muda (26.2 × 25.2). Por isso o smoke
# e o render-docs.sh rodam DENTRO do container depois do deploy — o 1º deploy deste conserto
# passou no dev e deixou ¿ na produção (barra dupla e vmatrix).
#
# De carona, o mesmo defeito de versão em NOME DE FUNÇÃO (`fix_names`): no pandoc 3.1 da imagem
# `\log` vem como `<mo>log</mo>` e o LibreOffice 25.2 desenha só "l" — vira `<mi>log</mi>`.
#
# E a TIPOGRAFIA da fórmula (`fix_settings`; relato de 24/09/2026: "o texto entre $ sai com outro
# tamanho"): o pandoc grava cada fórmula como objeto do LibreOffice Math com um `settings.xml` que
# só diz `IsTextMode`, e o Math desenha com os DEFAULTS dele — 12pt em Liberation Serif, que a
# imagem não tem: caía no DejaVu Serif (largo, x-height alto) no meio do Latin Modern 11pt do
# corpo. O objeto NÃO herda nada do parágrafo nem do reference-doc; por isso cada settings.xml de
# fórmula recebe o tamanho e a família do CORPO, lidos da default-style de parágrafo do styles.xml
# do próprio ODT — a do `etc/caderno-reference.odt` (mudou o corpo lá, a fórmula acompanha) — e
# índices/limites a 70% (o \scriptsize do LaTeX a 11pt é 8pt; os 60% do Math deixavam o
# `\sum_{i=1}^{n}` ilegível). ⚠ ORDEM: `FontName…` recria a fonte SEM itálico — o
# `FontVariablesIsItalic` tem de vir DEPOIS (antes dele o `n` saía em pé). A FAMÍLIA é o CMU Serif
# (fonts-cmu, MATH_FONTS) quando instalado: o Latin Modern Roman não tem grego, e o `\alpha` caía
# no DejaVu Serif; sem o CMU, fica a do corpo.
#
# COMO O LIBREOFFICE LÊ O MATHML (o que explica todo o resto): ele NÃO desenha o MathML — traduz
# para StarMath (a linguagem de fórmula dele) e LÊ ESSE TEXTO de novo. Para ver o que ele entendeu,
# salve o ODT pelo soffice (`--convert-to odt`) e leia o `<annotation encoding="StarMath 5.0">` de
# cada fórmula. Daí:
#   PARÊNTESES (`fix_brackets`): par com `stretchy="true"` vira `left ( … right )`, que estica até
#     a altura do conteúdo, e o pandoc 3.1 marca assim até o `(` COMUM do TeX — `(x_1, y_1)` saía
#     com parênteses maiores que o texto. Só estica em volta de conteúdo ALTO (fração, `\binom`,
#     matriz, ∑); as BARRAS seguem a mesma regra (`rewrite`). Par TROCADO (`[l, r)`) é erro de
#     sintaxe no StarMath (¿): vira caractere literal. O `cases` (abre sem fechar) ganha o fecho
#     vazio — sem ele o LibreOffice inventava a chave espelhada à direita;
#   SINTAXE (`fix_syntax`): `#`, `&`, `_`, `^`, `%`… num <mi>/<mo> são comandos do StarMath (`a \# b`
#     saía ¿ ¿, `a \& b` virava a ∧ b): viram texto;
#   OPERANDO (`fix_operands`): relação/binário precisa de operando dos dois lados — `$\le 10^9$`,
#     `$= 0$` e a coluna `&= …` do `aligned` saíam ¿; ganham o grupo vazio `{}` (sem largura).
# Sem conserto por aqui: ACENTOS (`\bar`, `\hat`, `\vec`, `\overline`…) — o importador do 25.2 monta
# o acento mas o escreve SEM NOME no StarMath, e ele some; como `csup` (o que sai hoje) o sinal fica
# alto e pequeno. O PRIMO (`f'`) sai do DejaVu Sans (nem o CMU Serif nem o Latin Modern têm o `′`).
#
# E as IMAGENS (`fix_images` + `--html-widths`; pedido de 24/09/2026: "não podem ficar gigantes nem
# sair da página"): nunca maior que o tamanho da página WEB (px × 0,75 pt) nem que o do DPI do
# arquivo, com teto na área útil da página mestra do reference-doc; a largura pedida pelo autor volta
# a valer. Ver a seção IMAGENS. É por isso que este
# script é o passo de pós-processamento do ODT do caderno, não só das barras (o nome ficou).
#
# Uso: odt-math-bars.py <arquivo.odt>   — reescreve NO LUGAR (tmp + os.replace), só as fórmulas
#        que mudam; mimetype PRIMEIRO e sem compressão (senão o LibreOffice recusa calado). Imprime
#        quantas fórmulas tiveram o MathML reescrito (a tipografia do settings.xml não conta). Erro =
#        ODT intacto e saída ≠ 0 (quem chama segue: no pior caso o PDF sai como antes). Idempotente.
#      odt-math-bars.py --roles        — TESTE: lê HTML/MathML no stdin e imprime, por <math>, o
#        papel de cada barra (O abre, C fecha, M meio, L solta; prefixo D = dupla).
#      odt-math-bars.py --html-widths <arquivo.html> — ANTES do pandoc: `style="width:…"` de <img> vira
#        atributo (no lugar, atômico); imprime quantas <img> mudaram.
#      odt-math-bars.py --fix          — TESTE: lê HTML/MathML no stdin e imprime, uma por linha,
#        cada <math> como sai daqui (o que o LibreOffice vai receber).
# Teste: server/test/smoke-odt-math-bars.sh; a cadeia real: server/test/render-docs.sh.
import os
import re
import struct
import subprocess
import sys
import tempfile
import zipfile
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

M = 'http://www.w3.org/1998/Math/MathML'
ET.register_namespace('', M)
NS_STYLE = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0'
NS_FO = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0'
NS_SVG = 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0'
BODY_FALLBACK = ('Latin Modern Roman', 11)   # o corpo do etc/caderno-reference.odt
# fonte das FÓRMULAS: o Latin Modern Roman do corpo NÃO tem grego (o `\alpha` caía no DejaVu Serif);
# o CMU Serif (fonts-cmu) é o mesmo desenho COM grego. A 1ª instalada vence; nenhuma = a do corpo.
MATH_FONTS = ('CMU Serif',)
SCRIPT_PCT = 70                              # índices e limites, % do corpo

BARS = {'|': 's', '∣': 's', '∥': 'd', '‖': 'd'}   # | ∣ ∥ ‖
OPENB = set('([{⟨⌊⌈')                             # ( [ { ⟨ ⌊ ⌈
CLOSEB = set(')]}⟩⌋⌉')
MATCH = dict(zip('([{⟨⌊⌈', ')]}⟩⌋⌉'))
POSTOP = set('′″‴!')                                # ′ ″ ‴ !
# operador que o texmath às vezes emite como <mi> (o `-` depois de uma barra sai `<mi>−</mi>`)
OPS = set('+-−=<>≤≥≠±∓×÷⋅·*/,;:'
          '∈∉⊂⊆∪∩∧∨¬→←↔⇒⇔'
          '∑∏∫…')
# conteúdo ALTO: o único caso em que o par de delimitadores estica (fração e \binom, matriz/cases,
# operador grande — o ∑ com limites). Ver fix_brackets.
TALL = {'mfrac', 'mtable'}
BIGOPS = set('∑∏∐∫∬∭∮⋃⋂⨁⨂')
SCRIPTS = {'msub', 'msup', 'msubsup', 'munder', 'mover', 'munderover', 'mmultiscripts'}
GROUP = {'mrow', 'mstyle', 'mpadded', 'mphantom'}
LEAF = {'mi', 'mn', 'mo', 'mtext', 'mspace', 'ms'}
ATTRS = ('form', 'stretchy', 'fence')


def tag(e):
    return e.tag.split('}', 1)[-1]


def text(e):
    return (e.text or '').strip()


def is_bar(e):
    # TODA barra é candidata, com ou sem atributo, em <mo> ou <mi>: o pandoc da imagem (3.1) emite o
    # `\|` como `<mo>∥</mo>` nu e o `vmatrix` como `<mi>∣</mi> … <mo>∣</mo>`, e o LibreOffice 25.2
    # desenha ¿ nos dois. O `\mid` do autor (`<mo>∣</mo>` entre operandos) sai do meio de novo.
    return tag(e) in ('mo', 'mi') and text(e) in BARS


def flatten(row, seq, rows):
    """seq = tokens da linha em ordem; rows = filhos a processar como linhas próprias."""
    for c in list(row):
        t = tag(c)
        if t in GROUP:
            flatten(c, seq, rows)
        elif t in SCRIPTS:
            kids = list(c)
            if not kids:
                continue
            if tag(kids[0]) in GROUP:
                flatten(kids[0], seq, rows)
            else:
                seq.append(kids[0])
                rows.append(kids[0])
            rows.extend(kids[1:])
        else:
            seq.append(c)
            rows.append(c)


def kind(e, role):
    if e in role:
        return role[e]
    t, x = tag(e), text(e)
    if t == 'mspace':
        return 'skip'
    if t == 'mi' and x in OPS:
        return 'op'
    if t == 'mo':
        if x in OPENB:
            return 'openb'
        if x in CLOSEB:
            return 'closeb'
        if x in POSTOP:
            return 'postop'
        return 'op'
    return 'operand'


def is_tall(e):
    return any(tag(d) in TALL or (tag(d) == 'mo' and text(d) in BIGOPS) for d in e.iter())


def process(row, role, tall):
    seq, rows = [], []
    flatten(row, seq, rows)
    toks = [e for e in seq if kind(e, {}) != 'skip']
    stack = {'s': [], 'd': []}
    pos = {}
    for i, e in enumerate(toks):
        if not is_bar(e):
            continue
        b = BARS[text(e)]
        st = e.get('stretchy') == 'true'
        form = e.get('form')
        P = toks[i - 1] if i > 0 else None
        N = toks[i + 1] if i + 1 < len(toks) else None
        prev = P is not None and kind(P, role) in ('operand', 'closeb', 'postop', 'close')
        nxt = N is not None and (is_bar(N) or kind(N, role) in ('operand', 'openb'))
        if st and form == 'postfix':
            r = 'close'
        elif not prev and nxt:
            r = 'open'
        elif prev and not nxt:
            r = 'close'
        elif prev and nxt:
            if stack[b]:
                r = 'close'
            else:
                rest = sum(1 for f in toks[i:] if is_bar(f) and BARS[text(f)] == b)
                r = 'open' if rest % 2 == 0 else 'infix'
        else:
            r = 'lone'
        if r == 'open':
            stack[b].append(e)
            pos[e] = i
        elif r == 'close':
            if stack[b]:
                o = stack[b].pop()
                tall[o] = tall[e] = any(is_tall(f) for f in toks[pos[o] + 1:i])
            else:
                r = 'lone'
        role[e] = r
    for b in stack:
        for e in stack[b]:
            role[e] = 'lone'
    for c in rows:   # sub-linhas (índices, frações, raízes, células): independentes
        if tag(c) not in LEAF:
            process(c, role, tall)


ROWLIKE = GROUP | {'math', 'mtd', 'msqrt', 'menclose', 'semantics'}


def roles_of(root, tall=None):
    """papel de cada barra; `tall` (se dado) recebe, para cada barra de PAR, se o par é alto."""
    role = {}
    process(root, role, {} if tall is None else tall)
    # a do MEIO precisa de vizinho dos DOIS lados no grupo REAL (o LibreOffice monta cada <mrow> à
    # parte): o pandoc 3.1 põe `{x | |x|` como `x <mrow>| |</mrow>` e um `∣` na borda do grupo vira
    # operador sem operando (¿). Sem os dois vizinhos ela sai SOLTA (texto), que sempre monta.
    parent = {c: p for p in root.iter() for c in p}
    for e, r in role.items():
        if r != 'infix':
            continue
        p = parent.get(e)
        sib = [c for c in p if tag(c) != 'mspace'] if p is not None else []
        if p is None or tag(p) not in ROWLIKE or sib[0] is e or sib[-1] is e:
            role[e] = 'lone'
    return role


def rewrite(root, role, tall):
    for e, r in role.items():
        b = BARS[text(e)]
        st = 'true' if tall.get(e) else 'false'   # estica só em volta de conteúdo alto (fix_brackets)
        for a in ATTRS:
            e.attrib.pop(a, None)
        if r != 'lone':
            e.tag = '{%s}mo' % M          # o `<mi>∣</mi>` do vmatrix do pandoc 3.1 vira operador
        if r in ('open', 'close'):
            e.text = '|' if b == 's' else '‖'
            e.set('fence', 'true')
            e.set('form', 'prefix' if r == 'open' else 'postfix')
            e.set('stretchy', st)
        elif r == 'infix':
            e.text = '∣' if b == 's' else '∥'
        else:
            e.tag = '{%s}mtext' % M
            e.text = '|' if b == 's' else '‖'
            e.attrib.clear()


FNAME = re.compile(r'^[A-Za-z]{2,}$')


def fix_names(root):
    """NOME DE FUNÇÃO (`\\log`, `\\sin`, `\\max`, `\\lim`…): o pandoc 3.1 da imagem o emite como
    `<mo>log</mo>` e o LibreOffice 25.2 desenha só a 1ª LETRA — `O(n \\log n)` saía "O(n l n)" no
    caderno. Como `<mi>` (o que o pandoc 3.7 do dev já emite) sai inteiro. Devolve quantos trocou."""
    n = 0
    for e in root.iter('{%s}mo' % M):
        if FNAME.match(text(e)):
            e.tag = '{%s}mi' % M
            n += 1
    return n


# caracteres que são SINTAXE no StarMath (o LibreOffice reescreve a fórmula em StarMath e a lê de
# novo): `#` separa colunas, `&` é o "e" lógico, `_`/`^` são índice/expoente, `%` abre nome de
# símbolo, `~`/`` ` `` são espaços, `\` escapa. Num <mi>/<mo>/<mn> saíam ¿ (`\#`, `\underline`) ou,
# pior, OUTRA COISA calada (`a \& b` virava a ∧ b; `x\_i`, x com índice i).
SYNTAX = set('#&_^%~`\\')


def fix_syntax(root):
    """caractere de sintaxe do StarMath vira TEXTO (`<mtext>`, que o LibreOffice põe entre aspas);
    aspa reta DENTRO do texto fecharia essas aspas — vira curva, como o TeX a desenha."""
    n = 0
    for e in root.iter():
        t, s = tag(e), e.text or ''
        if t in ('mi', 'mo', 'mn') and any(ch in SYNTAX for ch in s):
            e.tag = '{%s}mtext' % M
            e.attrib.clear()
            n += 1
        elif t == 'mtext' and '"' in s:
            parts = s.split('"')
            e.text = parts[0] + ''.join(('“' if i % 2 == 0 else '”') + p for i, p in enumerate(parts[1:]))
            n += 1
    return n


# operador na PONTA de um grupo: no StarMath relação/binário precisa de operando dos DOIS lados —
# `$\le 10^9$` ("valores $\le 10^9$"), `$= 0$`, `$x =$` e a 2ª coluna do `aligned` (`&= …`) saíam ¿.
# Quem pode abrir (sinal, ¬, ∀, ∑…) ou fechar (`!`, `′`…) uma expressão fica como está.
CAN_START = set('+-−±∓¬∀∃∄∂∇√') | BIGOPS | OPENB
CAN_END = set('!′″‴%°') | CLOSEB


def fix_operands(root):
    """relação/binário sem operando na ponta do grupo ganha o grupo VAZIO do StarMath (`{} <= 10^9`,
    sem largura). Roda por ÚLTIMO: as outras passadas olham o 1º/último filho do grupo."""
    def bare(e, ok):
        return tag(e) == 'mo' and text(e) and text(e) not in ok and text(e) not in BARS and e.get('fence') != 'true'
    n = 0
    for row in list(root.iter()):
        if tag(row) not in ROWLIKE:
            continue
        kids = [c for c in row if tag(c) not in ('mspace', 'annotation', 'annotation-xml')]
        if not kids:
            continue
        o, c = kids[0], kids[-1]
        pre, post = bare(o, CAN_START), bare(c, CAN_END)
        if not (pre or post):
            continue
        if tag(row) in ('math', 'semantics'):
            # na RAIZ cada filho vira uma LINHA do StarMath (`{ } newline <= newline { }`, ¿):
            # embrulha tudo num grupo só antes
            w = ET.Element('{%s}mrow' % M)
            row.insert(list(row).index(o), w)
            for k in kids:
                row.remove(k)
                w.append(k)
            row = w
        if pre:
            row.insert(list(row).index(o), ET.Element('{%s}mrow' % M))
            n += 1
        if post:
            row.insert(list(row).index(c) + 1, ET.Element('{%s}mrow' % M))
            n += 1
    return n


def _opener(e):
    """`(`/`[`/`{`…, ou o `<mo>` VAZIO de prefixo (o `\\left.` do TeX)."""
    return tag(e) == 'mo' and e.get('form') != 'postfix' and (
        text(e) in OPENB or (text(e) == '' and e.get('form') == 'prefix'))


def _closer(e):
    return tag(e) == 'mo' and e.get('form') != 'prefix' and (
        text(e) in CLOSEB or (text(e) == '' and e.get('form') == 'postfix'))


def _literal(e):
    e.tag = '{%s}mtext' % M          # o LibreOffice lê `"["`: o caractere, sem agrupar
    e.attrib.clear()


def fix_brackets(root):
    """PARÊNTESES E COLCHETES. O LibreOffice monta cada grupo (`<mrow>`) como um grupo do StarMath,
    onde `( … )` e `[ … ]` só existem EM PAR do mesmo tipo e `left … right` estica até a altura do
    conteúdo. Os delimitadores de cada grupo são casados numa pilha:
      par do mesmo tipo ..... o pandoc 3.1 da imagem emite o `(` COMUM do TeX igual ao `\\left(`
        (`stretchy="true"`), e `(x_1, y_1)`/`O(n \\log n)` saíam com parênteses maiores que o texto.
        No TeX `(` comum nunca estica, mas no MathML a diferença se perde: decide o CONTEÚDO — só
        estica em volta de fração (e `\\binom`), matriz ou operador grande (is_tall). As BARRAS
        seguem a mesma regra no rewrite;
      par TROCADO ........... o intervalo `[l, r)`: `[ … )` é erro de sintaxe no StarMath (¿).
        Vira caractere literal; com conteúdo alto e ocupando o grupo, `left [ … right )` (vale);
      abre esticável sem fechar, no início do grupo ... o `cases` (`{` + tabela, sem fecho): o
        LibreOffice inventava `right lbrace` (a chave espelhada à direita). Ganha o fecho VAZIO
        (`right none`); o simétrico (`\\right)` sem `\\left`) ganha a abertura vazia;
      sem par .............. literal (antes, ¿).
    Devolve quantos delimitadores mudou."""
    n = 0
    for row in list(root.iter()):
        if tag(row) in LEAF:
            continue
        kids = [c for c in row if tag(c) != 'mspace']
        stack, lone = [], []
        for i, c in enumerate(kids):
            if _opener(c):
                stack.append(i)
                continue
            if not _closer(c):
                continue
            if not stack:
                lone.append(i)
                continue
            j = stack.pop()
            o = kids[j]
            whole = j == 0 and i == len(kids) - 1
            tall = any(is_tall(k) for k in kids[j + 1:i])
            if text(o) == '' or text(c) == '' or MATCH.get(text(o)) == text(c):
                if o.get('stretchy') == 'true' and not tall:
                    for e in (o, c):
                        if e.get('stretchy') != 'false':
                            e.set('stretchy', 'false')
                            n += 1
            elif whole and tall:
                for e in (o, c):
                    e.set('stretchy', 'true')
                n += 2
            else:
                _literal(o)
                _literal(c)
                n += 2
        lone += stack
        for i in lone:
            e = kids[i]
            if e.get('stretchy') == 'true' and _opener(e) and i == 0 and text(e):
                ET.SubElement(row, '{%s}mo' % M, stretchy='true', form='postfix')
            elif e.get('stretchy') == 'true' and _closer(e) and i == len(kids) - 1 and text(e):
                row.insert(0, ET.Element('{%s}mo' % M, stretchy='true', form='prefix'))
            elif text(e):
                _literal(e)
            else:
                continue
            n += 1
    return n


def fix_formula(data):
    """bytes do content.xml de uma fórmula -> bytes novos, ou None se não muda nada."""
    try:
        root = ET.fromstring(data)
    except ET.ParseError:
        return None
    if root.tag != '{%s}math' % M:
        return None
    names = fix_names(root)          # ANTES dos papéis: `\log|x|` vê o nome como operando
    syntax = fix_syntax(root)
    brackets = fix_brackets(root)
    tall = {}
    role = roles_of(root, tall)
    rewrite(root, role, tall)
    operands = fix_operands(root)    # por ÚLTIMO (as outras olham o 1º/último filho do grupo)
    if not role and not names and not syntax and not brackets and not operands:
        return None
    out = ('<?xml version="1.0" encoding="UTF-8"?>' + ET.tostring(root, encoding='unicode')).encode('utf-8')
    return None if out == data else out


def is_math(data):
    try:
        return ET.fromstring(data).tag == '{%s}math' % M
    except ET.ParseError:
        return False


def body_font(zi):
    """(família, pt) do corpo: text-properties da default-style de parágrafo do styles.xml."""
    fam, pt = BODY_FALLBACK
    try:
        root = ET.fromstring(zi.read('styles.xml'))
    except (KeyError, ET.ParseError):
        return fam, pt
    faces = {f.get('{%s}name' % NS_STYLE): f.get('{%s}font-family' % NS_SVG)
             for f in root.iter('{%s}font-face' % NS_STYLE)}
    for d in root.iter('{%s}default-style' % NS_STYLE):
        if d.get('{%s}family' % NS_STYLE) != 'paragraph':
            continue
        tp = d.find('{%s}text-properties' % NS_STYLE)
        if tp is not None:
            f = faces.get(tp.get('{%s}font-name' % NS_STYLE))
            if f:
                fam = f.strip('\'"')
            m = re.fullmatch(r'([\d.]+)pt', tp.get('{%s}font-size' % NS_FO) or '')
            if m:
                pt = max(1, round(float(m.group(1))))
        break
    return fam, pt


def formula_family(body):
    """a 1ª de MATH_FONTS que o fontconfig tem COM grego (U+03B1); senão a família do corpo."""
    for f in MATH_FONTS:
        try:
            out = subprocess.run(['fc-list', '%s:charset=3b1' % f, 'family'],
                                 capture_output=True, text=True, timeout=20).stdout
        except (OSError, subprocess.SubprocessError):
            break
        if out.strip():
            return f
    return body


def settings_items(fam, pt):
    return [('BaseFontHeight', 'short', str(pt)),
            ('FontNameVariables', 'string', fam),
            ('FontVariablesIsItalic', 'boolean', 'true'),   # DEPOIS do nome (o nome zera o itálico)
            ('FontNameFunctions', 'string', fam),
            ('FontNameNumbers', 'string', fam),
            ('FontNameText', 'string', fam),
            ('FontNameSerif', 'string', fam),
            ('RelativeFontHeightIndices', 'short', str(SCRIPT_PCT)),
            ('RelativeFontHeightLimits', 'short', str(SCRIPT_PCT))]


def fix_settings(data, items):
    """settings.xml de uma fórmula com a tipografia do corpo. None = já estava assim, ou não tem
    o conjunto `ooo:configuration-settings` que o pandoc grava (fica como veio)."""
    s = data.decode('utf-8')
    names = '|'.join(n for n, _, _ in items)
    s2 = re.sub(r'<config:config-item config:name="(?:%s)"[^>]*>[^<]*</config:config-item>' % names, '', s)
    xml = ''.join('<config:config-item config:name="%s" config:type="%s">%s</config:config-item>'
                  % (n, t, escape(v)) for n, t, v in items)
    s2, k = re.subn(r'(<config:config-item-set config:name="ooo:configuration-settings">.*?)'
                    r'(</config:config-item-set>)', lambda m: m.group(1) + xml + m.group(2),
                    s2, count=1, flags=re.S)
    if not k or s2 == s:
        return None
    return s2.encode('utf-8')


# ---------- IMAGENS ------------------------------------------------------------------------------
# Tamanho natural = o MENOR entre o do pandoc (que usa o DPI gravado no arquivo e, sem DPI, 72 = 1 px/pt)
# e o da página WEB (pixel CSS = 1/96 pol = 0,75 pt): sem DPI a imagem fica do tamanho da web; com DPI de
# impressão (as da OBI, a 300 dpi) fica o que o autor pretendeu — nunca maior do que já saía. E nunca
# maior que a área útil: é o `img{max-width:100%}` da web, que a rota ODT não enxerga (ODT ignora CSS). Sem isto o pandoc punha PNG sem DPI a 1 px = 1 pt e o LibreOffice CORTAVA
# o que passava da página (1561 px → 1561 pt numa área útil de 453 pt; 13 das 72 imagens de pacote da
# produção passavam do A4). Largura pedida pelo autor (`{width=50%}` → `style="width:50.0%"`, que o
# leitor de HTML do pandoc ignora) volta como ATRIBUTO no passo `--html-widths`, antes do pandoc, e chega
# aqui como `style:rel-width`: fica relativa, só a altura é conferida.
UNIT_PT = {'pt': 1.0, 'in': 72.0, 'cm': 72 / 2.54, 'mm': 72 / 25.4, 'pc': 12.0, 'px': 0.75}
PAGE_FALLBACK = (21 / 2.54 * 72, 29.7 / 2.54 * 72, 2.5 / 2.54 * 72)   # A4, margens de 2,5 cm
IMG_HEIGHT_FRAC = 0.9          # altura máx. = 90% do corpo: cabe numa página com a linha de cima
IMG_FRAME = re.compile(r'<draw:frame\b([^>]*)>(\s*<draw:image\b[^>]*>)', re.S)


def to_pt(v):
    m = re.fullmatch(r'\s*(-?[\d.]+)\s*(pt|in|cm|mm|pc|px)?\s*', v or '')
    if not m:
        return None
    try:
        return float(m.group(1)) * UNIT_PT[m.group(2) or 'pt']
    except ValueError:
        return None


def text_box(zi):
    """(largura útil, altura máxima de imagem) em pt: a página mestra `Standard` do styles.xml, menos
    margens, cabeçalho e rodapé. Sem leitura: A4 com margens de 2,5 cm."""
    pw, ph, mg = PAGE_FALLBACK
    w, h = pw - 2 * mg, ph - 2 * mg
    try:
        root = ET.fromstring(zi.read('styles.xml'))
    except (KeyError, ET.ParseError):
        return w, h * IMG_HEIGHT_FRAC
    st = lambda k: '{%s}%s' % (NS_STYLE, k)
    fo = lambda k: '{%s}%s' % (NS_FO, k)
    masters = list(root.iter(st('master-page')))
    mp = next((m for m in masters if m.get(st('name')) == 'Standard'), masters[0] if masters else None)
    lay = None
    if mp is not None:
        lay = next((p for p in root.iter(st('page-layout'))
                    if p.get(st('name')) == mp.get(st('page-layout-name'))), None)
    if lay is None:
        return w, h * IMG_HEIGHT_FRAC
    pp = lay.find(st('page-layout-properties'))
    if pp is not None:
        g = lambda k, d: (to_pt(pp.get(fo(k))) if pp.get(fo(k)) else None) or d
        pw, ph = g('page-width', pw), g('page-height', ph)
        w = pw - (to_pt(pp.get(fo('margin-left'))) or 0) - (to_pt(pp.get(fo('margin-right'))) or 0)
        h = ph - (to_pt(pp.get(fo('margin-top'))) or 0) - (to_pt(pp.get(fo('margin-bottom'))) or 0)
    # cabeçalho/rodapé só ocupam o corpo quando a página mestra os TEM
    for part, gap in (('header', 'margin-bottom'), ('footer', 'margin-top')):
        if mp is None or mp.find(st(part)) is None:
            continue
        hf = lay.find(st(part + '-style'))
        hp = hf.find(st('header-footer-properties')) if hf is not None else None
        if hp is not None:
            h -= (to_pt(hp.get(fo('min-height'))) or 0) + (to_pt(hp.get(fo(gap))) or 0)
    return w, h * IMG_HEIGHT_FRAC


def img_px(b):
    """(largura, altura) em pixels pelo CABEÇALHO do arquivo (PNG, GIF, JPEG, WebP); None se não sabe."""
    try:
        if b[:8] == b'\x89PNG\r\n\x1a\n':
            return struct.unpack('>II', b[16:24])
        if b[:6] in (b'GIF87a', b'GIF89a'):
            return struct.unpack('<HH', b[6:10])
        if b[:2] == b'\xff\xd8':
            i = 2
            while i + 9 < len(b):
                if b[i] != 0xFF:
                    i += 1
                    continue
                mk = b[i + 1]
                if mk == 0xFF:                         # preenchimento entre marcadores
                    i += 1
                    continue
                if mk in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                    hh, ww = struct.unpack('>HH', b[i + 5:i + 9])
                    return ww, hh
                if mk in (0xD8, 0x01) or 0xD0 <= mk <= 0xD7:
                    i += 2
                    continue
                i += 2 + struct.unpack('>H', b[i + 2:i + 4])[0]
            return None
        if b[:4] == b'RIFF' and b[8:12] == b'WEBP':
            kind = b[12:16]
            if kind == b'VP8X':
                return (int.from_bytes(b[24:27], 'little') + 1, int.from_bytes(b[27:30], 'little') + 1)
            if kind == b'VP8L':
                v = int.from_bytes(b[21:25], 'little')
                return ((v & 0x3FFF) + 1, ((v >> 14) & 0x3FFF) + 1)
            if kind == b'VP8 ':
                return (int.from_bytes(b[26:28], 'little') & 0x3FFF, int.from_bytes(b[28:30], 'little') & 0x3FFF)
    except Exception:
        return None
    return None


def fix_images(zi, data, box):
    """content.xml principal -> bytes novos, ou None. Só a tag de ABERTURA de cada `draw:frame` que
    contém `draw:image` muda (regex, sem reescrever o XML — o ElementTree mexeria nos prefixos);
    fórmula é `draw:object` e fica de fora. Proporcional, nunca aumenta, idempotente."""
    maxw, maxh = box
    s = data.decode('utf-8')

    def attr(a, k):
        m = re.search(r'\b%s="([^"]*)"' % re.escape(k), a)
        return m.group(1) if m else None

    def setattr_(a, k, v):
        return re.sub(r'\b%s="[^"]*"' % re.escape(k), '%s="%s"' % (k, v), a)

    def one(m):
        a, img = m.group(1), m.group(2)
        w, h = to_pt(attr(a, 'svg:width')), to_pt(attr(a, 'svg:height'))
        if not w or not h:
            return m.group(0)
        rel = attr(a, 'style:rel-width')
        if rel and rel.endswith('%'):
            # largura do AUTOR, relativa à área útil: fica; só a altura é conferida
            try:
                pct = float(rel[:-1])
            except ValueError:
                return m.group(0)
            ew = maxw * pct / 100
            eh = ew * h / w
            if eh > maxh:
                pct = pct * maxh / eh
                ew, eh = maxw * pct / 100, maxh
            a2 = setattr_(a, 'style:rel-width', '%.1f%%' % pct)
            a2 = setattr_(setattr_(a2, 'svg:width', '%.2fpt' % ew), 'svg:height', '%.2fpt' % eh)
            return m.group(0) if a2 == a else '<draw:frame%s>%s' % (a2, img)
        href = re.search(r'xlink:href="([^"]+)"', img)
        nw, nh = w, h
        if href and not href.group(1).lower().endswith('.svg'):
            try:
                px = img_px(zi.read(href.group(1))[:1 << 20])
            except KeyError:
                px = None
            if px and px[0] > 0 and px[1] > 0:
                # o MENOR entre o do pandoc (DPI do arquivo; sem DPI ele usa 72 = 1 px/pt) e o da web
                # (px × 0,75 pt): sem DPI cai no tamanho da web; com DPI de impressão (OBI a 300 dpi)
                # fica o que o autor pretendeu. Nunca maior do que já saía.
                f = min(1.0, px[0] * 0.75 / w)
                nw, nh = w * f, h * f
        k = min(1.0, maxw / nw, maxh / nh)
        fw, fh = nw * k, nh * k
        if abs(fw - w) < 0.01 and abs(fh - h) < 0.01:
            return m.group(0)
        a2 = setattr_(setattr_(a, 'svg:width', '%.2fpt' % fw), 'svg:height', '%.2fpt' % fh)
        return '<draw:frame%s>%s' % (a2, img)

    s2 = IMG_FRAME.sub(one, s)
    return None if s2 == s else s2.encode('utf-8')


def html_widths(s):
    """`<img style="width:X%">` -> `<img width="X%">` (e height, px, cm…): o leitor de HTML do pandoc
    lê o ATRIBUTO e ignora o `style` — era assim que o `{width=50%}` do enunciado se perdia no PDF."""
    def one(m):
        t = m.group(0)
        st = re.search(r'\sstyle\s*=\s*"([^"]*)"', t)
        if not st:
            return t
        decl = {}
        for d in st.group(1).split(';'):
            if ':' in d:
                k, v = d.split(':', 1)
                decl[k.strip().lower()] = v.strip()
        add = []
        for prop in ('width', 'height'):
            v = decl.get(prop)
            if not v or re.search(r'\s%s\s*=' % prop, t):
                continue
            mv = re.fullmatch(r'([\d.]+)\s*(%|px|cm|mm|in|pt)?', v)
            if mv:
                unit = mv.group(2) or ''
                add.append('%s="%s%s"' % (prop, mv.group(1), '' if unit == 'px' else unit))
        if not add:
            return t
        end = '/>' if t.endswith('/>') else '>'
        return t[:-len(end)].rstrip() + ' ' + ' '.join(add) + ' ' + end
    return re.sub(r'<img\b[^>]*>', one, s, flags=re.I)


def fix_odt(path):
    with zipfile.ZipFile(path) as zi:
        infos = zi.infolist()
        names = set(zi.namelist())
        new = {}
        mathdirs = set()
        for info in infos:
            n = info.filename
            if n.endswith('/content.xml'):
                data = zi.read(n)
                if is_math(data):
                    mathdirs.add(n[:-len('content.xml')])
                out = fix_formula(data)
                if out is not None:
                    new[n] = out
        fixed = len(new)
        items = None
        for info in infos:
            n = info.filename
            if n.endswith('/settings.xml') and n[:-len('settings.xml')] in mathdirs:
                if items is None:
                    fam, pt = body_font(zi)
                    items = settings_items(formula_family(fam), pt)
                out = fix_settings(zi.read(n), items)
                if out is not None:
                    new[n] = out
        if 'content.xml' in names:                  # imagens do documento (não contam na saída)
            out = fix_images(zi, zi.read('content.xml'), text_box(zi))
            if out is not None:
                new['content.xml'] = out
        if not new:
            return 0
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(path)), suffix='.odt')
        os.close(fd)
        try:
            with zipfile.ZipFile(tmp, 'w') as zo:
                order = [i for i in infos if i.filename == 'mimetype'] + \
                        [i for i in infos if i.filename != 'mimetype']
                for info in order:
                    data = new.get(info.filename)
                    if data is None:
                        data = zi.read(info.filename)
                    zinfo = zipfile.ZipInfo(info.filename, date_time=info.date_time)
                    zinfo.external_attr = info.external_attr
                    zinfo.compress_type = zipfile.ZIP_STORED if info.filename == 'mimetype' \
                        else zipfile.ZIP_DEFLATED
                    zo.writestr(zinfo, data)
            os.replace(tmp, path)
        except BaseException:
            os.unlink(tmp)
            raise
    return fixed


def main(argv):
    if len(argv) == 2 and argv[1] == '--roles':
        code = {'open': 'O', 'close': 'C', 'infix': 'M', 'lone': 'L'}
        for m in re.findall(r'<math\b.*?</math>', sys.stdin.read(), flags=re.S):
            root = ET.fromstring(m)
            fix_names(root)
            fix_syntax(root)
            fix_brackets(root)
            role = roles_of(root)
            print(' '.join(('D' if BARS[text(e)] == 'd' else '') + code[role[e]]
                           for e in root.iter() if e in role))
        return 0
    if len(argv) == 3 and argv[1] == '--html-widths':
        # ANTES do pandoc: a largura do autor vira atributo (reescreve no lugar, atômico)
        p = argv[2]
        s = open(p, encoding='utf-8', errors='surrogateescape').read()
        s2 = html_widths(s)
        if s2 != s:
            fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(p)), suffix='.html')
            with os.fdopen(fd, 'w', encoding='utf-8', errors='surrogateescape') as f:
                f.write(s2)
            os.replace(tmp, p)
        imgs = lambda x: re.findall(r'<img\b[^>]*>', x, flags=re.I)
        print(sum(1 for a, b in zip(imgs(s), imgs(s2)) if a != b))   # quantas <img> mudaram
        return 0
    if len(argv) == 2 and argv[1] == '--fix':
        for m in re.findall(r'<math\b.*?</math>', sys.stdin.read(), flags=re.S):
            out = fix_formula(m.encode('utf-8'))
            print((out.decode('utf-8') if out else m).replace('\n', ' '))
        return 0
    if len(argv) != 2:
        print('uso: odt-math-bars.py <arquivo.odt> | --roles | --fix | --html-widths <arquivo.html>', file=sys.stderr)
        return 2
    print(fix_odt(argv[1]))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
