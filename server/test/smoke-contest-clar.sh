#!/bin/bash
# Item 6: clarifications (perguntar/responder, público vs privado, papéis) e notícias do contest.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
C="$FIX/cl"; mkdir -p "$C/var"
printf 'CONTEST_ID=cl\nCONTEST_TYPE=icpc\n' > "$C/conf"
fx_user "$C" cl.admin  p Admin
fx_user "$C" jdg.judge p Judge
fx_user "$C" jd2.judge p "Judge Two"
fx_user "$C" ch.cjudge p Chief
fx_user "$C" m.mon     p Mon
fx_user "$C" alice     a Alice
fx_user "$C" bob       b Bob
fx_user "$C" sala.staff s Sala
for s in "adm cl.admin" "jdg jdg.judge" "jd2 jd2.judge" "ch ch.cjudge" "mon m.mon" "alice alice" "bob bob" "sala sala.staff"; do
  set -- $s; printf 'CONTEST=cl\nLOGIN=%s\nLOGINAT=1\n' "$2" > "$SESS/$1"; done
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-adm}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

echo "== perguntar: só DURANTE a prova (time/.mon); staff nunca; juiz/admin sempre =="
NOW="$EPOCHSECONDS"
printf 'CONTEST_ID=cl\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW+3600))" "$((NOW+7200))" > "$C/conf"
call /contest/clarification-ask POST '{"question":"cedo"}' alice 'contest=cl'
ck "antes do início: time -> 403 contest_not_started" '[[ "$OUT" == *"Status: 403"* && "$(jq -r .error.code <<<"$BODY")" == contest_not_started ]]'
call /contest/clarification-ask POST '{"question":"cedo"}' mon 'contest=cl'
ck "antes do início: .mon -> 403"       '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/clarification-ask POST '{"question":"cedo"}' jdg 'contest=cl'
ck "juiz pergunta antes do início"      '[[ "$(jq -r .asked <<<"$BODY")" == true ]]'
rm -f "$C"/clarifications/*.json
printf 'CONTEST_ID=cl\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW-7200))" "$((NOW-3600))" > "$C/conf"
call /contest/clarification-ask POST '{"question":"tarde"}' alice 'contest=cl'
ck "depois do fim: time -> 403 contest_ended" '[[ "$OUT" == *"Status: 403"* && "$(jq -r .error.code <<<"$BODY")" == contest_ended ]]'
printf '[{"regex":"^alice$","end":%s,"reason":"sede prorrogada"}]' "$((NOW+1800))" > "$C/time-overrides.json"
call /contest/clarification-ask POST '{"question":"prorrogada"}' alice 'contest=cl'
ck "sede prorrogada segue perguntando"  '[[ "$(jq -r .asked <<<"$BODY")" == true ]]'
rm -f "$C/time-overrides.json" "$C"/clarifications/*.json
printf 'CONTEST_ID=cl\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW-3600))" "$((NOW+3600))" > "$C/conf"
call /contest/clarification-ask POST '{"question":"staff"}' sala 'contest=cl'
ck "staff nunca pergunta -> 403 role_forbidden" '[[ "$OUT" == *"Status: 403"* && "$(jq -r .error.code <<<"$BODY")" == role_forbidden ]]'

echo "== perguntar =="
call /contest/clarification-ask POST '{"problem":"A","question":"Como ler a entrada?"}' alice 'contest=cl'
Q1="$(jq -r .id <<<"$BODY")"; ck "alice perguntou (Q1)" '[[ -n "$Q1" && "$Q1" != null ]]'
call /contest/clarification-ask POST '{"question":"Tem ar condicionado?"}' bob 'contest=cl'
Q2="$(jq -r .id <<<"$BODY")"; ck "bob perguntou geral (Q2)" '[[ -n "$Q2" && "$Q2" != null ]]'

echo "== visibilidade inicial =="
call /contest/clarifications GET '' alice 'contest=cl'
# asker é anonimizado p/ todos (sem .login); o próprio asker é marcado com .mine=true
ck "alice vê só a própria (1)" '[[ "$(jq -r ".clarifications|length" <<<"$BODY")" == 1 && "$(jq -r ".clarifications[0].mine" <<<"$BODY")" == "true" && "$(jq -r ".clarifications[0]|has(\"login\")" <<<"$BODY")" == "false" ]]'
ck "alice can_answer false"    '[[ "$(jq -r .can_answer <<<"$BODY")" == false ]]'
call /contest/clarifications GET '' adm 'contest=cl'
ck "admin vê todas (2) + can_answer" '[[ "$(jq -r ".clarifications|length" <<<"$BODY")" == 2 && "$(jq -r .can_answer <<<"$BODY")" == true ]]'
ck "admin: can_edit/is_chief true, me"  '[[ "$(jq -r .can_edit <<<"$BODY")" == true && "$(jq -r .is_chief <<<"$BODY")" == true && "$(jq -r .me <<<"$BODY")" == cl.admin ]]'
ck "admin vê login + nome de quem perguntou" '[[ "$(jq -r "[.clarifications[]|select(.id==\"$Q1\")][0] | .login + \"/\" + .asker_name" <<<"$BODY")" == "alice/Alice" ]]'
call /contest/clarifications GET '' ch 'contest=cl'
ck "chefe vê login + nome; can_edit"    '[[ "$(jq -r "[.clarifications[]|select(.id==\"$Q2\")][0].login" <<<"$BODY")" == bob && "$(jq -r .can_edit <<<"$BODY")" == true ]]'
call /contest/clarifications GET '' jdg 'contest=cl'
ck "juiz comum NÃO vê login nem asker_name; can_edit false" '[[ "$(jq -r ".clarifications[0]|has(\"login\") or has(\"asker_name\")" <<<"$BODY")" == false && "$(jq -r .can_edit <<<"$BODY")" == false && "$(jq -r .is_chief <<<"$BODY")" == false ]]'
call /contest/clarifications GET '' mon 'contest=cl'
ck "monitor NÃO vê login"               '[[ "$(jq -r ".clarifications[0]|has(\"login\")" <<<"$BODY")" == false ]]'

echo "== reserva: ninguém pega por cima; chefe/admin só liberam com force =="
call /contest/clarification-claim POST "{\"id\":\"$Q1\",\"action\":\"claim\"}" jdg 'contest=cl'
ck "jdg reservou Q1"                    '[[ "$(jq -r .claimed <<<"$BODY")" == true ]]'
call /contest/clarification-claim POST "{\"id\":\"$Q1\",\"action\":\"claim\"}" jd2 'contest=cl'
ck "jd2 não reserva Q1 (409 clar_claimed)" '[[ "$OUT" == *"Status: 409"* && "$(jq -r .error.code <<<"$BODY")" == clar_claimed ]]'
call /contest/clarification-claim POST "{\"id\":\"$Q1\",\"action\":\"claim\"}" ch 'contest=cl'
ck "chefe também não reserva por cima (409)" '[[ "$OUT" == *"Status: 409"* && "$(jq -r .error.code <<<"$BODY")" == clar_claimed ]]'
call /contest/clarification-answer POST "{\"id\":\"$Q1\",\"answer\":\"x\"}" ch 'contest=cl'
ck "chefe não responde por cima da reserva (409)" '[[ "$OUT" == *"Status: 409"* && "$(jq -r .error.code <<<"$BODY")" == clar_claimed ]]'
call /contest/clarification-claim POST "{\"id\":\"$Q1\",\"action\":\"release\"}" ch 'contest=cl'
ck "chefe release SEM force = 409"      '[[ "$OUT" == *"Status: 409"* && "$(jq -r .error.code <<<"$BODY")" == clar_claimed ]]'
call /contest/clarification-claim POST "{\"id\":\"$Q1\",\"action\":\"release\",\"force\":true}" jd2 'contest=cl'
ck "juiz comum com force = 409 (não é chefe)" '[[ "$OUT" == *"Status: 409"* ]]'
call /contest/clarification-claim POST "{\"id\":\"$Q1\",\"action\":\"release\",\"force\":true}" ch 'contest=cl'
ck "chefe release COM force libera + forced_from" '[[ "$(jq -r .released <<<"$BODY")" == true && "$(jq -r .forced_from <<<"$BODY")" == jdg.judge ]]'
ck "audit clar-release forced_from"     'grep -q "	clar-release	id=$Q1 by=ch.cjudge forced_from=jdg.judge" "$C/var/admin-audit.log"'
call /contest/clarification-claim POST "{\"id\":\"$Q1\",\"action\":\"claim\"}" jd2 'contest=cl'
ck "jd2 reserva depois da liberação"    '[[ "$(jq -r .claimed <<<"$BODY")" == true ]]'
call /contest/clarification-claim POST "{\"id\":\"$Q1\",\"action\":\"release\"}" jd2 'contest=cl'
ck "jd2 libera a própria (sem force)"   '[[ "$(jq -r .released <<<"$BODY")" == true ]]'

echo "== responder (judge pública / mon privada) =="
call /contest/clarification-answer POST "{\"id\":\"$Q1\",\"answer\":\"Leia via stdin.\",\"public\":true}" jdg 'contest=cl'
ck "judge respondeu Q1 (pública)" '[[ "$(jq -r .answered <<<"$BODY")" == "true" ]]'
call /contest/clarification-answer POST "{\"id\":\"$Q2\",\"answer\":\"Sim.\",\"public\":false}" mon 'contest=cl'
ck "mon respondeu Q2 (privada)"   '[[ "$(jq -r .answered <<<"$BODY")" == "true" ]]'

echo "== visibilidade pós-resposta =="
call /contest/clarifications GET '' alice 'contest=cl'
ck "alice vê Q1 respondida"   '[[ "$(jq -r "[.clarifications[]|select(.id==\"$Q1\")][0].answer" <<<"$BODY")" == "Leia via stdin." ]]'
ck "alice NÃO vê Q2 privada"  '[[ "$(jq -r "[.clarifications[]|select(.id==\"$Q2\")]|length" <<<"$BODY")" == 0 ]]'
call /contest/clarifications GET '' bob 'contest=cl'
ck "bob vê sua Q2 respondida" '[[ "$(jq -r "[.clarifications[]|select(.id==\"$Q2\")][0].answer" <<<"$BODY")" == "Sim." ]]'

echo "== proteções =="
call /contest/clarification-answer POST "{\"id\":\"$Q1\",\"answer\":\"x\"}" alice 'contest=cl'
ck "regular não responde 403"  '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/clarification-answer POST "{\"id\":\"$Q1\",\"answer\":\"outra\"}" jd2 'contest=cl'
ck "juiz não edita respondida (409 already_answered)" '[[ "$OUT" == *"Status: 409"* && "$(jq -r .error.code <<<"$BODY")" == already_answered ]]'
call /contest/clarification-answer POST "{\"id\":\"$Q1\",\"answer\":\"Leia via stdin (editado).\",\"public\":true}" adm 'contest=cl'
ck "ADMIN edita respondida (edited:true)" '[[ "$(jq -r .edited <<<"$BODY")" == true ]]'

echo "== aviso oficial: assunto opcional; quebra de linha preservada =="
call /contest/clarification-broadcast POST '{"answer":"Linha 1\nLinha 2"}' jdg 'contest=cl'
ck "aviso só com texto (sem assunto) = ok" '[[ "$(jq -r .broadcast <<<"$BODY")" == true ]]'
B1="$(jq -r .id <<<"$BODY")"
call /contest/clarification-broadcast POST '{"question":"Errata do B"}' jdg 'contest=cl'
ck "aviso sem texto = 422 answer_missing" '[[ "$OUT" == *"Status: 422"* && "$(jq -r .error.code <<<"$BODY")" == answer_missing ]]'
call /contest/clarifications GET '' alice 'contest=cl'
ck "competidor vê o aviso com \\n intacto e question vazia" '[[ "$(jq -r "[.clarifications[]|select(.id==\"$B1\")][0].answer | contains(\"\\n\")" <<<"$BODY")" == true && "$(jq -r "[.clarifications[]|select(.id==\"$B1\")][0].question" <<<"$BODY")" == "" ]]'

echo "== reserva expira (CLAR_TTL) =="
call /contest/clarification-ask POST '{"question":"Q3"}' bob 'contest=cl'
Q3="$(jq -r .id <<<"$BODY")"
OUT="$(PATH_INFO=/contest/clarification-claim REQUEST_METHOD=POST QUERY_STRING='contest=cl' HTTP_AUTHORIZATION="Bearer jdg" CLAR_TTL=1 \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"{\"id\":\"$Q3\",\"action\":\"claim\"}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"
ck "jdg reservou Q3 com TTL 1s"          '[[ "$(jq -r .claimed <<<"$BODY")" == true ]]'
sleep 2
call /contest/clarifications GET '' jd2 'contest=cl'
ck "reserva expirada some na leitura"    '[[ "$(jq -r "[.clarifications[]|select(.id==\"$Q3\")][0].answer_claim" <<<"$BODY")" == null ]]'
call /contest/clarification-claim POST "{\"id\":\"$Q3\",\"action\":\"claim\"}" jd2 'contest=cl'
ck "jd2 reserva Q3 depois do TTL"        '[[ "$(jq -r .claimed <<<"$BODY")" == true ]]'

echo "== notícias do contest =="
call /contest/admin/news POST '{"action":"add","title":"Início em 5min","text":"preparem-se"}' mon 'contest=cl'
ck "mon cria notícia"          '[[ "$(jq -r ".items|length" <<<"$BODY")" == 1 ]]'
call /contest/admin/news POST '{"action":"add","title":"x"}' alice 'contest=cl'
ck "regular não cria notícia 403" '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/news GET '' bob 'contest=cl'
ck "notícia aparece p/ todos"  '[[ "$(jq -r ".items[0].title" <<<"$BODY")" == "Início em 5min" ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
