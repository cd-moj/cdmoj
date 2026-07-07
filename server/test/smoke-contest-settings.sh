#!/bin/bash
# Itens 8+9: settings do contest (tempos/login/toggles) e gestão de problemas (add/remove/reorder/rename).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
C="$FIX/sc"; mkdir -p "$C/var" "$C/enunciados" "$FIX/treino/var/jsons"
NOW="$(date +%s)"; FUT=$(( NOW + 100000 ))
{ printf 'CONTEST_ID=sc\nCONTEST_TYPE=icpc\nCONTEST_NAME=Antigo\nCONTEST_START=%s\nCONTEST_END=%s\n' 1 "$FUT"
  printf "PROBS=( cdmoj p/a 'Prob A' A 'p#a' cdmoj p/b 'Prob B' B 'p#b' )\n"; } > "$C/conf"
printf 'sc.admin:p:Admin\nalice:a:Alice\n' > "$C/passwd"
printf 'CONTEST=sc\nLOGIN=sc.admin\nLOGINAT=1\n' > "$SESS/adm"
printf 'CONTEST=sc\nLOGIN=alice\nLOGINAT=1\n' > "$SESS/usr"
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-adm}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

echo "== settings GET (defaults) =="
call /contest/admin/settings GET '' adm 'contest=sc'
ck "name Antigo"          '[[ "$(jq -r .name <<<"$BODY")" == "Antigo" ]]'
ck "show_editor default true" '[[ "$(jq -r .show_editor <<<"$BODY")" == "true" ]]'
ck "login_enabled default true" '[[ "$(jq -r .login_enabled <<<"$BODY")" == "true" ]]'

echo "== settings POST =="
call /contest/admin/settings POST "{\"name\":\"Novo Nome\",\"end\":$(( FUT+50 )),\"login_enabled\":false,\"show_editor\":false,\"show_log\":false,\"login_ua_substring\":\"MOJBOX\"}" adm 'contest=sc'
ck "salvou"               '[[ "$(jq -r .saved <<<"$BODY")" == "true" ]]'
ck "conf CONTEST_NAME"    'grep -q "^CONTEST_NAME=Novo" "$C/conf"'
ck "conf LOGIN_ENABLED=n" 'grep -q "^LOGIN_ENABLED=n" "$C/conf"'
ck "conf SHOWEDITOR=0"    'grep -q "^SHOWEDITOR=0" "$C/conf"'
ck "conf LOGIN_UA_SUBSTRING" 'grep -q "^LOGIN_UA_SUBSTRING=MOJBOX" "$C/conf"'
call /contest/admin/settings GET '' adm 'contest=sc'
ck "GET reflete login_enabled false/show_editor false" '[[ "$(jq -r .login_enabled <<<"$BODY")" == "false" && "$(jq -r .show_editor <<<"$BODY")" == "false" ]]'
ck "auditoria settings" 'grep -q "	settings	" "$C/var/admin-audit.log"'

echo "== penalidade ICPC (PENALTY_MINUTES / PENALTY_VERDICTS) =="
call /contest/admin/settings GET '' adm 'contest=sc'
ck "GET mode=icpc"            '[[ "$(jq -r .mode <<<"$BODY")" == "icpc" ]]'
ck "GET penalty_minutes=20"   '[[ "$(jq -r .penalty_minutes <<<"$BODY")" == "20" ]]'
ck "GET penalty_verdicts default (sem ce)" '[[ "$(jq -c .penalty_verdicts <<<"$BODY")" == "[\"wa\",\"tle\",\"mle\",\"rte\"]" ]]'
call /contest/admin/settings POST '{"penalty_minutes":10,"penalty_verdicts":["ce","wa"]}' adm 'contest=sc'
ck "salvou penalidade"        '[[ "$(jq -r .saved <<<"$BODY")" == "true" ]]'
ck "conf PENALTY_MINUTES=10"  'grep -q "^PENALTY_MINUTES=10$" "$C/conf"'
ck "conf PENALTY_VERDICTS wa+ce (ordem canônica)" 'grep -q "^PENALTY_VERDICTS=wa.\\?.ce$" "$C/conf"'
call /contest/admin/settings GET '' adm 'contest=sc'
ck "GET reflete 10 / [wa,ce]" '[[ "$(jq -r .penalty_minutes <<<"$BODY")" == "10" && "$(jq -c .penalty_verdicts <<<"$BODY")" == "[\"wa\",\"ce\"]" ]]'
call /contest/admin/settings POST '{"penalty_verdicts":[]}' adm 'contest=sc'
ck "lista vazia é válida (linha presente no conf)" 'grep -q "^PENALTY_VERDICTS=" "$C/conf"'
call /contest/admin/settings GET '' adm 'contest=sc'
ck "GET reflete lista vazia"  '[[ "$(jq -c .penalty_verdicts <<<"$BODY")" == "[]" ]]'
call /contest/admin/settings POST '{"penalty_minutes":20,"penalty_verdicts":["wa","tle","mle","rte"]}' adm 'contest=sc'
ck "defaults removem as vars" '! grep -q "^PENALTY_" "$C/conf"'
call /contest/admin/settings POST '{"penalty_verdicts":["xx"]}' adm 'contest=sc'
ck "código inválido -> 422"   '[[ "$OUT" == *"Status: 422"* ]]'
call /contest/admin/settings POST '{"penalty_minutes":"abc"}' adm 'contest=sc'
ck "minutos inválidos -> 422" '[[ "$OUT" == *"Status: 422"* ]]'

