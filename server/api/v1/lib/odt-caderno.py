#!/usr/bin/env python3
# odt-caderno.py <arquivo.odt> [--event TEXTO] [--logo arquivo.png] [--first-page N] — o passo de PÁGINA do documento
# impresso (caderno, editorial), depois do pandoc e do odt-math-bars.py. Reescreve o ODT no lugar
# (atômico, mimetype primeiro e sem compressão) e é fail-open: erro aqui = o PDF sai como antes.
#
# Três coisas que o pandoc não faz (molde dos cadernos da Maratona SBC, pedido de 28/09/2026 depois
# da XIV Maratona UnB — "pouca cara de LaTeX"):
#   1. ESTILOS DA TABELA DE EXEMPLOS. O lib/odt-samples.lua emite a tabela crua com os nomes
#      `MojSample{Tbl,Col,Row,Cell}`; o LibreOffice só aplica estilo de tabela/célula AUTOMÁTICO do
#      content.xml (estilo comum do styles.xml é ignorado na célula — testado), então eles entram
#      aqui, só quando a tabela existe.
#   2. RODAPÉ "evento – Problema A – título · página". O caderno-reference.odt traz o campo de
#      capítulo (`text:chapter`, o \leftmark do LaTeX: o título de nível 1 corrente) e a página; o nome
#      do evento é por contest e entra aqui (`--event`), antes do campo.
#   3. LOGO NO CABEÇALHO (opcional, `--logo`): a imagem vai para `Pictures/` do ODT e para o cabeçalho
#      da página mestra, centralizada, com altura fixa (a faixa de logos dos cadernos da SBC).
#   4. ENTRELINHA DE PARÁGRAFO COM IMAGEM: o corpo tem entrelinha proporcional < 100% (a do LaTeX, ver
#      o reference-doc) e o LibreOffice encolhe junto a linha de uma imagem `as-char` — ela subia por
#      cima do texto de cima (a figura do Jogo da Memória, XIV Maratona UnB). Parágrafo que contém
#      imagem ou caixa de figura ganha um estilo automático filho do dele com 100%. Fórmula
#      (`draw:object`) fica de fora: nela os 89% não cortam nada e a linha segue igual às outras.
#   5. PRIMEIRA PÁGINA (`--first-page N`): no caminho por-problema do caderno (há enunciado em PDF
#      próprio no meio) cada problema é um ODT à parte; o 1º título ganha `style:page-number=N` e a
#      numeração segue a do caderno em vez de voltar a 1 em cada problema.
#   6. SÍMBOLO QUE A CMU NÃO TEM (⊕ ⋅ ≤ ∑ ∈ … digitados no TEXTO, fora de `$…$`): ganha um span com a
#      fonte Latin Modern Math (fonts-lmodern, a matemática do LaTeX). Sem isso o LibreOffice escolhe o
#      substituto sozinho — DejaVu Serif no 25.2 da imagem, DejaVu Sans no 26.2 do dev — e o 25.2 NEM
#      CONSULTA o fontconfig para isso (FC_DEBUG, 28/09/2026: regra de fontconfig não adianta). A cobertura
#      das duas fontes vem do fontconfig (`fc-match -f %{charset}`); sem ele ou sem a fonte, nada muda.
#      Sobrescrito/subscrito Unicode (`10⁹`) que nenhuma das duas tem vira o dígito da CMU em posição
#      de índice (o `10^9` do LaTeX).
#      Fórmula (objeto do LibreOffice Math) não passa por aqui: lá os símbolos são da OpenSymbol.
import os, re, struct, subprocess, sys, tempfile, zipfile
from xml.sax.saxutils import escape

LOGO_H_CM = 1.6          # altura da faixa do logo
TEXT_W_CM = 16.0         # largura útil do A4 com margens de 2,5 cm (caderno-reference.odt)

