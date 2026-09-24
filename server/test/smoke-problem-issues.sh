#!/bin/bash
# PROBLEM-ISSUES — issues por problema (lib/problem-issues.sh + /problems/issues), pedido da banca via
# Arthur Botelho (22/09/2026): "um sistema de issues, que devem ser resolvidas para o problema ficar ok".
# Garante: acesso = quem EDITA (não-membro e inexistente = o MESMO 404), o ciclo open/comment/close/
# reopen, os tetos, texto hostil fica TEXTO, corpo grande não passa por argv, o Painel vê a issue
# (open_issues, pending issues_open, needs_review) e as issues seguem o problema no move e somem no delete.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; PROBS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN" "$PROBS"' EXIT
source "$HERE/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" MOJ_PROBLEMS_DIR="$PROBS" TL_STORE_DIR="$RUN/tl" \
       CALIB_DIR="$RUN/calib" MOJ_JOBS_SYNC=1
mkdir -p "$RUN/tl" "$RUN/calib" "$FIX/treino/var"
NOW="$EPOCHSECONDS"; T="$FIX/treino"
printf 'CONTEST_ID=treino\nCONTEST_END=%s\n' "$((NOW+86400))" > "$T/conf"
echo '{"col":{"members":["autor","bruno"],"admins":["autor"],"public_allowed":true,"title":"Col"},
       "dst":{"members":["autor"],"admins":["autor"],"public_allowed":false,"title":"Dst"}}' > "$T/var/orgs.json"
P="$PROBS/col/pa"; mkdir -p "$P/sols/good" "$P/tests/input" "$P/docs"
printf 'x\n' > "$P/docs/enunciado.md"; printf 'int main(){}\n' > "$P/sols/good/sol.c"; printf '1\n' > "$P/tests/input/t1"
printf '{"owner":"autor","public":false,"display_title":"PA"}\n' > "$P/.moj-meta.json"
( cd "$P" && git init -q && git add -A && git -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm init )
jq -cn '{problems:[{id:"col#pa",owner:"autor",repo:"col",prob:"pa",title:"PA",public:false,collaborators:[],collections:[]}]}' \
  > "$T/var/problem-owners.json"
for u in autor bruno outro; do fx_user "$T" "$u" s "$u"
  printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino "$u" "$u" "$NOW" > "$SESS/tk-$u"; done

pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:300}"; ((fail++)); fi; }
req(){ # <método> <rota> <login> [query] [corpo]
  OUT="$(PATH_INFO="$2" REQUEST_METHOD="$1" QUERY_STRING="${4:-}" HTTP_AUTHORIZATION="Bearer tk-$3" bash "$ROUTER" <<<"${5:-}" 2>/dev/null)"
  STATUS="$(printf '%s' "$OUT" | sed -n 's/^Status: \([0-9]*\).*/\1/p' | head -1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
act(){ req POST /problems/issues "$1" "" "$2"; }

echo "== acesso: quem edita; o resto recebe o MESMO 404 =="
req GET /problems/issues autor "id=col%23pa"
ck "membro lê (vazio)"                           '[[ "$STATUS" == 200 && "$(jq -c "[.open, (.issues|length)]" <<<"$BODY")" == "[0,0]" ]]'
req GET /problems/issues outro "id=col%23pa"; A="$BODY"; SA="$STATUS"
req GET /problems/issues outro "id=col%23zz"; B="$BODY"
ck "não-membro = 404"                            '[[ "$SA" == 404 ]]'
ck "…byte a byte igual a problema inexistente"   '[[ "$A" == "$B" ]]'
act outro '{"id":"col#pa","action":"open","title":"x"}'
ck "não-membro não abre issue (404)"             '[[ "$STATUS" == 404 ]]'

echo "== ciclo =="
act autor '{"id":"col#pa","action":"open","title":"   "}'
ck "sem título = 400"                            '[[ "$STATUS" == 400 ]] && grep -q "título" <<<"$BODY"'
act autor '{"id":"col#pa","action":"open","title":"  Teste 7 fora do limite  ","body":"n=1296 mas o enunciado diz N <= 1000\n"}'
ck "abre a #1 (título aparado, corpo sem \\n final)" '[[ "$STATUS" == 200 && "$(jq -c "[.issue.n,.issue.title,.issue.state,.issue.by,.open]" <<<"$BODY")" == "[1,\"Teste 7 fora do limite\",\"open\",\"autor\",1]" && "$(jq -r .issue.body <<<"$BODY")" == "n=1296 mas o enunciado diz N <= 1000" ]]'
act autor '{"id":"col#pa","action":"open","title":"<script>alert(1)</script> & \"aspas\""}'
ck "abre a #2 com texto hostil guardado LITERAL" '[[ "$(jq -r .issue.title <<<"$BODY")" == "<script>alert(1)</script> & \"aspas\"" && "$(jq -r .issue.n <<<"$BODY")" == 2 ]]'
act bruno '{"id":"col#pa","action":"comment","n":1,"body":"conferi: é o t7"}'
ck "outro membro comenta"                        '[[ "$STATUS" == 200 && "$(jq -c "[.issue.comments[0].by, (.issue.comments|length)]" <<<"$BODY")" == "[\"bruno\",1]" ]]'
act bruno '{"id":"col#pa","action":"comment","n":1,"body":"  "}'
ck "comentário vazio = 400"                      '[[ "$STATUS" == 400 ]]'
act autor '{"id":"col#pa","action":"comment","n":99,"body":"x"}'
ck "issue inexistente = 404 issue_notfound"      '[[ "$STATUS" == 404 ]] && grep -q issue_notfound <<<"$BODY"'
act autor '{"id":"col#pa","action":"apagar","n":1}'
ck "ação desconhecida = 400"                     '[[ "$STATUS" == 400 ]]'
act autor '{"id":"col#pa","action":"close","n":1,"body":"corrigido: t7 regerado"}'
ck "fecha com comentário"                        '[[ "$STATUS" == 200 && "$(jq -c "[.issue.state,.issue.closed_by,(.issue.comments|length),.open]" <<<"$BODY")" == "[\"closed\",\"autor\",2,1]" ]]'
act autor '{"id":"col#pa","action":"close","n":1}'
ck "fechar de novo = 409"                        '[[ "$STATUS" == 409 ]]'
act bruno '{"id":"col#pa","action":"reopen","n":1}'
ck "reabre (closed_* limpos)"                    '[[ "$(jq -c "[.issue.state,.issue.closed_by,.open]" <<<"$BODY")" == "[\"open\",null,2]" ]]'
act autor '{"id":"col#pa","action":"close","n":1}'; act autor '{"id":"col#pa","action":"close","n":2}'
req GET /problems/issues bruno "id=col%23pa"
ck "lista: todas fechadas, open=0"               '[[ "$(jq -c "[.open, (.issues|length), ([.issues[].state]|unique)]" <<<"$BODY")" == "[0,2,[\"closed\"]]" ]]'
act autor '{"id":"col#pa","action":"open","title":"TL apertado p/ Python"}'
req GET /problems/issues bruno "id=col%23pa"
ck "lista: abertas primeiro"                     '[[ "$(jq -c "[.issues[0].n, .issues[0].state]" <<<"$BODY")" == "[3,\"open\"]" ]]'

echo "== tetos e corpo grande =="
BIG="$(head -c 150000 /dev/zero | tr '\0' 'a')"
act autor "$(jq -Rsc '{id:"col#pa",action:"comment",n:3,body:.}' <<<"$BIG")"   # o corpo por stdin (o TESTE também não usa argv)
ck "corpo > 20 KB = 400 (e nada de 'argument list too long')" '[[ "$STATUS" == 400 ]] && grep -q "longo demais" <<<"$BODY"'
act autor "$(jq -cn --arg t "$(head -c 201 /dev/zero | tr '\0' 't')" '{id:"col#pa",action:"open",title:$t}')"
ck "título > 200 = 400"                          '[[ "$STATUS" == 400 ]]'
OK19="$(head -c 19000 /dev/zero | tr '\0' 'b')"
act autor "$(jq -cn --arg b "$OK19" '{id:"col#pa",action:"comment",n:3,body:$b}')"
ck "corpo de 19 KB passa"                        '[[ "$STATUS" == 200 ]]'

echo "== Painel =="
SUM="$T/var/problem-issues-summary.json"
ck "sumário: 1 aberta"                           '[[ "$(jq -r ".[\"col#pa\"]" "$SUM")" == 1 ]]'
req GET /problems/status autor "id=col%23pa"
ROW="$(jq -c '.problems[0]' <<<"$BODY")"
ck "status: open_issues=1"                       '[[ "$(jq -r .open_issues <<<"$ROW")" == 1 ]]'
ck "status: pendência issues_open:1 e needs_review" 'jq -e "(.pending|index(\"issues_open:1\")) and (.review_reasons|index(\"issues_open:1\")) and .needs_review" <<<"$ROW" >/dev/null'
ck "status: contagem issues_open"                '[[ "$(jq -r .counts.issues_open <<<"$BODY")" == 1 ]]'
act autor '{"id":"col#pa","action":"close","n":3}'
req GET /problems/status autor "id=col%23pa"
ck "fechou a última: sai do sumário e das pendências" '[[ "$(jq -r "has(\"col#pa\")" "$SUM")" == false && "$(jq -r ".problems[0].open_issues" <<<"$BODY")" == 0 ]] && ! jq -e ".problems[0].pending|index(\"issues_open:1\")" <<<"$BODY" >/dev/null'
rm -f "$SUM"; act autor '{"id":"col#pa","action":"reopen","n":3}'
ck "sumário apagado: o upsert reconstrói a frio" '[[ "$(jq -r ".[\"col#pa\"]" "$SUM")" == 1 ]]'

echo "== move leva, delete apaga =="
req POST /problems/move autor "" '{"id":"col#pa","to_org":"dst"}'
ck "move ok"                                     '[[ "$STATUS" == 200 ]]'
ck "issues no id novo, fora do antigo"           '[[ -s "$T/var/problem-issues/dst/pa.json" && ! -e "$T/var/problem-issues/col/pa.json" ]]'
ck "sumário re-chaveado"                         '[[ "$(jq -c "[has(\"col#pa\"), .[\"dst#pa\"]]" "$SUM")" == "[false,1]" ]]'
jq -cn '{problems:[{id:"dst#pa",owner:"autor",repo:"dst",prob:"pa",title:"PA",public:false,collaborators:[],collections:[]}]}' > "$T/var/problem-owners.json"
req GET /problems/issues autor "id=dst%23pa"
ck "a lista vem pelo id novo"                    '[[ "$(jq -r ".issues|length" <<<"$BODY")" == 3 ]]'
req POST /problems/delete autor "" '{"id":"dst#pa","confirm":"dst#pa"}'
ck "delete ok"                                   '[[ "$STATUS" == 200 ]]'
ck "issues apagadas e fora do sumário"           '[[ ! -e "$T/var/problem-issues/dst/pa.json" && "$(jq -r "has(\"dst#pa\")" "$SUM")" == false ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