echo "== pool de juízes (CONTEST_JUDGES / problem-judges.json) =="
call /contest/admin/settings POST '{"judges":["cpu2","cpu1","cpu2"]}' adm 'contest=sc'
ck "salvou judges"            '[[ "$(jq -r .saved <<<"$BODY")" == "true" ]]'
ck "conf CONTEST_JUDGES (%q, unique)" 'grep -q "^CONTEST_JUDGES=cpu1\\\\ cpu2" "$C/conf"'
call /contest/admin/settings GET '' adm 'contest=sc'
ck "GET judges [cpu1,cpu2]"   '[[ "$(jq -c .judges <<<"$BODY")" == "[\"cpu1\",\"cpu2\"]" ]]'
call /contest/admin/settings POST '{"judges":["../x"]}' adm 'contest=sc'
ck "hostname inválido descartado (vira vazio = remove)" '! grep -q "^CONTEST_JUDGES=" "$C/conf"'
call /contest/admin/settings POST '{"judges":["cpu1"]}' adm 'contest=sc'
call /contest/admin/problems POST '{"action":"judges","letter":"A","judges":["orval"]}' adm 'contest=sc'
ck "judges por problema salvo" '[[ "$(jq -r .saved <<<"$BODY")" == "true" && "$(jq -c ".[\"p#a\"]" "$C/problem-judges.json")" == "[\"orval\"]" ]]'
call /contest/admin/problems GET '' adm 'contest=sc'
ck "GET problems traz judges"  '[[ "$(jq -c ".problems[0].judges" <<<"$BODY")" == "[\"orval\"]" ]]'
call /contest/admin/problems POST '{"action":"judges","letter":"A","judges":[]}' adm 'contest=sc'
ck "judges vazio limpa a entrada" '[[ "$(jq -c "keys" "$C/problem-judges.json")" == "[]" ]]'
call /contest/admin/settings POST '{"judges":[]}' adm 'contest=sc'
ck "judges [] remove do conf"  '! grep -q "^CONTEST_JUDGES=" "$C/conf"'

echo "== problemas GET/add/reorder/rename/remove =="
call /contest/admin/problems GET '' adm 'contest=sc'
ck "2 problemas (A,B)"    '[[ "$(jq -r ".problems|length" <<<"$BODY")" == 2 && "$(jq -r ".problems[0].letter" <<<"$BODY")" == "A" ]]'
call /contest/admin/problems POST '{"action":"add","problem":{"source":"cdmoj","problem_id":"p/c","name":"Prob C","letter":"C"}}' adm 'contest=sc'
ck "add -> 3 problemas"   '[[ "$(jq -r ".problems|length" <<<"$BODY")" == 3 ]]'
ck "conf PROBS tem 15"    '[[ "$( . "$C/conf"; echo ${#PROBS[@]} )" == 15 ]]'
call /contest/admin/problems POST '{"action":"reorder","order":["C","A","B"]}' adm 'contest=sc'
ck "reorder: 1º agora p#c, letra A" '[[ "$(jq -r ".problems[0].problem_id" <<<"$BODY")" == "p#c" && "$(jq -r ".problems[0].letter" <<<"$BODY")" == "A" ]]'
call /contest/admin/problems POST '{"action":"rename","letter":"A","name":"Renomeado"}' adm 'contest=sc'
ck "rename name"          '[[ "$(jq -r ".problems[0].name" <<<"$BODY")" == "Renomeado" ]]'
call /contest/admin/problems POST '{"action":"remove","letter":"C"}' adm 'contest=sc'
ck "remove -> 2 problemas" '[[ "$(jq -r ".problems|length" <<<"$BODY")" == 2 ]]'
ck "auditoria problems"   'grep -q "	problems-" "$C/var/admin-audit.log"'

echo "== proteção =="
call /contest/admin/settings POST '{"name":"x"}' usr 'contest=sc'
ck "não-admin 403"        '[[ "$OUT" == *"Status: 403"* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
