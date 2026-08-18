#!/bin/bash
# smoke-contest-docs.sh — GATES dos documentos da prova (fase × papel × publicação):
# - caderno/times publicados: sede (.staff/.cstaff) vê ANTES do início; TIME só após o start;
# - info-sheet: publicado = visível (logística);
# - EDITORIAL: publicar exige contest_over_for_all (e o download do time idem — prorrogação
#   por sede segura o editorial); notícia anexando caderno antes do início é recusada.
# Os arquivos de doc são FAKES gravados direto (a geração real é coberta em produção).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN"
NOW="$(date +%s)"

C="$FIX/dprova"; mkdir -p "$C/docs" "$C/var"
conf(){ # <start> <end>
  { printf 'CONTEST_ID=dprova\nCONTEST_NAME="Prova Docs"\nCONTEST_TYPE=icpc\n'
    printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$1" "$2"
    printf 'PROBS=( cdmoj org#alfa Alfa A org#alfa )\n'; } > "$C/conf"
}
conf "$((NOW+3600))" "$((NOW+10800))"        # ANTES do início
fx_user "$C" time01 s3nha "Time 01"
fx_user "$C" dprova.admin adm "Admin"
fx_user "$C" sede.cstaff st "Chefe de Sede"
fx_user "$C" apoio.staff st "Apoio"

mkses(){ printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=1\n' dprova "$1" "$1" > "$SESS/$2"; }
mkses dprova.admin tok-adm; mkses time01 tok-time; mkses sede.cstaff tok-cstaff; mkses apoio.staff tok-staff

# docs fake + index.json (publish exige o arquivo; a listagem lê o índice)
for t in info-sheet contest times editorial; do printf '%%PDF-fake' > "$C/docs/$t.pt.pdf"; done
jq -cn --argjson at "$NOW" '[ {type:"info-sheet"},{type:"contest"},{type:"times"},{type:"editorial"}
  | . + {lang:"pt", html_bytes:0, pdf_bytes:9, generated_at:$at, by:"dprova.admin"} ]' > "$C/docs/index.json"

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="contest=dprova${5:+&$5}" \
    HTTP_AUTHORIZATION="Bearer ${4:-tok-adm}" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
