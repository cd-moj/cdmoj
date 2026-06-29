#!/bin/bash
# Item 6: clarifications (perguntar/responder, público vs privado, papéis) e notícias do contest.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
C="$FIX/cl"; mkdir -p "$C/var"
printf 'CONTEST_ID=cl\nCONTEST_TYPE=icpc\n' > "$C/conf"
printf 'cl.admin:p:Admin\njdg.judge:p:Judge\nm.mon:p:Mon\nalice:a:Alice\nbob:b:Bob\n' > "$C/passwd"
for s in "adm cl.admin" "jdg jdg.judge" "mon m.mon" "alice alice" "bob bob"; do
  set -- $s; printf 'CONTEST=cl\nLOGIN=%s\nLOGINAT=1\n' "$2" > "$SESS/$1"; done
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-adm}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

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

echo "== notícias do contest =="
call /contest/admin/news POST '{"action":"add","title":"Início em 5min","text":"preparem-se"}' mon 'contest=cl'
ck "mon cria notícia"          '[[ "$(jq -r ".items|length" <<<"$BODY")" == 1 ]]'
call /contest/admin/news POST '{"action":"add","title":"x"}' alice 'contest=cl'
ck "regular não cria notícia 403" '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/news GET '' bob 'contest=cl'
ck "notícia aparece p/ todos"  '[[ "$(jq -r ".items[0].title" <<<"$BODY")" == "Início em 5min" ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
