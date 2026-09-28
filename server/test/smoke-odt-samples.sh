#!/bin/bash
# smoke-odt-samples.sh — o molde SBC do documento impresso, na metade que NÃO precisa do LibreOffice:
#   lib/odt-samples.lua  — exemplos (`section.moj-exemplos`) viram TABELA "Exemplo de entrada N | Exemplo
#                          de saída N", rótulos no idioma do documento, explicação "… do exemplo N",
#                          espaço/TAB do exemplo preservados, o título "Exemplos" some;
#   lib/odt-caderno.py   — estilos automáticos da tabela (célula só pega estilo AUTOMÁTICO), evento no
#                          rodapé, logo no cabeçalho, 1ª página do problema e entrelinha 100% no
#                          parágrafo com imagem (o corpo tem 89% e a imagem subia sobre o texto).
# O papel (PDF) é conferido no render-docs.sh, que roda com o soffice (dev e DENTRO da imagem).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
L="$ROOT/api/v1/lib"; REF="$ROOT/etc/caderno-reference.odt"
command -v pandoc >/dev/null 2>&1 || { echo "SKIP: sem pandoc"; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; ((fail++)); fi; }

cat > "$T/in.html" <<'HTML'
<!DOCTYPE html><html><head><meta charset="utf-8"></head><body>
<h1>Problema A – Soma</h1><p>Some.</p>
<section class="moj-exemplos"><h2>Exemplos</h2>
<div class="moj-exemplo"><h3>Entrada</h3><pre data-sample="s1" data-kind="input">1 2
  3	4 &amp; 5</pre><h3>Saída</h3><pre data-sample="s1" data-kind="output">3</pre>
<div class="moj-exemplo-nota"><h3>Explicação</h3><p>Porque sim.</p></div></div>
<div class="moj-exemplo"><h3>Entrada</h3><pre data-kind="input">9</pre><h3>Saída</h3><pre data-kind="output">9</pre></div>
</section>
<p><img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC" alt="x"></p>
</body></html>
HTML
odt(){ # <lang> <saida>
  pandoc -f html -t odt --reference-doc="$REF" --lua-filter="$L/odt-samples.lua" \
    -M "moj-lang=$1" -M "lang=pt-BR" "$T/in.html" -o "$2" 2>/dev/null; }

echo "== filtro: exemplos em tabela =="
odt pt "$T/pt.odt"; C="$(unzip -p "$T/pt.odt" content.xml)"
ck "duas tabelas MojSample"                          '[[ "$(grep -o "table:style-name=\"MojSampleTbl\"" <<<"$C" | wc -l)" == 2 ]]'
ck "rótulos PT numerados"                            'grep -q "Exemplo de entrada 1" <<<"$C" && grep -q "Exemplo de saída 2" <<<"$C"'
ck "explicação vira \"Explicação do exemplo 1\""    'grep -q "Explicação do exemplo 1" <<<"$C" && grep -q "Porque sim" <<<"$C"'
ck "o título \"Exemplos\" some"                      '! grep -q ">Exemplos<" <<<"$C"'
# (o TAB o próprio leitor de HTML do pandoc já entrega como espaço — o filtro trata o que chegar)
ck "espaço inicial repetido e & preservados"         'grep -q "<text:s text:c=\"2\"/>3 4 &amp; 5" <<<"$C"'
ck "linhas do exemplo em MojSampleText"              'grep -q "<text:p text:style-name=\"MojSampleText\">1 2</text:p>" <<<"$C"'
odt en "$T/en.odt"; CE="$(unzip -p "$T/en.odt" content.xml)"
odt es "$T/es.odt"; CS="$(unzip -p "$T/es.odt" content.xml)"
ck "rótulos EN"                                      'grep -q "Sample input 1" <<<"$CE" && grep -q "Explanation of sample 1" <<<"$CE"'
ck "rótulos ES"                                      'grep -q "Ejemplo de salida 2" <<<"$CS" && grep -q "Explicación del ejemplo 1" <<<"$CS"'
ck "idioma do documento no estilo (lang=pt-BR)"      'D="$(unzip -p "$T/pt.odt" styles.xml | tr "\n" " " | grep -o "<style:default-style style:family=\"paragraph\">.*</style:default-style>")"; grep -q "fo:language=\"pt\"" <<<"$D" && grep -q "fo:country=\"BR\"" <<<"$D"'

echo "== passo de página (odt-caderno.py) =="
printf '\x89PNG\r\n\x1a\n\0\0\0\rIHDR\0\0\x01\x90\0\0\0\x50\x08\x02\0\0\0' > "$T/logo.png"   # 400×80
python3 "$L/odt-caderno.py" "$T/pt.odt" --event 'Maratona <Teste> & Cia' --logo "$T/logo.png" --first-page 7 >/dev/null
C="$(unzip -p "$T/pt.odt" content.xml)"; S="$(unzip -p "$T/pt.odt" styles.xml)"
ck "estilos automáticos da tabela no content.xml"    'grep -q "style:name=\"MojSampleCell\"" <<<"$C" && grep -q "fo:border=\"0.5pt solid #000000\"" <<<"$C"'
ck "evento (escapado) antes do capítulo no rodapé"   'grep -q "Maratona &lt;Teste&gt; &amp; Cia – </text:span><text:chapter" <<<"$S"'
ck "logo no cabeçalho + Pictures + manifesto"       'grep -q "draw:name=\"MojLogo\"" <<<"$S" && unzip -l "$T/pt.odt" | grep -q "Pictures/moj-header-logo.png" && unzip -p "$T/pt.odt" META-INF/manifest.xml | grep -q "moj-header-logo.png"'
ck "logo: 1,6 cm de altura, proporção 400×80"        'grep -q "svg:width=\"8.000cm\" svg:height=\"1.600cm\"" <<<"$S"'
ck "1ª página: o 1º título recomeça em 7"            'grep -q "style:page-number=\"7\"" <<<"$C" && grep -q "<text:h text:style-name=\"MojFirstPage\"" <<<"$C"'
ck "parágrafo com imagem ganha entrelinha 100%"      'grep -q "<text:p text:style-name=\"MojImg_" <<<"$C" && grep -q "fo:line-height=\"100%\"" <<<"$C"'
ck "idempotente (2ª passada não duplica)"            'python3 "$L/odt-caderno.py" "$T/pt.odt" --event "Maratona <Teste> & Cia" --logo "$T/logo.png" --first-page 7 >/dev/null; [[ "$(unzip -p "$T/pt.odt" styles.xml | grep -o "MojLogo\"" | wc -l)" == 1 && "$(unzip -p "$T/pt.odt" content.xml | grep -o "style:name=\"MojSampleTbl\"" | wc -l)" == 1 ]] && ! unzip -p "$T/pt.odt" content.xml | grep -q "MojImg_MojImg_"'
ck "mimetype 1º e sem compressão"                   'python3 -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); i=z.infolist()[0]; sys.exit(not (i.filename==\"mimetype\" and i.compress_type==0))" "$T/pt.odt"'
ck "sem --event/--logo: nada de evento nem logo"      'odt pt "$T/b.odt"; python3 "$L/odt-caderno.py" "$T/b.odt" >/dev/null; ! unzip -p "$T/b.odt" styles.xml | grep -q "MojFooterEvent\|MojLogo"'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