SAMPLE_STYLES = (
    '<style:style style:name="MojSampleTbl" style:family="table">'
    '<style:table-properties style:width="%.2fcm" table:align="margins" fo:margin-top="0.12cm" '
    'fo:margin-bottom="0.3cm" style:may-break-between-rows="true"/></style:style>'
    '<style:style style:name="MojSampleCol" style:family="table-column">'
    '<style:table-column-properties style:column-width="%.2fcm"/></style:style>'
    '<style:style style:name="MojSampleRow" style:family="table-row">'
    '<style:table-row-properties fo:keep-together="always"/></style:style>'
    '<style:style style:name="MojSampleCell" style:family="table-cell">'
    '<style:table-cell-properties fo:padding-left="0.15cm" fo:padding-right="0.15cm" '
    'fo:padding-top="0.06cm" fo:padding-bottom="0.1cm" fo:border="0.5pt solid #000000"/></style:style>'
) % (TEXT_W_CM, TEXT_W_CM / 2)


def png_size(b):
    if b[:8] == b'\x89PNG\r\n\x1a\n':
        return struct.unpack('>II', b[16:24])
    return None


def first_page(s, n):
    """content.xml: o 1º título de nível 1 recomeça a numeração em N (idempotente)."""
    if not n or 'style:name="MojFirstPage"' in s:
        return s
    st = ('<style:style style:name="MojFirstPage" style:family="paragraph" style:parent-style-name="Heading_20_1" '
          'style:master-page-name="Standard"><style:paragraph-properties style:page-number="%d"/></style:style>' % n)
    s2, k = re.subn(r'<text:h text:style-name="Heading_20_1"', '<text:h text:style-name="MojFirstPage"', s, count=1)
    if not k:
        return s
    if '<office:automatic-styles/>' in s2:
        return s2.replace('<office:automatic-styles/>', '<office:automatic-styles>' + st + '</office:automatic-styles>', 1)
    s3, k = re.subn(r'</office:automatic-styles>', st + '</office:automatic-styles>', s2, count=1)
    return s3 if k else s


P_OPEN = re.compile(r'<text:p text:style-name="([^"]+)"')


def img_lines(s):
    """content.xml: parágrafo cujo trecho (até o próximo <text:p ou </text:p>) tem draw:image ou
    draw:text-box ganha o estilo `MojImg_<estilo>` (filho do original, entrelinha 100%)."""
    out, pos, used = [], 0, set()
    for m in P_OPEN.finditer(s):
        st = m.group(1)
        seg_end = len(s)
        for tok in ('<text:p ', '<text:p>', '</text:p>'):
            k = s.find(tok, m.end())
            if k != -1:
                seg_end = min(seg_end, k)
        seg = s[m.end():seg_end]
        if st.startswith('MojImg_') or ('<draw:image' not in seg and '<draw:text-box' not in seg):
            continue
        out.append(s[pos:m.start()]); out.append('<text:p text:style-name="MojImg_%s"' % st)
        pos = m.end(); used.add(st)
    if not used:
        return s
    out.append(s[pos:])
    s2 = ''.join(out)
    def one(st):
        # estilo AUTOMÁTICO (P1, P2… do pandoc) não pode ser pai de outro automático no ODF: vira CÓPIA
        m = re.search(r'<style:style style:name="%s"[^>]*?(/>|>.*?</style:style>)' % re.escape(st), s2, re.S)
        if m:
            x = m.group(0).replace('style:name="%s"' % st, 'style:name="MojImg_%s"' % st, 1)
            if x.endswith('/>'):
                return x[:-2] + '><style:paragraph-properties fo:line-height="100%"/></style:style>'
            if '<style:paragraph-properties' in x:
                x = re.sub(r'\sfo:line-height="[^"]*"', '', x)
                return re.sub(r'<style:paragraph-properties', '<style:paragraph-properties fo:line-height="100%"', x, count=1)
            return x.replace('</style:style>', '<style:paragraph-properties fo:line-height="100%"/></style:style>')
        return ('<style:style style:name="MojImg_%s" style:family="paragraph" style:parent-style-name="%s">'
                '<style:paragraph-properties fo:line-height="100%%"/></style:style>' % (st, st))
    sts = ''.join(one(st) for st in sorted(used))
    if '<office:automatic-styles/>' in s2:
        return s2.replace('<office:automatic-styles/>', '<office:automatic-styles>' + sts + '</office:automatic-styles>', 1)
    s3, k = re.subn(r'</office:automatic-styles>', sts + '</office:automatic-styles>', s2, count=1)
    return s3 if k else s


