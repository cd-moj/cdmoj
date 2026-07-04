#!/bin/bash
# Contest SUPER SECRETO (conf SECRET=1): fora das listagens públicas (home/arquivo/status),
# placar e visual (balloons/regions/teams-meta) exigem sessão DO contest; tela de login (basic)
# continua pública; settings marca/desmarca; export/mine preservam a visão do criador.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
T="$FIX/treino"; mkdir -p "$T/var/jsons" "$T/controle"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\n' > "$T/conf"
printf 'boss.admin:p:Boss\nregular:s:Regular\n' > "$T/passwd"
printf '{"threshold":0,"allow":["regular"],"deny":[]}' > "$T/var/contest-perms.json"
printf 'CONTEST=treino\nLOGIN=regular\nUSERFULLNAME=Regular\nLOGINAT=1\n' > "$SESS/reg"
printf '%s' '{"id":"bankprob","title":"Banco","tags":[],"statement_html_b64":"PGgxPm9pPC9oMT4="}' > "$T/var/jsons/bankprob.json"
printf '%s' '{"problems":[{"id":"bankprob","title":"Banco","owner":"x","collaborators":[],"public":true}]}' > "$T/var/problem-owners.json"
: > "$T/controle/history"
NOW="$(date +%s)"; FUT=$(( NOW + 100000 ))
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

# um contest SECRETO e um VISÍVEL (mesma janela aberta)
call /treino/contest-create/create POST "{\"id\":\"sec-c\",\"name\":\"Prova Secreta\",\"mode\":\"icpc\",\"secret\":true,\"start\":$((NOW-100)),\"end\":$FUT,\"problems\":[{\"bank_id\":\"bankprob\",\"name\":\"B\"}]}" reg
[[ "$(jq -r .contest_id <<<"$BODY")" == sec-c ]] || { echo "SETUP FAIL: $BODY"; exit 1; }
call /treino/contest-create/create POST "{\"id\":\"vis-c\",\"name\":\"Prova Visivel\",\"mode\":\"icpc\",\"start\":$((NOW-100)),\"end\":$FUT,\"problems\":[{\"bank_id\":\"bankprob\",\"name\":\"B\"}]}" reg
printf 'CONTEST=sec-c\nLOGIN=aluno1\nUSERFULLNAME=A\nLOGINAT=1\n' > "$SESS/sal"
printf 'CONTEST=sec-c\nLOGIN=regular.admin\nUSERFULLNAME=Adm\nLOGINAT=1\n' > "$SESS/sadm"
printf 'CONTEST=vis-c\nLOGIN=aluno2\nUSERFULLNAME=B\nLOGINAT=1\n' > "$SESS/valu"

echo "== criação com secret:true =="
ck "conf tem SECRET=1"          'grep -q "^SECRET=1" "$FIX/sec-c/conf"'
ck "visível NÃO tem SECRET"     '! grep -q "^SECRET=" "$FIX/vis-c/conf"'

echo "== listagens públicas =="
call /index/contests GET '' '' ''
ck "home não lista o secreto"   '[[ "$(jq -r "[.open[].id, .upcoming[].id, .closed.items[].id]|index(\"sec-c\")" <<<"$BODY")" == null ]]'
ck "home lista o visível"       '[[ "$(jq -r "[.open[].id]|index(\"vis-c\")" <<<"$BODY")" != null ]]'
printf '0:aluno1:bankprob:C:Not Answered Yet:0:s1\n' > "$FIX/sec-c/controle/history"
printf '0:aluno2:bankprob:C:Not Answered Yet:0:s2\n' > "$FIX/vis-c/controle/history"
call /index/status GET '' '' ''
ck "status não expõe o secreto" '[[ "$(jq -r "[.queue.lists[].contest]|index(\"sec-c\")" <<<"$BODY")" == null ]]'
ck "status lista o visível"     '[[ "$(jq -r "[.queue.lists[].contest]|index(\"vis-c\")" <<<"$BODY")" != null ]]'
ck "total conta os dois"        '[[ "$(jq -r .queue.total_pending <<<"$BODY")" == 2 ]]'

echo "== placar e visual exigem sessão do contest =="
for ep in score balloons regions teams-meta; do
  call "/contest/$ep" GET '' '' 'contest=sec-c'
  ck "$ep sem token 401"        '[[ "$OUT" == *"Status: 401"* ]]'
done
call /contest/score GET '' valu 'contest=sec-c'
ck "sessão de OUTRO contest 401" '[[ "$OUT" == *"Status: 401"* ]]'
call /contest/score GET '' sal 'contest=sec-c'
ck "aluno do contest vê o placar" '[[ "$OUT" == *"Status: 200"* ]]'
call /contest/balloons GET '' sal 'contest=sec-c'
ck "balloons com sessão 200"    '[[ "$OUT" == *"Status: 200"* ]]'
call /contest/score GET '' '' 'contest=vis-c'
ck "visível segue público"      '[[ "$OUT" == *"Status: 200"* ]]'

echo "== tela de login continua funcional =="
call /contest/basic GET '' '' 'contest=sec-c'
ck "basic público com secret:true" '[[ "$(jq -r .secret <<<"$BODY")" == true && "$(jq -r .contest_name <<<"$BODY")" == "Prova Secreta" ]]'

echo "== settings marca/desmarca =="
call /contest/admin/settings GET '' sadm 'contest=sec-c'
ck "settings GET secret:true"   '[[ "$(jq -r .secret <<<"$BODY")" == true ]]'
call /contest/admin/settings POST '{"secret":false}' sadm 'contest=sec-c'
ck "desmarcou"                  '[[ "$(jq -r .saved <<<"$BODY")" == true ]] && ! grep -q "^SECRET=" "$FIX/sec-c/conf"'
call /index/contests GET '' '' ''
ck "desmarcado volta à home"    '[[ "$(jq -r "[.open[].id]|index(\"sec-c\")" <<<"$BODY")" != null ]]'
call /contest/score GET '' '' 'contest=sec-c'
ck "placar volta a ser público" '[[ "$OUT" == *"Status: 200"* ]]'
call /contest/admin/settings POST '{"secret":true}' sadm 'contest=sec-c'
ck "marcou de novo"             'grep -q "^SECRET=1" "$FIX/sec-c/conf"'

echo "== criador continua vendo (mine/export) =="
call /treino/contest-create/mine GET '' reg ''
ck "mine lista o secreto"       '[[ "$(jq -r "[.contests[].id]|index(\"sec-c\")" <<<"$BODY")" != null ]]'
call /treino/contest-create/export GET '' reg 'id=sec-c'
ck "export carrega secret:true" '[[ "$(jq -r .secret <<<"$BODY")" == true ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
