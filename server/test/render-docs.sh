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
# ⚠ Precisa de pandoc + soffice + poppler: NÃO roda no checkout de desenvolvimento.
#    Rode DENTRO da imagem:  podman exec <container> bash /opt/moj/cdmoj/server/test/render-docs.sh
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
  printf "PROBS=( x col#pa 'Soma Simples' A col#pa )\n"; } > "$C/conf"
# um enunciado com os elementos que denunciam tipografia: itálico, negrito, código e tabela
cat > "$C/enunciados/col#pa.html" <<'HTML'
<!DOCTYPE html><html><head><meta charset="utf-8"><title>Soma</title></head><body>
<h1 class="moj-title">Soma Simples</h1>
<p>Dados dois inteiros <em>a</em> e <em>b</em>, com <strong>1 ≤ a, b ≤ 10⁹</strong>, escreva a
soma. Este parágrafo existe para haver texto suficiente para o justificado mostrar a que veio,
com pelo menos três linhas de corpo em A4.</p>
<h2>Entrada</h2><p>Uma linha com <em>a</em> e <em>b</em>.</p>
<h2>Saída</h2><p>Uma linha com a soma.</p>
<pre>2 3
5</pre>
</body></html>
HTML

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
  for t in info-sheet times contest; do
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

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
