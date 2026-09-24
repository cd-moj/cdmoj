#!/usr/bin/env python3
# odt-math-bars.py — conserta as BARRAS VERTICAIS das fórmulas de um ODT gerado pelo pandoc,
# para o LibreOffice Math não desenhar o "¿" vermelho em volta delas no PDF.
#
# Por que existe (relato do Arthur Botelho, 24/09/2026 — "a barra vertical fica com um ¿ em
# volta; a gente tem que escapar?"): o caderno e o editorial da prova vão por
# `pandoc -f html -t odt` → `soffice --convert-to pdf` (lib/contest-docs.sh, _doc_html2pdf_odt).
# O pandoc (texmath) marca TODO `|` do MathML como `<mo stretchy="false" form="prefix">|</mo>`,
# inclusive o que FECHA; o importador de MathML do LibreOffice não consegue montar isso e
# desenha o erro de sintaxe (¿). O enunciado está certo (o navegador desenha o MathML) e não há
# contorno do lado do autor: `\lvert…\rvert`, `\left|…\right|`, `\vert` e `\|` quebram igual.
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
# Índices, frações, raízes e células são linhas próprias (recursão).
#
# Uso: odt-math-bars.py <arquivo.odt>   — reescreve NO LUGAR (tmp + os.replace), só as fórmulas
#        que mudam; mimetype PRIMEIRO e sem compressão (senão o LibreOffice recusa calado). Erro =
#        ODT intacto e saída ≠ 0 (quem chama segue: no pior caso o PDF sai como antes). Idempotente.
#      odt-math-bars.py --roles        — TESTE: lê HTML/MathML no stdin e imprime, por <math>, o
#        papel de cada barra (O abre, C fecha, M meio, L solta; prefixo D = dupla).
# Teste: server/test/smoke-odt-math-bars.sh; a cadeia real: server/test/render-docs.sh.
import os
import re
import sys
import tempfile
import zipfile
import xml.etree.ElementTree as ET

M = 'http://www.w3.org/1998/Math/MathML'
ET.register_namespace('', M)

BARS = {'|': 's', '∣': 's', '∥': 'd', '‖': 'd'}   # | ∣ ∥ ‖
OPENB = set('([{⟨⌊⌈')                             # ( [ { ⟨ ⌊ ⌈
CLOSEB = set(')]}⟩⌋⌉')
POSTOP = set('′″‴!')                                # ′ ″ ‴ !
# operador que o texmath às vezes emite como <mi> (o `-` depois de uma barra sai `<mi>−</mi>`)
OPS = set('+-−=<>≤≥≠±∓×÷⋅·*/,;:'
          '∈∉⊂⊆∪∩∧∨¬→←↔⇒⇔'
          '∑∏∫…')
SCRIPTS = {'msub', 'msup', 'msubsup', 'munder', 'mover', 'munderover', 'mmultiscripts'}
GROUP = {'mrow', 'mstyle', 'mpadded', 'mphantom'}
LEAF = {'mi', 'mn', 'mo', 'mtext', 'mspace', 'ms'}
ATTRS = ('form', 'stretchy', 'fence')


def tag(e):
    return e.tag.split('}', 1)[-1]


def text(e):
    return (e.text or '').strip()


def is_bar(e):
    return tag(e) == 'mo' and text(e) in BARS and any(e.get(a) is not None for a in ATTRS)


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


def process(row, role):
    seq, rows = [], []
    flatten(row, seq, rows)
    toks = [e for e in seq if kind(e, {}) != 'skip']
    stack = {'s': [], 'd': []}
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
        elif r == 'close':
            if stack[b]:
                stack[b].pop()
            else:
                r = 'lone'
        role[e] = r
    for b in stack:
        for e in stack[b]:
            role[e] = 'lone'
    for c in rows:   # sub-linhas (índices, frações, raízes, células): independentes
        if tag(c) not in LEAF:
            process(c, role)


def roles_of(root):
    role = {}
    process(root, role)
    return role


def rewrite(root, role):
    for e, r in role.items():
        b = BARS[text(e)]
        st = 'true' if e.get('stretchy') == 'true' else 'false'
        for a in ATTRS:
            e.attrib.pop(a, None)
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


def fix_formula(data):
    """bytes do content.xml de uma fórmula -> bytes novos, ou None se não muda nada."""
    try:
        root = ET.fromstring(data)
    except ET.ParseError:
        return None
    if root.tag != '{%s}math' % M:
        return None
    role = roles_of(root)
    if not role:
        return None
    rewrite(root, role)
    out = ('<?xml version="1.0" encoding="UTF-8"?>' + ET.tostring(root, encoding='unicode')).encode('utf-8')
    return None if out == data else out


def fix_odt(path):
    with zipfile.ZipFile(path) as zi:
        infos = zi.infolist()
        new = {}
        for info in infos:
            n = info.filename
            if n.endswith('/content.xml'):
                out = fix_formula(zi.read(n))
                if out is not None:
                    new[n] = out
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
    return len(new)


def main(argv):
    if len(argv) == 2 and argv[1] == '--roles':
        code = {'open': 'O', 'close': 'C', 'infix': 'M', 'lone': 'L'}
        for m in re.findall(r'<math\b.*?</math>', sys.stdin.read(), flags=re.S):
            root = ET.fromstring(m)
            role = roles_of(root)
            print(' '.join(('D' if BARS[text(e)] == 'd' else '') + code[role[e]]
                           for e in root.iter() if e in role))
        return 0
    if len(argv) != 2:
        print('uso: odt-math-bars.py <arquivo.odt> | --roles', file=sys.stderr)
        return 2
    print(fix_odt(argv[1]))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
