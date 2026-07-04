#!/bin/bash
# Testa gerência de notícias (CRUD) + log de auditoria (notícias, deslogar, travar).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; ND="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$ND"' EXIT
T="$FIX/treino"; mkdir -p "$T/var"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\n' > "$T/conf"
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
fx_user "$T" boss.admin p "Boss Admin"
fx_user "$T" victim s "Victim"
fx_user "$T" regular s "Regular"
printf 'CONTEST=treino\nLOGIN=boss.admin\nUSERFULLNAME=Boss\nLOGINAT=1\n' > "$SESS/adm"
printf 'CONTEST=treino\nLOGIN=victim\nLOGINAT=1\nIP=1.1.1.1\n' > "$SESS/vic"
printf 'CONTEST=treino\nLOGIN=regular\nLOGINAT=1\n' > "$SESS/reg"

# call <path> <method> <body> [query]
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${4:-}" HTTP_AUTHORIZATION="Bearer adm" \
  CONTESTSDIR="$FIX" SESSIONDIR="$SESS" NEWSDIR="$ND" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:160}"; ((fail++)); fi; }

echo "== criar notícia =="
call /treino/admin/news POST '{"title":"Olá Mundo","summary":"um resumo","url":"http://x","body":"corpo"}'
KEY="$(jq -r .key <<<"$BODY")"
ck "created + key"     '[[ -n "$KEY" && "$KEY" != null ]]'
ck "arquivo criado"    '[[ -f "$ND/$KEY.json" ]]'

echo "== listar =="
call /treino/admin/news GET
ck "lista com 1"       '[[ "$(jq -r ".news|length" <<<"$BODY")" == 1 ]]'
ck "tem key e título"  '[[ "$(jq -r ".news[0].key" <<<"$BODY")" == "$KEY" && "$(jq -r ".news[0].title" <<<"$BODY")" == "Olá Mundo" ]]'

echo "== editar =="
call /treino/admin/news/update POST "{\"key\":\"$KEY\",\"title\":\"Editado\",\"summary\":\"novo resumo\"}"
ck "updated"           '[[ "$(jq -r .updated <<<"$BODY")" == "true" ]]'
ck "título mudou"      'grep -q "Editado" "$ND/$KEY.json"'
call /treino/admin/news/update POST '{"key":"naoexiste","title":"x"}'
ck "editar inexistente 404" '[[ "$OUT" == *"Status: 404"* ]]'

echo "== público: lista (key/is_local) + detalhe (markdown) + preview =="
call /treino/admin/news POST '{"title":"Post Local","summary":"resumo","url":"","body":"# Olá\n\n**negrito** e `code`"}'
LKEY="$(jq -r .key <<<"$BODY")"
call /treino/admin/news POST '{"title":"Externa","summary":"s","url":"https://x.com","body":""}'
EKEY="$(jq -r .key <<<"$BODY")"
call /index/news GET
ck "lista pública: all_news_url=/noticias/ e is_local=true (local)" '[[ "$(jq -r .all_news_url <<<"$BODY")" == "/noticias/" && "$(jq -r ".news[]|select(.key==\"$LKEY\")|.is_local" <<<"$BODY")" == true ]]'
ck "externa is_local=false" '[[ "$(jq -r ".news[]|select(.key==\"$EKEY\")|.is_local" <<<"$BODY")" == false ]]'
ck "lista pública é leve (sem body)" '[[ "$(jq -r ".news[0]|has(\"body\")" <<<"$BODY")" == false ]]'
call /index/news GET '' "id=$LKEY"
ck "detalhe renderiza markdown (<h1> + <strong>)" '[[ "$(jq -r .news.body_html_b64 <<<"$BODY" | base64 -d)" == *"<h1"* && "$(jq -r .news.body_html_b64 <<<"$BODY" | base64 -d)" == *"<strong>negrito</strong>"* ]]'
call /index/news GET '' 'id=../x'
ck "detalhe id inválido -> 400" '[[ "$OUT" == *"Status: 400"* ]]'
call /treino/admin/news/preview POST '{"body":"## Oi\n\n- x"}'
ck "preview do admin renderiza (<h2>)" '[[ "$(jq -r .html_b64 <<<"$BODY" | base64 -d)" == *"<h2"* ]]'
OUT="$(PATH_INFO=/treino/admin/news/preview REQUEST_METHOD=POST HTTP_AUTHORIZATION="Bearer reg" CONTESTSDIR="$FIX" SESSIONDIR="$SESS" NEWSDIR="$ND" bash "$ROUTER" <<<'{"body":"x"}' 2>&1)"
ck "preview sem admin -> 403" '[[ "$OUT" == *"Status: 403"* ]]'
call /treino/admin/news/delete POST "{\"key\":\"$LKEY\"}"
call /treino/admin/news/delete POST "{\"key\":\"$EKEY\"}"

echo "== deslogar e travar (gera auditoria) =="
call /treino/admin/logout-user POST '{"login":"victim"}'
call /treino/admin/lock-user   POST '{"login":"victim"}'

echo "== remover notícia =="
call /treino/admin/news/delete POST "{\"key\":\"$KEY\"}"
ck "deleted"           '[[ "$(jq -r .deleted <<<"$BODY")" == "true" ]]'
ck "arquivo removido"  '[[ ! -f "$ND/$KEY.json" ]]'

echo "== log de auditoria =="
call /treino/admin/audit-log GET
ck "registrou news-add"    '[[ "$(jq -r "[.entries[].action]|index(\"news-add\")" <<<"$BODY")" != null ]]'
ck "registrou news-edit"   '[[ "$(jq -r "[.entries[].action]|index(\"news-edit\")" <<<"$BODY")" != null ]]'
ck "registrou news-delete" '[[ "$(jq -r "[.entries[].action]|index(\"news-delete\")" <<<"$BODY")" != null ]]'
ck "registrou logout-user" '[[ "$(jq -r "[.entries[].action]|index(\"logout-user\")" <<<"$BODY")" != null ]]'
ck "registrou lock-user"   '[[ "$(jq -r "[.entries[].action]|index(\"lock-user\")" <<<"$BODY")" != null ]]'
ck "admin gravado"         '[[ "$(jq -r ".entries[0].admin" <<<"$BODY")" == "boss.admin" ]]'

echo "== não-admin barrado =="
OUT="$(PATH_INFO=/treino/admin/news REQUEST_METHOD=GET HTTP_AUTHORIZATION="Bearer reg" CONTESTSDIR="$FIX" SESSIONDIR="$SESS" NEWSDIR="$ND" bash "$ROUTER" 2>&1)"
ck "news (não-admin) 403"  '[[ "$OUT" == *"Status: 403"* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