SYM_FONT = 'Latin Modern Math'
SYM_BODY = 'CMU Serif'
# só blocos de SÍMBOLO (setas, operadores, técnicos, geométricos, delimitadores, alfanuméricos
# matemáticos) — letra, pontuação e emoji ficam com quem já os desenha
SYM_BLOCKS = ((0x2030, 0x205F), (0x2100, 0x2BFF), (0x1D400, 0x1D7FF))
# sobrescrito/subscrito Unicode (`10⁹`, `x₁`) que a CMU não tem — nem a Latin Modern Math: vira o
# caractere comum da própria CMU em posição de índice, como o LaTeX desenha `10^9` (sem isso, DejaVu)
SUPS = dict(zip('⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ⁱⁿ', '0123456789+−=()in'))
SUBS = dict(zip('₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎ₐₑₒₓₕₖₗₘₙₚₛₜ', '0123456789+−=()aeoxhklmnpst'))
TEXT_PARENTS = {'text:p', 'text:h', 'text:span', 'text:a'}


def fc_charset(family):
    """conjunto de code points da fonte (fontconfig), ou None se a família não existe/sem fc-match."""
    try:
        r = subprocess.run(['fc-match', '-f', '%{family}\n%{charset}', family + ':charset=20'],
                           capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return None
    fam, _, cs = r.stdout.partition('\n')
    if r.returncode != 0 or family not in fam.split(','):
        return None
    out = set()
    for tok in cs.split():
        a, _, b = tok.partition('-')
        try:
            lo = int(a, 16); hi = int(b, 16) if b else lo
        except ValueError:
            continue
        out.update(range(lo, hi + 1))
    return out


_SYM = None


def sym_set():
    """{code point: ('MojSym', o mesmo char) | ('MojSup'|'MojSub', o char comum)} — só o que a CMU não tem."""
    global _SYM
    if _SYM is None:
        body, sym = fc_charset(SYM_BODY), fc_charset(SYM_FONT)
        _SYM = {}
        if body and sym:
            for c in sym - body:
                if any(lo <= c <= hi for lo, hi in SYM_BLOCKS):
                    _SYM[c] = ('MojSym', chr(c))
            for tab, st in ((SUPS, 'MojSup'), (SUBS, 'MojSub')):
                for k, v in tab.items():
                    if ord(k) not in body and all(ord(x) in body for x in v):
                        _SYM[ord(k)] = (st, v)
    return _SYM


SYM_STYLES = {
    'MojSym': '<style:text-properties style:font-name="MojMath" style:font-name-asian="MojMath" style:font-name-complex="MojMath"/>',
    'MojSup': '<style:text-properties style:text-position="super 58%"/>',
    'MojSub': '<style:text-properties style:text-position="sub 58%"/>',
}


def _ins_auto(s, st):
    if '<office:automatic-styles/>' in s:
        return s.replace('<office:automatic-styles/>', '<office:automatic-styles>' + st + '</office:automatic-styles>', 1)
    s2, k = re.subn(r'</office:automatic-styles>', lambda m: st + m.group(0), s, count=1)
    if k:
        return s2
    return re.sub(r'<office:body>', lambda m: '<office:automatic-styles>' + st + '</office:automatic-styles>' + m.group(0), s, count=1)


def sym_spans(s, syms=None):
    """content.xml: texto de parágrafo/título com caractere de `syms` vira span MojSym (Latin Modern
    Math) ou MojSup/MojSub (índice com o char comum). Só texto cujo pai é text:p/h/span/a (nunca
    atributo, título de figura, etc.); idempotente."""
    syms = sym_set() if syms is None else syms
    b = s.find('<office:body>')
    if not syms or b < 0 or not any(ord(ch) in syms for ch in s[b:] if ord(ch) > 0x206F):
        return s
    out, stack, used = [s[:b]], [], set()
    for m in re.finditer(r'<[^>]*>|[^<]+', s[b:]):
        t = m.group(0)
        if t[0] == '<':
            out.append(t)
            if t.startswith('</'):
                if stack:
                    stack.pop()
            elif t[1] in '?!' or t.endswith('/>'):
                pass
            else:
                name = t[1:].split(None, 1)[0].rstrip('>')
                stack.append((name, re.search(r'text:style-name="Moj(Sym|Sup|Sub)"', t) is not None))
            continue
        if not stack or stack[-1][0] not in TEXT_PARENTS or stack[-1][1]:
            out.append(t); continue
        if not any(ord(ch) in syms for ch in t):
            out.append(t); continue
        run_st, run = None, []
        def flush():
            if run_st:
                out.append('<text:span text:style-name="%s">%s</text:span>' % (run_st, ''.join(run)))
            else:
                out.append(''.join(run))
        for ch in t:
            st, rep = syms.get(ord(ch), (None, ch))
            if st != run_st:
                flush(); run_st, run = st, []
            run.append(rep)
        flush()
        used.update(st for st, _ in (syms.get(ord(ch), (None, None)) for ch in t) if st)
    s2 = ''.join(out)
    if s2 == s:
        return s
    if 'MojSym' in used and 'style:name="MojMath"' not in s2:
        face = ('<style:font-face style:name="MojMath" svg:font-family="&apos;%s&apos;" '
                'style:font-family-generic="roman" style:font-pitch="variable"/>' % SYM_FONT)
        if '<office:font-face-decls/>' in s2:
            s2 = s2.replace('<office:font-face-decls/>', '<office:font-face-decls>' + face + '</office:font-face-decls>', 1)
        elif '</office:font-face-decls>' in s2:
            s2 = s2.replace('</office:font-face-decls>', face + '</office:font-face-decls>', 1)
        else:
            s2 = re.sub(r'(<office:(automatic-styles|body)[ />])', lambda m: '<office:font-face-decls>' + face + '</office:font-face-decls>' + m.group(1), s2, count=1)
    for st in sorted(used):
        if 'style:name="%s"' % st not in s2:
            s2 = _ins_auto(s2, '<style:style style:name="%s" style:family="text">%s</style:style>' % (st, SYM_STYLES[st]))
    return s2


def fix_content(s):
    """content.xml: estilos automáticos da tabela de exemplos (idempotente)."""
    if 'table:style-name="MojSampleTbl"' not in s or 'style:name="MojSampleTbl"' in s:
        return None
    if '<office:automatic-styles/>' in s:
        return s.replace('<office:automatic-styles/>', '<office:automatic-styles>' + SAMPLE_STYLES + '</office:automatic-styles>', 1)
    s2, n = re.subn(r'</office:automatic-styles>', SAMPLE_STYLES + '</office:automatic-styles>', s, count=1)
    if n:
        return s2
    s2, n = re.subn(r'(<office:body>)', '<office:automatic-styles>' + SAMPLE_STYLES + r'</office:automatic-styles>\1', s, count=1)
    return s2 if n else None


def fix_styles(s, event, logo):
    """styles.xml: evento no rodapé e (opcional) o cabeçalho com o logo."""
    out = s
    if event and 'MojFooterEvent' not in out:
        span = '<text:span text:style-name="MojFooterEvent">%s – </text:span>' % escape(event)
        out = re.sub(r'(<text:p text:style-name="MojFooter">)', r'\1' + span.replace('\\', r'\\'), out, count=1)
        if '<office:automatic-styles>' in out:
            out = out.replace('<office:automatic-styles>', '<office:automatic-styles><style:style '
                              'style:name="MojFooterEvent" style:family="text"/>', 1)
    if logo and 'MojLogo' not in out:
        href, wcm = logo
        frame = ('<style:header><text:p text:style-name="MojHeader"><draw:frame draw:style-name="MojLogoFr" '
                 'draw:name="MojLogo" text:anchor-type="as-char" svg:width="%.3fcm" svg:height="%.3fcm" '
                 'draw:z-index="0"><draw:image xlink:href="%s" xlink:type="simple" xlink:show="embed" '
                 'xlink:actuate="onLoad"/></draw:frame></text:p></style:header>') % (wcm, LOGO_H_CM, href)
        out = re.sub(r'(<style:master-page style:name="Standard"[^>]*>)', r'\1' + frame, out, count=1)
        hstyle = ('<style:header-style><style:header-footer-properties fo:min-height="0cm" '
                  'fo:margin-left="0cm" fo:margin-right="0cm" fo:margin-bottom="0.5cm" '
                  'style:dynamic-spacing="true"/></style:header-style>')
        out = re.sub(r'<style:header-style\s*/>', hstyle, out, count=1)
        # com a faixa do logo o corpo começa um pouco mais alto (o cabeçalho ocupa a margem de cima)
        out = re.sub(r'(<style:page-layout style:name="Mpm1">\s*<style:page-layout-properties[^>]*?)'
                     r'fo:margin-top="2.5cm"', r'\1fo:margin-top="1.2cm"', out, count=1)
        gstyle = ('<style:style style:name="MojLogoFr" style:family="graphic"><style:graphic-properties '
                  'style:wrap="none" style:vertical-pos="top" style:vertical-rel="baseline" '
                  'style:horizontal-pos="center" style:horizontal-rel="paragraph" fo:border="none" '
                  'fo:padding="0cm" fo:margin-left="0cm" fo:margin-right="0cm" fo:margin-top="0cm" '
                  'fo:margin-bottom="0cm"/></style:style>')
        if '<office:automatic-styles>' in out:
            out = out.replace('<office:automatic-styles>', '<office:automatic-styles>' + gstyle, 1)
        elif '<office:automatic-styles/>' in out:
            out = out.replace('<office:automatic-styles/>', '<office:automatic-styles>' + gstyle + '</office:automatic-styles>', 1)
    return None if out == s else out


def fix_odt(path, event=None, logo=None, first=None):
    with zipfile.ZipFile(path) as zi:
        infos = zi.infolist()
        new, add = {}, {}
        c0 = zi.read('content.xml').decode('utf-8')
        c = fix_content(c0)
        c = img_lines(c if c is not None else c0)
        c = first_page(c, first)
        c = sym_spans(c)
        if c != c0:
            new['content.xml'] = c.encode('utf-8')
        lg = None
        if logo:
            b = open(logo, 'rb').read()
            px = png_size(b)
            if px and px[0] > 0 and px[1] > 0:
                href = 'Pictures/moj-header-logo.png'
                lg = (href, min(TEXT_W_CM, LOGO_H_CM * px[0] / px[1]))
                add[href] = b
        s = fix_styles(zi.read('styles.xml').decode('utf-8'), event, lg)
        if s is not None:
            new['styles.xml'] = s.encode('utf-8')
        if add:
            m = zi.read('META-INF/manifest.xml').decode('utf-8')
            for href in add:
                if href not in m:
                    m = m.replace('</manifest:manifest>', '<manifest:file-entry manifest:full-path="%s" '
                                  'manifest:media-type="image/png"/></manifest:manifest>' % href, 1)
            new['META-INF/manifest.xml'] = m.encode('utf-8')
        if not new and not add:
            return 0
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(path)), suffix='.odt')
        os.close(fd)
        try:
            with zipfile.ZipFile(tmp, 'w') as zo:
                order = [i for i in infos if i.filename == 'mimetype'] + [i for i in infos if i.filename != 'mimetype']
                for info in order:
                    data = new.get(info.filename)
                    if data is None:
                        data = zi.read(info.filename)
                    z = zipfile.ZipInfo(info.filename, date_time=info.date_time)
                    z.external_attr = info.external_attr
                    z.compress_type = zipfile.ZIP_STORED if info.filename == 'mimetype' else zipfile.ZIP_DEFLATED
                    zo.writestr(z, data)
                for href, data in add.items():
                    if href not in {i.filename for i in infos}:
                        z = zipfile.ZipInfo(href)
                        z.compress_type = zipfile.ZIP_DEFLATED
                        zo.writestr(z, data)
            os.replace(tmp, path)
        except BaseException:
            os.unlink(tmp)
            raise
    return len(new) + len(add)


def main(argv):
    args, event, logo, first = [], None, None, None
    it = iter(argv[1:])
    for a in it:
        if a == '--event':
            event = next(it, '')
        elif a == '--logo':
            logo = next(it, '')
        elif a == '--first-page':
            v = next(it, '')
            first = int(v) if v.isdigit() and int(v) > 1 else None
        else:
            args.append(a)
    if len(args) != 1:
        print('uso: odt-caderno.py <arquivo.odt> [--event TEXTO] [--logo arquivo.png] [--first-page N]', file=sys.stderr)
        return 2
    if logo and not os.path.isfile(logo):
        logo = None
    print(fix_odt(args[0], event or None, logo, first))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
