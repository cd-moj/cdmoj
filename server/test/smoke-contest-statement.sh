#!/bin/bash
# /contest/statement — o enunciado SOB DEMANDA, e o gate dele.
#
# O corpo do enunciado saiu da lista (/contest/problems) em 20/08/2026: vinha em base64, e num
# contest de PDF isso é 3,8 MB por time (base64 de PDF não comprime — o PDF já é comprimido).
# Com 2000 times abrindo a prova no mesmo segundo são ~5 GB de uma vez, para entregar 12
# enunciados que cada um lê de um em um. Agora a lista só diz QUE existe e o corpo vem daqui.
#
# O risco que isso cria é de ACESSO: uma rota nova que serve enunciado é exatamente por onde a
# prova vaza. Ela tem de repetir o gate da lista — .staff nunca, competidor só depois do
# início — e responder **404**, não 403: antes de a prova abrir, nem a existência do problema
# pode ser confirmada. É isso que este teste guarda, junto com o ETag (recarregar não repuxa MB)
# e com a impossibilidade de escolher o arquivo pelo parâmetro.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"

C="$FIX/st"; mkdir -p "$C/var" "$C/enunciados"
T0=$(( $(date +%s) - 3600 ))
conf(){ { printf 'CONTEST_ID=st\nCONTEST_TYPE=icpc\nCONTEST_NAME=Prova\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$1" "$(( $1 + 18000 ))"
  printf 'PROBS=( x col#pa Alfa A col#pa x col#pb Beta B col#pb )\n'; } > "$C/conf"; }
conf "$T0"
for u in st.admin st.judge st.staff st.cstaff time01; do
  fx_user "$C" "$u" p "Nome $u"
  printf 'CONTEST=st\nLOGIN=%s\nUSERFULLNAME=X\nLOGINAT=1\n' "$u" > "$SESS/$u"
done
printf '<html><body><h1>Alfa</h1><p>SEGREDO-DO-ENUNCIADO</p></body></html>' > "$C/enunciados/col#pa.html"
printf '%%PDF-1.4\n1 0 obj\nSEGREDO-PDF\n' > "$C/enunciados/col#pb.pdf"

hit(){ env PATH_INFO="/contest/${1}" REQUEST_METHOD=GET QUERY_STRING="contest=st${3:+&$3}" \
  HTTP_AUTHORIZATION="Bearer ${2:-}" ${4:+HTTP_IF_NONE_MATCH=$4} \
  CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$FIX/run" bash "$ROUTER" </dev/null 2>/dev/null; }
st(){ OUT="$(hit statement "$1" "$2" "${3:-}")"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
code(){ printf '%s' "$OUT" | head -1 | tr -d '\r' | sed 's/^Status: //'; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: $(code)"; ((fail++)); fi; }

echo "== a lista diz QUE existe, e não manda o corpo =="
OUT="$(hit problems time01)"; L="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"
ck "A tem html, não tem pdf"     '[[ "$(jq -r ".problems[0]|.has_statement_html,.has_statement_pdf" <<<"$L" | paste -sd,)" == "true,false" ]]'
ck "B tem pdf, não tem html"     '[[ "$(jq -r ".problems[1]|.has_statement_html,.has_statement_pdf" <<<"$L" | paste -sd,)" == "false,true" ]]'
ck "nenhum corpo em base64"      '! grep -q "statement_html_b64\|statement_pdf_b64" <<<"$L"'
ck "e o corpo da lista é pequeno" '[[ ${#L} -lt 2000 ]]'

echo "== o competidor pega o enunciado =="
st time01 'problem=A&format=html'
ck "200 e o conteúdo certo"      '[[ "$(code)" == "200 OK" ]] && grep -q SEGREDO-DO-ENUNCIADO <<<"$BODY"'
ck "Content-Type de html"        '[[ "$OUT" == *"Content-Type: text/html"* ]]'
st time01 'problem=B&format=pdf'
ck "pdf: 200 e application/pdf"  '[[ "$(code)" == "200 OK" && "$OUT" == *"Content-Type: application/pdf"* ]]'
st time01 'problem=col%23pa&format=html'
ck "aceita o problem_id também"  'grep -q SEGREDO-DO-ENUNCIADO <<<"$BODY"'
st time01 'problem=A'
ck "sem format: cai em html"     'grep -q SEGREDO-DO-ENUNCIADO <<<"$BODY"'

echo "== ETag: recarregar não repuxa o enunciado =="
st time01 'problem=A&format=html'
ET="$(printf '%s' "$OUT" | awk -F': ' '/^ETag/{print $2}' | tr -d '\r')"
ck "manda ETag"                  '[[ -n "$ET" ]]'
ck "e Cache-Control private"     '[[ "$OUT" == *"Cache-Control: private"* ]]'
OUT="$(hit statement time01 'problem=A&format=html' "$ET")"
ck "If-None-Match => 304"        '[[ "$(code)" == "304 Not Modified" ]]'
ck "e 304 vem sem corpo"         '[[ -z "$(printf "%s" "$OUT" | awk "f{print} /^\r?\$/{f=1}")" ]]'
# enunciado corrigido no meio da prova: o ETag muda e o time recebe o novo
sleep 1; printf '<html><body>CORRIGIDO</body></html>' > "$C/enunciados/col#pa.html"
OUT="$(hit statement time01 'problem=A&format=html' "$ET")"
ck "enunciado novo NÃO dá 304"   '[[ "$(code)" == "200 OK" ]] && grep -q CORRIGIDO <<<"$OUT"'

echo "== GATE: o .staff NUNCA vê enunciado (nem que ele existe) =="
st st.staff 'problem=A&format=html'
ck "staff => 404"                '[[ "$(code)" == "404 Not Found" ]]'
ck "e sem o conteúdo"            '! grep -q CORRIGIDO <<<"$BODY"'
st st.cstaff 'problem=A&format=html'
ck "cstaff => 404"               '[[ "$(code)" == "404 Not Found" ]]'

echo "== GATE: antes do início, o competidor não pega (e o juiz pega) =="
conf "$(( $(date +%s) + 3600 ))"
st time01 'problem=A&format=html'
ck "pré-início => 404"           '[[ "$(code)" == "404 Not Found" ]]'
ck "nada do enunciado vaza"      '! grep -q CORRIGIDO <<<"$BODY"'
st st.judge 'problem=A&format=html'
ck "juiz pega antes do início"   '[[ "$(code)" == "200 OK" ]] && grep -q CORRIGIDO <<<"$BODY"'
st st.admin 'problem=A&format=html'
ck "admin também"                '[[ "$(code)" == "200 OK" ]]'
st '' 'problem=A&format=html'
ck "sem sessão => 401"           '[[ "$(code)" == 401* ]]'
conf "$T0"

echo "== o parâmetro NÃO escolhe arquivo (a chave sai do PROBS) =="
printf 'segredo do servidor\n' > "$FIX/fora.html"
for r in '../fora' '../../fora' '/etc/passwd' 'col%23pa/../../fora' 'Z'; do
  st time01 "problem=$r&format=html"
  ck "recusa '$r'"               '[[ "$(code)" == "404 Not Found" ]]'
done
st time01 'problem=A&format=sh'
ck "formato inválido => 400"     '[[ "$(code)" == "400 Bad Request" ]]'
st time01 'format=html'
ck "sem problem => 400"          '[[ "$(code)" == "400 Bad Request" ]]'
st time01 'problem=B&format=html'
ck "formato que não existe => 404" '[[ "$(code)" == "404 Not Found" ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
