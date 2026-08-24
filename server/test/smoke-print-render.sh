#!/bin/bash
# smoke-print-render.sh — a cadeia REAL de impressão do staff: <id>.src -> <id>.combined.pdf.
#
#   bash server/test/smoke-print-render.sh
#
# POR QUE EXISTE: em agosto/2026 TODA impressão de código-fonte do `mdp-teste-2026` saía só com a
# folha de rosto. O `_pr_render` chamava `paps --format=pdf`, opção que só existe no paps >= 0.7,
# e a imagem tem **0.6.8** — o comando morria com "Unknown option", o `2>/dev/null` engolia a
# mensagem, `docok=0`, e a capa ia sozinha para o cache com um "não foi possível converter"
# impresso nela. No DEV o paps é 0.8 e aceita: por isso passou pela revisão.
#
# E havia um segundo, escondido atrás do primeiro: `.cpp` salvo em CP1252/ISO-8859-1 (Dev-C++ no
# Windows, com um `// solução` no comentário) faz o paps abortar — ele só lê UTF-8. Numa prova
# latino-americana esse não é o arquivo raro, é o arquivo típico.
#
# Nada disso tinha teste: o `smoke-contest-staff.sh` fabrica o meta à mão com `"pages":1` e nunca
# cria um `.src`. Este arquivo fecha o buraco pelos DOIS lados — a conversão e o cache.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"          # .../server
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; ((fail++)); fi; }

for b in paps ps2pdf pdfinfo magick iconv nl file; do
  command -v "$b" >/dev/null 2>&1 || { echo "SKIP: falta '$b' — este teste roda onde a cadeia de"
    echo "      impressão existe (a imagem, ou um dev com paps+ghostscript instalados)."; exit 0; }
done

export CONTESTSDIR="$FIX"
C="$FIX/pr"; mkdir -p "$C/print-requests" "$C/users/time-x"
printf 'CONTEST_ID=pr\nCONTEST_TYPE=icpc\n' > "$C/conf"
jq -cn '{login:"time-x",password:"p",fullname:"Time X",status:"active",
         team:{name:"Time X",univ_full:"Universidade Exemplo"}}' > "$C/users/time-x/account.json"
source "$ROOT/api/v1/lib/print.sh" 2>/dev/null

mkreq(){ # <id> <arquivo> <nome-visível>
  local id="$1"
  cp "$2" "$C/print-requests/$id.src"
  jq -cn --arg id "$id" --arg fn "$3" --argjson t 100 \
    '{id:$id, seq:7, login:"time-x", fullname:"Time X", team:"Time X", univ:"Universidade Exemplo",
      kind:"print", filename:$fn, mime:"text/x-c", size:100, time:$t, status:"pending", pages:0}' \
    > "$C/print-requests/$id.json"
}
pages(){ pdfinfo "$1" 2>/dev/null | awk '/^Pages:/{print $2; exit}'; }

# --- os três encodings que chegam de uma sala de verdade ------------------------------------
printf '#include <stdio.h>\nint main(void){ return 0; }\n'                       > "$FIX/ascii.cpp"
printf '#include <stdio.h>\n/* solu\303\247\303\243o do exerc\303\255cio */\nint main(void){ return 0; }\n' > "$FIX/utf8.cpp"
printf '#include <stdio.h>\n/* solu\347\343o do exerc\355cio */\nint main(void){ return 0; }\n'             > "$FIX/latin1.cpp"

echo "== texto -> PDF (o que a sala imprime) =="
i=0
for f in ascii utf8 latin1; do
  i=$((i+1)); id="req$i"
  mkreq "$id" "$FIX/$f.cpp" "solucao-$f.cpp"
  out="$(pr_build_pdf pr "$id")"; rc=$?
  meta="$C/print-requests/$id.json"
  ck "$f: pr_build_pdf devolve o cache"  '[[ $rc -eq 0 && -s "$out" ]]'
  ck "$f: build_ok=true no meta"         '[[ "$(jq -r .build_ok "$meta")" == true ]]'
  ck "$f: pages >= 1 no meta"            '[[ "$(jq -r .pages "$meta")" =~ ^[1-9] ]]'
  ck "$f: PDF tem capa + documento"      '(( $(pages "$out") >= 2 ))'
  ck "$f: sem arquivo de erro"           '[[ ! -f "$C/print-requests/$id.err" ]]'
done

echo "== o acento sobrevive ao caminho (iconv -> paps) =="
# o texto do paps não é extraível (ele desenha glifos), então a prova é indireta: o PDF do
# latin1 tem de ter o MESMO nº de páginas do utf8 e um tamanho comparável — se o iconv tivesse
# falhado, a conversão morreria e o PDF seria só a capa (1 página), já coberto acima.
ck "latin1 e utf8 rendem o mesmo nº de páginas" \
   '[[ "$(pages "$C/print-requests/req3.combined.pdf")" == "$(pages "$C/print-requests/req2.combined.pdf")" ]]'