adm(){ call /contest/admin/docs POST "$1" tok-adm; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${OUT:0:200}"; ((fail++)); fi; }
J(){ jq -r "$1" <<<"$BODY" 2>/dev/null; }

echo "== ANTES do início: sede vê publicado, time não =="
adm '{"action":"publish","type":"contest","lang":"pt"}'
ck "publica caderno (sem news)"       '[[ "$(J .ok)" == true ]]'
adm '{"action":"publish","type":"times","lang":"pt"}'
adm '{"action":"publish","type":"info-sheet","lang":"pt"}'
call /contest/doc GET '' tok-cstaff
ck "cstaff LISTA caderno pré-início"  '[[ "$(J "[.docs[].type]|index(\"contest\")")" != null ]]'
call /contest/doc GET '' tok-staff ''
ck "staff idem"                       '[[ "$(J "[.docs[].type]|index(\"times\")")" != null ]]'
call /contest/doc GET '' tok-time
ck "time NÃO lista caderno/times"     '[[ "$(J "[.docs[].type]|index(\"contest\")")" == null && "$(J "[.docs[].type]|index(\"times\")")" == null ]]'
ck "time LISTA info-sheet"            '[[ "$(J .success)" == true && "$(J "[.docs[].type]|index(\"info-sheet\")")" != null ]]'
call /contest/doc GET '' tok-time 'type=contest&lang=pt&fmt=pdf'
ck "time baixa caderno -> 404"        '[[ "$OUT" == *"Status: 404"* ]]'
call /contest/doc GET '' tok-cstaff 'type=contest&lang=pt&fmt=pdf'
ck "cstaff baixa caderno -> 200"      '[[ "$OUT" == *"Status: 200"* && "$OUT" == *PDF-fake* ]]'
call /contest/doc GET '' tok-time 'type=info-sheet&lang=pt&fmt=pdf'
ck "time baixa info-sheet -> 200"     '[[ "$OUT" == *"Status: 200"* ]]'
adm '{"action":"publish","type":"contest","lang":"pt","news":true}'
ck "caderno + news pré-início -> 409" '[[ "$OUT" == *"Status: 409"* && "$(J .error.code)" == news_before_start ]]'

echo "== EDITORIAL: só publica após o fim p/ todas as sedes =="
adm '{"action":"publish","type":"editorial","lang":"pt"}'
ck "pré-início -> 403"                '[[ "$OUT" == *"Status: 403"* && "$(J .error.code)" == contest_running ]]'
conf "$((NOW-7200))" "$((NOW+3600))"          # RODANDO
adm '{"action":"publish","type":"editorial","lang":"pt"}'
ck "rodando -> 403"                   '[[ "$OUT" == *"Status: 403"* ]]'
conf "$((NOW-7200))" "$((NOW-60))"            # ENCERRADO
printf '[{"regex":"^sedex","end":%s,"reason":"prorrogada"}]' "$((NOW+1800))" > "$C/time-overrides.json"
adm '{"action":"publish","type":"editorial","lang":"pt"}'
ck "sede prorrogada -> 403"           '[[ "$OUT" == *"Status: 403"* ]]'
rm -f "$C/time-overrides.json"
adm '{"action":"publish","type":"editorial","lang":"pt"}'
ck "encerrado p/ todos -> publica"    '[[ "$(J .ok)" == true ]]'
call /contest/doc GET '' tok-time 'type=editorial&lang=pt&fmt=pdf'
ck "time baixa editorial -> 200"      '[[ "$OUT" == *"Status: 200"* ]]'
printf '[{"regex":"^sedex","end":%s,"reason":"prorrogada"}]' "$((NOW+1800))" > "$C/time-overrides.json"
call /contest/doc GET '' tok-time 'type=editorial&lang=pt&fmt=pdf'
ck "prorrogou DEPOIS: time -> 404"    '[[ "$OUT" == *"Status: 404"* ]]'
call /contest/doc GET '' tok-cstaff 'type=editorial&lang=pt&fmt=pdf'
ck "sede segue baixando (publicado)"  '[[ "$OUT" == *"Status: 200"* ]]'
rm -f "$C/time-overrides.json"

echo "== COMEÇOU: time baixa caderno/times =="
conf "$((NOW-600))" "$((NOW+10800))"
call /contest/doc GET '' tok-time 'type=contest&lang=pt&fmt=pdf'
ck "pós-início: caderno -> 200"       '[[ "$OUT" == *"Status: 200"* ]]'
call /contest/doc GET '' tok-time
ck "listagem inclui caderno agora"    '[[ "$(J "[.docs[].type]|index(\"contest\")")" != null ]]'
call /contest/doc GET '' tok-time 'type=editorial&lang=pt&fmt=pdf'
ck "editorial em prova -> 404"        '[[ "$OUT" == *"Status: 404"* ]]'
adm '{"action":"publish","type":"contest","lang":"pt","news":true}'
ck "caderno + news pós-início ok"     '[[ "$(J .ok)" == true ]]'

echo "== ESPANHOL: 3º idioma de ponta a ponta =="
printf '%%PDF-fake' > "$C/docs/info-sheet.es.pdf"
adm '{"action":"publish","type":"info-sheet","lang":"es"}'
ck "publica em es"                    '[[ "$(J .ok)" == true ]]'
call /contest/doc GET '' tok-time 'type=info-sheet&lang=es&fmt=pdf'
ck "time baixa o es -> 200"           '[[ "$OUT" == *"Status: 200"* ]]'
call /contest/doc GET '' tok-time 'type=info-sheet&lang=de&fmt=pdf'
ck "idioma fora da lista -> 400"      '[[ "$OUT" == *"Status: 400"* && "$BODY" == *lang_invalid* ]]'

echo "== PDF ENVIADO: vence o gerado, e publica mesmo sem gerar =="
# PDF de verdade (o handler valida por file --mime-type; %PDF-fake não passa)
PDF64="$(printf '%%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%%%EOF\n' | base64 -w0)"
adm "{\"action\":\"upload\",\"type\":\"times\",\"lang\":\"es\",\"pdf_b64\":\"$PDF64\"}"
ck "upload aceito"                    '[[ "$(J .saved)" == true ]] && [[ -s "$C/docs/times.es.uploaded.pdf" ]]'
adm '{"action":"publish","type":"times","lang":"es"}'
ck "publica SEM ter gerado"           '[[ "$(J .ok)" == true ]]'
call /contest/doc GET '' tok-time 'type=times&lang=es&fmt=pdf'
ck "time recebe o ENVIADO"            '[[ "$OUT" == *"Status: 200"* ]] && [[ "$OUT" == *"1 0 obj"* ]]'
printf '%%PDF-gerado-diferente' > "$C/docs/times.es.pdf"
call /contest/doc GET '' tok-time 'type=times&lang=es&fmt=pdf'
ck "enviado VENCE o gerado"           '[[ "$OUT" == *"1 0 obj"* && "$OUT" != *"PDF-gerado-diferente"* ]]'
call /contest/admin/docs GET '' tok-adm
ck "listagem marca uploaded"          '[[ "$(J "[.docs[]|select(.type==\"times\" and .lang==\"es\")|.uploaded]|first")" == true ]]'
adm '{"action":"upload","type":"times","lang":"es","remove_upload":true}'
ck "voltar ao gerado"                 '[[ "$(J .removed)" == true ]]'
call /contest/doc GET '' tok-time 'type=times&lang=es&fmt=pdf'
ck "agora vem o gerado"               '[[ "$OUT" == *"PDF-gerado-diferente"* ]]'
adm "{\"action\":\"upload\",\"type\":\"times\",\"lang\":\"es\",\"pdf_b64\":\"$(printf 'nao sou pdf' | base64 -w0)\"}"
ck "não-PDF recusado"                 '[[ "$BODY" == *pdf_invalid* ]]'

echo "== resources.json: type/lang + gate de fase (a aba Contest agrupa por documento) =="
call /contest/resources GET '' tok-adm
ck "documento traz type e lang"       '[[ "$(J "[.items[]|select(.type==\"contest\" and .lang==\"pt\")]|length")" == 1 ]]'
conf "$((NOW+3600))" "$((NOW+10800))"        # volta p/ ANTES do início
call /contest/resources GET '' tok-time
ck "time não vê caderno pré-início"   '[[ "$(J "[.items[]|select(.type==\"contest\")]|length")" == 0 ]]'
ck "…mas vê o info-sheet"             '[[ "$(J "[.items[]|select(.type==\"info-sheet\")]|length")" -ge 1 ]]'
call /contest/resources GET '' tok-cstaff
ck "sede vê tudo (organização)"       '[[ "$(J "[.items[]|select(.type==\"contest\")]|length")" -ge 1 ]]'

echo; echo "passed=$pass failed=$fail"
(( fail == 0 ))
