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
import os, re, struct, sys, tempfile, zipfile
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