echo "== o RODAPÉ de identificação (login do time) em TODA página =="
# O cabeçalho do paps é `<data> <título> Page N` e o título NÃO cabe o login: passando de ~14
# caracteres ele SOBREPÕE a data (medido em 4 tamanhos de fonte; a fonte do cabeçalho é fixa e
# não acompanha o `--font`). Por isso o login vai num selo A4 transparente carimbado por
# `qpdf --overlay --repeat=1`. Sem isso a folha de código que se solta da capa fica anônima na
# mesa da sala — que é justamente o que o rodapé existe p/ evitar.
if command -v qpdf >/dev/null 2>&1; then
  # arquivo comprido de propósito: o rodapé tem de valer em TODAS as páginas, não só na 1ª
  seq 1 200 | sed 's/^/int linha_/; s/$/(void){ return 0; }/' > "$FIX/longo.cpp"
  mkdir -p "$FIX/w1" "$FIX/w2"
  _pr_text2pdf "$FIX/longo.cpp" "$FIX/sem.pdf" "longo.cpp" ""                  "$FIX/w1" 2>/dev/null
  _pr_text2pdf "$FIX/longo.cpp" "$FIX/com.pdf" "longo.cpp" "time-x - longo.cpp" "$FIX/w2" 2>/dev/null
  ck "com e sem rodapé têm o mesmo nº de páginas" '[[ "$(pages "$FIX/sem.pdf")" == "$(pages "$FIX/com.pdf")" ]]'
  ck "o arquivo comprido rendeu várias páginas"   '(( $(pages "$FIX/com.pdf") >= 3 ))'
  ck "o rodapé mudou o PDF"                       '[[ "$(stat -c%s "$FIX/com.pdf")" -ne "$(stat -c%s "$FIX/sem.pdf")" ]]'
  # o selo é uma imagem, e ela tem de aparecer em TODAS as páginas — o erro clássico do overlay
  # é carimbar só a 1ª. ⚠ contar LINHAS do `pdfimages -list` dá o dobro: o selo é transparente,
  # então cada página lista `image` + `smask`. O que vale é o conjunto de PÁGINAS citadas.
  if command -v pdfimages >/dev/null 2>&1; then
    ck "o selo aparece em todas as páginas (--repeat=1)" \
       '[[ "$(pdfimages -list "$FIX/com.pdf" 2>/dev/null | awk "/^ *[0-9]/{print \$1}" | sort -u | wc -l)" == "$(pages "$FIX/com.pdf")" ]]'
  fi
  # e o pedido de verdade, pela cadeia inteira, tem de continuar saindo
  ck "pedido real com rodapé continua com capa + documento" '(( $(pages "$C/print-requests/req2.combined.pdf") >= 2 ))'
else
  echo "  (pulado: sem qpdf — o rodapé degrada p/ o PDF sem selo, de propósito)"
fi

echo "== cache: build que falhou NÃO fica servido para sempre =="
# simula o estado que o bug do paps deixou em produção: capa-só em cache e build_ok=false
id=req1; cache="$C/print-requests/$id.combined.pdf"; meta="$C/print-requests/$id.json"
antes="$(stat -c %Y "$cache")"
jq -c '.build_ok=false | .pages=0' "$meta" > "$meta.t" && mv -f "$meta.t" "$meta"
sleep 1; out="$(pr_build_pdf pr "$id")"
ck "refez o cache (build_ok era false)" '[[ "$(stat -c %Y "$cache")" -gt "$antes" ]]'
ck "e o meta voltou a true"             '[[ "$(jq -r .build_ok "$meta")" == true ]]'

echo "== cache: um DEPLOY que mexe na lib refaz o papel =="
# O desenho da folha mora no código, não no .src — então quando o `lib/print.sh` muda (rodapé
# novo, numeração, capa) o pedido antigo tem de se refazer sozinho na próxima impressão. Sem
# isto, "consertei e continua saindo o papel velho" volta a ser possível: é o mesmo veneno do
# build_ok, por outra porta. Datas antigas de propósito — a lib é sempre mais nova que 2020.
touch -d '2020-01-01' "$C/print-requests/$id.src" "$cache"
out="$(pr_build_pdf pr "$id")"
ck "cache mais velho que a lib foi refeito" '[[ "$(stat -c %Y "$cache")" -gt "$(date -d 2020-01-02 +%s)" ]]'

echo "== cache: build bom é reusado (build-once) =="
touch -d '1 hour ago' "$C/print-requests/$id.src"
m1="$(stat -c %Y "$cache")"; sleep 1; pr_build_pdf pr "$id" >/dev/null
ck "não reconverteu o que já estava bom" '[[ "$(stat -c %Y "$cache")" == "$m1" ]]'

echo "== arquivo binário desconhecido não derruba o pedido =="
# Aqui o resultado depende do que a máquina tem (o soffice converte quase tudo, e nem sempre
# está instalado). O que TEM de valer nos dois casos é a coerência: ou converteu e o PDF tem
# capa+documento, ou não converteu e o meta ASSUME isso — que é o sinal lido pela fila do staff.
head -c 300 /dev/urandom > "$FIX/bin.dat"
mkreq reqb "$FIX/bin.dat" "coisa.bin"
out="$(pr_build_pdf pr reqb)"; rc=$?
bmeta="$C/print-requests/reqb.json"
ck "ainda sai a folha de rosto"  '[[ $rc -eq 0 && -s "$out" ]]'
ck "meta coerente com o PDF"     '[[ "$(jq -r .build_ok "$bmeta")" == true ]] && (( $(pages "$out") >= 2 )) || { [[ "$(jq -r .build_ok "$bmeta")" == false ]] && (( $(pages "$out") == 1 )); }'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
