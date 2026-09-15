#!/bin/bash
# ENUNCIADO EM VÁRIOS IDIOMAS (2026-09-15) — a cadeia inteira, do pacote ao competidor.
#
#   pacote  docs/enunciado.md (PT) + docs/enunciado.en.md + docs/notes/sample1.{md,en.md} + titles.en
#     -> gen-problem-json.sh   statement_langs + statements.en{title,html_b64}, rótulos por idioma,
#                              nota do sample2 CAI NO PT (fallback), <html lang>
#     -> /problems/source      translations.en; /problems/edit translations.es grava, translations.en:null
#                              apaga SEM tocar no PT; /problems/preview lang=es + kind:editorial
#     -> contest               STATEMENT_LANGS (admin E .cjudge definem, .judge não), /contest/problems
#                              statement_langs + default_statement_lang (LOCALE), /contest/statement?lang=
#                              (EN materializado do banco, ES cai no PT, xx=400, fora da lista=404),
#                              upload de HTML por idioma pelo admin, cache invalidado
#     -> validador             html_builds_en, secao_saida aceita Salida, aviso nota-sem-traducao
# Roda o renderizador REAL (pandoc): sem ele, SKIP.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
command -v pandoc >/dev/null 2>&1 || { echo "SKIP: sem pandoc (render do enunciado)"; exit 0; }
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; PROBS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN" "$PROBS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" MOJ_PROBLEMS_DIR="$PROBS" TL_STORE_DIR="$RUN/tl"
: "${MOJTOOLS_DIR:=$(cd "$ROOT/../../mojtools" && pwd)}"; export MOJTOOLS_DIR
mkdir -p "$RUN/tl" "$FIX/treino/var/jsons" "$FIX/treino/var/jsons-private"
NOW="$EPOCHSECONDS"

pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:220}"; ((fail++)); fi; }
call(){ # <path> <method> <sess> [query] [body] [extra-env]
  OUT="$(env PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${4:-}" HTTP_AUTHORIZATION="Bearer $3" \
    ${6:-} bash "$ROUTER" <<<"${5:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
code(){ printf '%s' "$OUT" | head -1 | tr -d '\r' | sed 's/^Status: //'; }
hdr(){ printf '%s' "$OUT" | awk -F': ' -v k="$1" 'tolower($1)==tolower(k){print $2}' | tr -d '\r'; }

# ---------- pacote PT+EN ----------
echo '{"col":{"members":["autor"],"admins":["autor"],"public_allowed":true,"title":"Col"}}' > "$FIX/treino/var/orgs.json"
fx_user "$FIX/treino" autor s "Autor"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino autor Autor "$NOW" > "$SESS/aut"
P="$PROBS/col/pa"; mkdir -p "$P/docs/notes" "$P/tests/input" "$P/tests/output" "$P/sols/good"
printf 'Leia N e imprima N.\n\n## Entrada\n\nUm inteiro.\n\n## Saída\n\nO mesmo inteiro.\n' > "$P/docs/enunciado.md"
printf 'Read N and print N.\n\n## Input\n\nOne integer.\n\n## Output\n\nThe same integer.\n' > "$P/docs/enunciado.en.md"
printf '3\n' > "$P/tests/input/sample1"; printf '3\n' > "$P/tests/output/sample1"
printf '7\n' > "$P/tests/input/sample2"; printf '7\n' > "$P/tests/output/sample2"
printf 'Nota PT do um.\n' > "$P/docs/notes/sample1.md"; printf 'EN note of one.\n' > "$P/docs/notes/sample1.en.md"
printf 'Nota PT do dois.\n' > "$P/docs/notes/sample2.md"
printf '# Ideia\n\nImprima.\n' > "$P/docs/solucao.md"; printf '# Idea\n\nPrint it.\n' > "$P/docs/solucao.en.md"
printf 'Autor\n' > "$P/author"; printf 'int main(){return 0;}\n' > "$P/sols/good/a.c"
printf '{"owner":"autor","public":true,"display_title":"Eco","titles":{"en":"Echo"}}' > "$P/.moj-meta.json"

echo "== gen-problem-json: um render por idioma =="
TREINO_JSONS="$FIX/treino/var/jsons" MOJ_TL_STORE="$RUN/tl" bash "$MOJTOOLS_DIR/gen-problem-json.sh" "$P" "col#pa" >/dev/null 2>&1
J="$FIX/treino/var/jsons/col#pa.json"; BODY="$(cat "$J" 2>/dev/null | head -c 300)"
ck "json publicado"                      '[[ -s "$J" ]]'
ck "statement_langs = [pt,en]"           '[[ "$(jq -c .statement_langs "$J")" == "[\"pt\",\"en\"]" ]]'
ck "statements.en.title = Echo"          '[[ "$(jq -r .statements.en.title "$J")" == Echo ]]'
EN="$(jq -r .statements.en.html_b64 "$J" | base64 -d)"; PT="$(jq -r .statement_html_b64 "$J" | base64 -d)"
ck "EN: texto e rótulos em inglês"       'grep -q "Read N and print N" <<<"$EN" && grep -q "<h2>Examples</h2>" <<<"$EN" && grep -q "<h3>Input</h3>" <<<"$EN" && grep -q "<h3>Output</h3>" <<<"$EN"'
ck "EN: nota do sample1 em EN"           'grep -q "EN note of one" <<<"$EN" && grep -q "<h3>Explanation</h3>" <<<"$EN"'
ck "EN: nota do sample2 cai no PT"       'grep -q "Nota PT do dois" <<<"$EN"'
ck "EN: <html lang=en> e h1 Echo"        'grep -q "<html lang=\"en\"" <<<"$EN" && grep -q "moj-title\">Echo" <<<"$EN"'
ck "PT: intacto (Exemplos/Entrada/Saída, lang pt-BR)" 'grep -q "<h2>Exemplos</h2>" <<<"$PT" && grep -q "<h3>Saída</h3>" <<<"$PT" && grep -q "<html lang=\"pt-BR\"" <<<"$PT" && ! grep -q "EN note" <<<"$PT"'
ck "editorial NÃO vai ao aluno"          '! grep -q "Print it" <<<"$EN" && ! grep -q "Imprima" <<<"$PT"'

echo "== validador: traduções são checks duros, nota sem tradução é aviso =="
VALIDATE_RUN_SOLS=0 TREINO_JSONS="$FIX/treino/var/jsons" bash "$MOJTOOLS_DIR/validate-problem.sh" "$P" "col#pa" >/dev/null 2>&1
V="$RUN/validation/col#pa.json"; BODY="$(cat "$V" 2>/dev/null | head -c 300)"
ck "validação ok"                        '[[ "$(jq -r .ok "$V")" == true ]]'
ck "checks html_builds_en/secao_*_en"    '[[ "$(jq -r "[.checks[]|select(.name|test(\"_en$\"))|.name]|length" "$V")" == 3 ]]'
ck "aviso nota-sem-traducao(sample2,en)" 'grep -q "nota-sem-traducao(sample2,en)" <<<"$(jq -r .render_warnings "$V")"'
printf 'Salida test.\n\n## Entrada\n\nx\n\n## Salida\n\ny\n' > "$P/docs/enunciado.es.md"
VALIDATE_RUN_SOLS=0 TREINO_JSONS="$FIX/treino/var/jsons" bash "$MOJTOOLS_DIR/validate-problem.sh" "$P" "col#pa" >/dev/null 2>&1
ck "## Salida passa na seção de saída ES" '[[ "$(jq -r ".checks[]|select(.name==\"secao_saida_es\")|.ok" "$V")" == true ]]'
rm -f "$P/docs/enunciado.es.md"
TREINO_JSONS="$FIX/treino/var/jsons" MOJ_TL_STORE="$RUN/tl" bash "$MOJTOOLS_DIR/gen-problem-json.sh" "$P" "col#pa" >/dev/null 2>&1

echo "== /problems/source: translations + titles =="
call /problems/source GET aut "id=col%23pa"
ck "200"                                 '[[ "$(code)" == "200 OK" ]]'
ck "translations.en com título/enunciado/editorial/nota" '[[ "$(jq -r ".translations.en | .title, (.enunciado_md|length>0), (.editorial_md|length>0), .notes.sample1" <<<"$BODY" | paste -sd,)" == "Echo,true,true,EN note of one." ]]'
ck "titles.en e statement_langs"         '[[ "$(jq -r ".titles.en, (.statement_langs|join(\",\"))" <<<"$BODY" | paste -sd,)" == "Echo,pt,en" ]]'
ck "PT segue nos campos de sempre"       'grep -q "Leia N" <<<"$(jq -r .enunciado_md <<<"$BODY")" && [[ "$(jq -r ".examples[0].explanation" <<<"$BODY")" == "Nota PT do um." ]]'

echo "== /problems/edit: translations.es grava; translations.en:null apaga só o EN =="
call /problems/edit POST aut "" '{"id":"col#pa","translations":{"es":{"title":"Eco ES","enunciado_md":"Lea N.\n\n## Entrada\n\nx\n\n## Salida\n\ny\n","notes":{"sample1":"Nota ES uno"}}}}'
ck "edit 200"                            '[[ "$(code)" == "200 OK" ]]'
ck "enunciado.es.md + nota ES + titles.es" '[[ -f "$P/docs/enunciado.es.md" && -f "$P/docs/notes/sample1.es.md" && "$(jq -r .titles.es "$P/.moj-meta.json")" == "Eco ES" ]]'
ck "PT e EN intactos"                    '[[ -f "$P/docs/enunciado.md" && -f "$P/docs/enunciado.en.md" && -f "$P/docs/notes/sample1.md" && -f "$P/docs/notes/sample1.en.md" && -f "$P/docs/notes/sample2.md" ]]'
call /problems/edit POST aut "" '{"id":"col#pa","translations":{"en":null},"examples":[{"input":"3\n","output":"3\n","explanation":"Nota PT do um v2"},{"input":"7\n","output":"7\n","explanation":"Nota PT do dois"}]}'
ck "en apagado (enunciado, editorial, nota, título)" '[[ ! -f "$P/docs/enunciado.en.md" && ! -f "$P/docs/solucao.en.md" && ! -f "$P/docs/notes/sample1.en.md" && "$(jq -r ".titles.en // \"-\"" "$P/.moj-meta.json")" == "-" ]]'
ck "ES ficou e PT foi regravado"         '[[ -f "$P/docs/enunciado.es.md" && -f "$P/docs/notes/sample1.es.md" && "$(cat "$P/docs/notes/sample1.md")" == "Nota PT do um v2" ]]'
# devolve o EN p/ o resto do teste
call /problems/edit POST aut "" '{"id":"col#pa","translations":{"en":{"title":"Echo","enunciado_md":"Read N and print N.\n\n## Input\n\nOne integer.\n\n## Output\n\nThe same integer.\n","editorial_md":"# Idea\n\nPrint it.","notes":{"sample1":"EN note of one."}}}}'
ck "EN de volta"                         '[[ -f "$P/docs/enunciado.en.md" && "$(jq -r .titles.en "$P/.moj-meta.json")" == Echo ]]'

echo "== /problems/preview: lang=es (rótulos) e kind:editorial (sem exemplos, sem h1) =="
call /problems/preview POST aut "" '{"enunciado_md":"Hola.\n\n## Entrada\n\nx\n\n## Salida\n\ny","title":"Hola Mundo","lang":"es","examples":[{"input":"1\n","output":"1\n","explanation":"nota"}]}'
H="$(jq -r .html_b64 <<<"$BODY" | base64 -d 2>/dev/null)"
ck "preview es: Ejemplos/Entrada/Salida/Explicación + <html lang=es>" 'grep -q "<h2>Ejemplos</h2>" <<<"$H" && grep -q "<h3>Salida</h3>" <<<"$H" && grep -q "<h3>Explicación</h3>" <<<"$H" && grep -q "<html lang=\"es\"" <<<"$H"'
ck "preview es: h3 (não h4) — gerador único" '! grep -q "<h4>" <<<"$H"'
call /problems/preview POST aut "" '{"kind":"editorial","markdown":"# Ideia\n\nSome tudo.","examples":[{"input":"1","output":"1"}],"title":"X"}'
H="$(jq -r .html_b64 <<<"$BODY" | base64 -d 2>/dev/null)"
ck "editorial: markdown renderizado, sem exemplos e sem h1 do título" 'grep -q "Some tudo" <<<"$H" && ! grep -q "<section class=\"moj-exemplos" <<<"$H" && ! grep -q "<h1 class=\"moj-title" <<<"$H" && [[ "$(jq -r .kind <<<"$BODY")" == editorial ]]'
call /problems/preview POST aut "" '{"enunciado_md":"x","lang":"fr"}'
ck "lang fora da lista = 400"            '[[ "$(code)" == "400 Bad Request" ]]'

# ---------- contest ----------
echo "== contest: STATEMENT_LANGS (admin e .cjudge definem; .judge não) =="
C="$FIX/sl"; mkdir -p "$C/var"
conf(){ { printf 'CONTEST_ID=sl\nCONTEST_TYPE=icpc\nCONTEST_NAME=Prova\nLOCALE=en\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW-3600))" "$((NOW+18000))"
  printf 'PROBS=( x col#pa Eco A col#pa )\n'; [[ -n "${1:-}" ]] && printf 'STATEMENT_LANGS=%s\n' "$1"; } > "$C/conf"; }
conf
for u in sl.admin sl.cjudge sl.judge time01; do
  fx_user "$C" "$u" p "Nome $u"
  printf 'CONTEST=sl\nLOGIN=%s\nUSERFULLNAME=X\nLOGINAT=1\n' "$u" > "$SESS/$u"
done
call /contest/problems GET time01 "contest=sl"
ck "sem conf: statement_langs [pt] e default pt" '[[ "$(jq -c ".statement_langs, .default_statement_lang, .problems[0].statement_langs" <<<"$BODY" | paste -sd" ")" == "[\"pt\"] \"pt\" [\"pt\"]" ]]'
ck "PT materializado do banco"           '[[ -s "$C/enunciados/col#pa.html" ]]'
call /contest/statement GET time01 "contest=sl&problem=A&lang=en"
ck "en fora da lista oferecida = 404"    '[[ "$(code)" == "404 Not Found" ]]'
call /contest/admin/statement-langs POST sl.judge "contest=sl" '{"langs":["pt","en"]}'
ck ".judge não define (403)"             '[[ "$(code)" == "403 Forbidden" ]]'
call /contest/admin/statement-langs POST sl.cjudge "contest=sl" '{"langs":["pt","en","es"]}'
ck ".cjudge define (200)"                '[[ "$(code)" == "200 OK" ]] && grep -q "STATEMENT_LANGS=pt\\\\ en\\\\ es" "$C/conf"'
ck "e a tradução EN foi materializada"   '[[ -s "$C/enunciados/col#pa.en.html" ]] && grep -q "Read N" "$C/enunciados/col#pa.en.html"'
call /contest/admin/statement-langs GET sl.admin "contest=sl"
ck "GET: langs, default=en (LOCALE), available A.en, sem A.es" '[[ "$(jq -c ".langs, .default, .available.A.en, (.available.A.es // false)" <<<"$BODY" | paste -sd" ")" == "[\"pt\",\"en\",\"es\"] \"en\" true false" ]]'
call /contest/admin/statement-langs POST sl.admin "contest=sl" '{"langs":["pt","fr"]}'
ck "idioma fora da allowlist = 422"      '[[ "$(code)" == "422 Unprocessable Entity" ]]'
call /contest/admin/statement-langs POST sl.admin "contest=sl" '{"langs":"pt"}'
ck "langs não-lista = 400"               '[[ "$(code)" == "400 Bad Request" ]]'

echo "== /contest/problems e /contest/statement por idioma =="
call /contest/problems GET time01 "contest=sl"
ck "lista: oferecidos [pt,en,es], default en, A tem [pt,en] (es sem arquivo)" '[[ "$(jq -c ".statement_langs, .default_statement_lang, .problems[0].statement_langs" <<<"$BODY" | paste -sd" ")" == "[\"pt\",\"en\",\"es\"] \"en\" [\"pt\",\"en\"]" ]]'
call /contest/statement GET time01 "contest=sl&problem=A&lang=en"
ck "lang=en: 200 com o texto EN e X-MOJ-Statement-Lang en" '[[ "$(code)" == "200 OK" ]] && grep -q "Read N and print N" <<<"$BODY" && [[ "$(hdr X-MOJ-Statement-Lang)" == en ]]'
call /contest/statement GET time01 "contest=sl&problem=A"
ck "sem lang: usa o default do contest (en)" 'grep -q "Read N and print N" <<<"$BODY"'
call /contest/statement GET time01 "contest=sl&problem=A&lang=pt"
ck "lang=pt: texto PT"                   'grep -q "Leia N e imprima N" <<<"$BODY" && [[ "$(hdr X-MOJ-Statement-Lang)" == pt ]]'
call /contest/statement GET time01 "contest=sl&problem=A&lang=es"
ck "lang=es (oferecido, sem arquivo): cai no PT, header pt" '[[ "$(code)" == "200 OK" ]] && grep -q "Leia N" <<<"$BODY" && [[ "$(hdr X-MOJ-Statement-Lang)" == pt ]]'
call /contest/statement GET time01 "contest=sl&problem=A&lang=xx"
ck "lang=xx: 400 lang_invalid"           '[[ "$(code)" == "400 Bad Request" ]] && grep -q lang_invalid <<<"$BODY"'
call /contest/statement GET sl.judge "contest=sl&problem=A&lang=en"
ck "juiz também pega o EN"               'grep -q "Read N and print N" <<<"$BODY"'

echo "== admin envia HTML PRÓPRIO em ES; refresh limpa todos os idiomas =="
call /contest/admin/problems POST sl.admin "contest=sl" "{\"action\":\"statement\",\"letter\":\"A\",\"lang\":\"es\",\"html_b64\":\"$(printf '<html><body><p>Lea N. PROPIO</p></body></html>' | base64 -w0)\"}"
ck "upload es: 200 e arquivo <skey>.es.html" '[[ "$(code)" == "200 OK" && -s "$C/enunciados/col#pa.es.html" && "$(jq -r .lang <<<"$BODY")" == es ]]'
call /contest/problems GET time01 "contest=sl"
ck "lista atualizada: A agora tem [pt,en,es]" '[[ "$(jq -c ".problems[0].statement_langs" <<<"$BODY")" == "[\"pt\",\"en\",\"es\"]" ]]'
call /contest/statement GET time01 "contest=sl&problem=A&lang=es"
ck "lang=es serve o próprio"             'grep -q "PROPIO" <<<"$BODY" && [[ "$(hdr X-MOJ-Statement-Lang)" == es ]]'
call /contest/admin/problems POST sl.admin "contest=sl" '{"action":"statement","letter":"A","lang":"zz","html_b64":"eA=="}'
ck "upload com lang inválido = 400"      '[[ "$(code)" == "400 Bad Request" ]]'
call /contest/admin/problems POST sl.admin "contest=sl" '{"action":"statement","letter":"A","lang":"es","remove_html":true}'
ck "remove_html es apaga só o ES"        '[[ ! -f "$C/enunciados/col#pa.es.html" && -f "$C/enunciados/col#pa.en.html" && -f "$C/enunciados/col#pa.html" ]]'
call /contest/admin/problems POST sl.admin "contest=sl" '{"action":"statement","letter":"A","refresh":true}'
ck "refresh apaga PT e traduções (volta a buscar do banco)" '[[ ! -f "$C/enunciados/col#pa.html" && ! -f "$C/enunciados/col#pa.en.html" ]]'
call /contest/problems GET time01 "contest=sl"
ck "…e a lista re-materializa PT e EN do banco" '[[ -s "$C/enunciados/col#pa.html" && -s "$C/enunciados/col#pa.en.html" && "$(jq -c ".problems[0].statement_langs" <<<"$BODY")" == "[\"pt\",\"en\"]" ]]'

echo "== tirar o idioma da lista fecha a porta na hora (cache invalidado) =="
call /contest/admin/statement-langs POST sl.admin "contest=sl" '{"langs":["pt"]}'
ck "só pt: conf sem STATEMENT_LANGS"     '! grep -q STATEMENT_LANGS "$C/conf"'
call /contest/problems GET time01 "contest=sl"
ck "lista: default pt, A só [pt]"        '[[ "$(jq -c ".default_statement_lang, .problems[0].statement_langs" <<<"$BODY" | paste -sd" ")" == "\"pt\" [\"pt\"]" ]]'
call /contest/statement GET time01 "contest=sl&problem=A&lang=en"
ck "lang=en agora 404 (arquivo existe, mas não é oferecido)" '[[ "$(code)" == "404 Not Found" ]]'

echo "== settings GET expõe statement_langs =="
conf "pt\\ en"
call /contest/admin/settings GET sl.admin "contest=sl"
ck "settings: statement_langs [pt,en], default en" '[[ "$(jq -c ".statement_langs, .default_statement_lang" <<<"$BODY" | paste -sd" ")" == "[\"pt\",\"en\"] \"en\"" ]]'

echo "== documentos: caderno/editorial no idioma (HTML, sem soffice) =="
export _DIR="$ROOT/api/v1" SESSION_LOGIN=sl.admin
source "$ROOT/api/v1/lib/common.sh" 2>/dev/null || true
source "$ROOT/api/v1/lib/contest-create.sh" 2>/dev/null || true
source "$ROOT/api/v1/lib/tl-store.sh" 2>/dev/null || true
source "$ROOT/api/v1/lib/contest-docs.sh"
HEN="$(_doc_html_contest sl en 2>/dev/null)"; HES="$(_doc_html_contest sl es 2>/dev/null)"; HPT="$(_doc_html_contest sl pt 2>/dev/null)"
ck "caderno EN: texto EN + título Echo"  'grep -q "Read N and print N" <<<"$HEN" && grep -q "Echo" <<<"$HEN"'
ck "caderno ES (sem tradução): cai no PT e título PT" 'grep -q "Leia N e imprima N" <<<"$HES" && ! grep -q "Read N" <<<"$HES"'
ck "caderno PT: PT"                      'grep -q "Leia N e imprima N" <<<"$HPT" && ! grep -q "Read N" <<<"$HPT"'
EEN="$(_doc_html_editorial sl en 2>/dev/null)"; EES="$(_doc_html_editorial sl es 2>/dev/null)"
ck "editorial EN usa solucao.en.md"      'grep -q "Print it" <<<"$EEN" && ! grep -q "Imprima" <<<"$EEN"'
ck "editorial ES cai no PT"              'grep -q "Imprima" <<<"$EES"'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
