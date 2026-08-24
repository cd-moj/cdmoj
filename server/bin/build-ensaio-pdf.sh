#!/bin/bash
# build-ensaio-pdf.sh — o ROTEIRO DE ENSAIO DA SEDE em PDF, um por idioma.
#
#   bash server/bin/build-ensaio-pdf.sh [dir-de-saida] [pt|en|es …]
#
# A fonte é `web/contest/ajuda/ensaio/<lang>.html` — a MESMA página que fica no ar. Ela foi
# escrita em estilo de DOCUMENTO (o CSS de server/etc/contest-doc.css, sem flex nem grid) para
# que o `soffice --headless --convert-to pdf` produza o PDF que a organização publica como
# documento do contest:
#
#   moj contest -c <cid> docs upload  info ensaio-sede.pt.pdf --lang pt
#   moj contest -c <cid> docs publish info --lang pt
#
# ⚠ AS IMAGENS: o importador de HTML do LibreOffice resolve `src` RELATIVO ao arquivo. Por isso
# o script monta uma árvore temporária que repete o caminho `ensaio/<lang>.html` + `img/*.png` —
# copiar só o HTML dá um PDF sem nenhuma figura, e em silêncio.
#
# ⚠ NADA de PDF versionado: `server/var/` não é gitignorado. Sem argumento, a saída é um temp.
set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1   # raiz do cdmoj
ROOT="$PWD"
SRCDIR="$ROOT/web/contest/ajuda/ensaio"
IMGDIR="$ROOT/web/contest/ajuda/img"

OUT="${1:-}"; shift 2>/dev/null || true
[[ -n "$OUT" ]] || OUT="$(mktemp -d)"
mkdir -p "$OUT" || { echo "não consegui criar $OUT" >&2; exit 1; }
LANGS=( "$@" ); (( ${#LANGS[@]} )) || LANGS=( pt en es )

command -v soffice >/dev/null || { echo "soffice não encontrado (é o único engine de PDF)" >&2; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/ensaio" "$WORK/img"

rc=0
for l in "${LANGS[@]}"; do
  src="$SRCDIR/$l.html"
  [[ -f "$src" ]] || { echo "  $l: $src não existe — pulei" >&2; rc=1; continue; }

  # só as imagens que ESTA página cita (o dir de ajuda tem 30+; copiar tudo é desperdício)
  cp -f "$src" "$WORK/ensaio/$l.html"
  n=0
  while IFS= read -r img; do
    [[ -f "$IMGDIR/$img" ]] || { echo "  $l: imagem citada e ausente: $img" >&2; rc=1; continue; }
    cp -f "$IMGDIR/$img" "$WORK/img/$img"; n=$((n+1))
  done < <(grep -oE '\.\./img/[A-Za-z0-9._-]+' "$src" | sed 's|\.\./img/||' | sort -u)

  # ROTA PREFERIDA: pandoc html→odt (com o reference-doc do caderno) e soffice odt→pdf. O
  # importador de HTML do LibreOffice serve, mas afrouxa a entrelinha e desmonta as tabelas — o
  # mesmo documento saía com 27 páginas por lá e 14 por aqui. ⚠ o <title> tem de sair antes: o
  # pandoc o promoveria a um título órfão no topo da primeira página.
  ok=0
  if command -v pandoc >/dev/null 2>&1; then
    python3 - "$WORK/ensaio/$l.html" <<'PY' 2>/dev/null
import re, sys
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
open(p, 'w', encoding='utf-8').write(re.sub(r'<title>.*?</title>', '', s, flags=re.S))
PY
    if pandoc -f html -t odt --resource-path="$WORK/ensaio" \
              --reference-doc="$ROOT/server/etc/caderno-reference.odt" \
              "$WORK/ensaio/$l.html" -o "$WORK/ensaio/$l.odt" 2>/dev/null; then
      soffice --headless -env:UserInstallation="file://$WORK/lo" --convert-to pdf \
              --outdir "$WORK/ensaio" "$WORK/ensaio/$l.odt" >/dev/null 2>&1
      [[ -s "$WORK/ensaio/$l.pdf" ]] && ok=1
    fi
  fi
  # plano B: soffice direto no HTML (é o que a imagem faz quando não há pandoc)
  (( ok )) || soffice --headless -env:UserInstallation="file://$WORK/lo" --convert-to pdf \
          --outdir "$WORK/ensaio" "$WORK/ensaio/$l.html" >/dev/null 2>&1

  if [[ -s "$WORK/ensaio/$l.pdf" ]]; then
    mv -f "$WORK/ensaio/$l.pdf" "$OUT/ensaio-sede.$l.pdf"
    pg="$(pdfinfo "$OUT/ensaio-sede.$l.pdf" 2>/dev/null | awk '/^Pages:/{print $2; exit}')"
    printf '  %-3s %s  (%s páginas, %s imagens, %s bytes)\n' "$l" "ensaio-sede.$l.pdf" \
      "${pg:-?}" "$n" "$(stat -c%s "$OUT/ensaio-sede.$l.pdf")"
  else
    echo "  $l: o soffice não produziu PDF" >&2; rc=1
  fi
done

echo ">> em $OUT"
exit $rc
