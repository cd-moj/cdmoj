#!/bin/bash
# smoke-contest-priority.sh — PRIORIDADE no julgamento EDITÁVEL e AUDITADA; Super só do SUPER-ADMIN do treino
# (01/10/2026, pedido do Ribas). Antes a prioridade só se escolhia na criação (padrão lista-publica) e qualquer
# `.admin` dava Super — que passa na frente de toda fila, inclusive das provas dos outros. Afirma:
#   • Central › Regras (/contest/admin/settings): GET diz priority/priority_set/priority_locked; o admin do contest
#     muda entre lista-publica/lista-privada/prova; Super nunca (403 priority_forbidden); contest em Super fica
#     travado p/ ele (403 priority_locked) sem impedir o resto das Regras; valor inválido 422; mesma = nada auditado;
#   • /treino/admin/contest-priority: só super-admin (SUPERADMINS do conf do treino) — .admin comum e aluno 403;
#     dá e tira Super; contest inexistente 404;
#   • toda mudança vai à auditoria do contest (`priority`) E à trilha central do treino (`contest-priority`), com
#     de/para/via e quem;
#   • criação: Super só p/ super-admin (o `.admin` comum leva 403) e a prioridade de nascimento entra na trilha;
#     duplicar um contest Super sem ser super-admin nasce Prova (não 403);
#   • o painel do treino (/treino/admin/contests) devolve a prioridade de cada contest.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS"
NOW="$EPOCHSECONDS"; FUT=$(( NOW + 100000 ))
T="$FIX/treino"; mkdir -p "$T/var/jsons"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=treino\nSUPERADMINS=%q\n' "boss.admin" > "$T/conf"
fx_user "$T" boss.admin p "Boss"; fx_user "$T" prof.admin p "Prof"; fx_user "$T" aluno p "Aluno"
for u in boss.admin prof.admin aluno; do printf 'CONTEST=treino\nLOGIN=%s\nUSERFULLNAME=%s\nLOGINAT=1\n' "$u" "$u" > "$SESS/t-$u"; done
fx_owners_index "$FIX"
# contest de prova criado pela interface (dono prof.admin), SEM prioridade definida
C="$FIX/cp"; mkdir -p "$C/var" "$C/enunciados"
{ printf 'CONTEST_ID=cp\nCONTEST_NAME=Prova\nCONTEST_TYPE=icpc\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW-3600))" "$FUT"
  printf "PROBS=( x col#pa Alfa A col#pa )\n"; } > "$C/conf"
printf 'prof.admin\n' > "$C/owner"; printf 'prof.admin\t%s\ticpc\n' "$NOW" > "$C/created-by"
fx_user "$C" cp.admin p "Admin"
printf 'CONTEST=cp\nLOGIN=cp.admin\nUSERFULLNAME=Admin\nLOGINAT=1\n' > "$SESS/c-adm"
call(){ # <path> <method> <body> <token> [query]
  local o; o="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer $4" bash "$ROUTER" <<<"$3" 2>/dev/null)"
  STATUS="$(printf '%s' "$o" | sed -n 's/^Status: \([0-9]*\).*/\1/p' | head -1)"; STATUS="${STATUS:-200}"
  BODY="$(printf '%s' "$o" | awk 'f{print} /^\r?$/{f=1}')"; }
regras(){ call /contest/admin/settings "${2:-POST}" "$1" c-adm "contest=cp"; }
prio(){ local v; v="$(grep -m1 '^CONTEST_PRIORITY=' "$FIX/$1/conf" | cut -d= -f2)"; printf '%s' "${v:-}"; }
aud(){ grep -c "$2" "$FIX/$1/var/admin-audit.log" 2>/dev/null || true; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: $STATUS ${BODY:0:220}"; ((fail++)); fi; }

echo "== Regras (admin do contest) =="
regras '' GET
ck "GET: lista-publica, não definida, destravada"   '[[ "$(jq -c "[.priority,.priority_set,.priority_locked]" <<<"$BODY")" == "[\"lista-publica\",false,false]" ]]'
regras '{"priority":"prova"}'
ck "muda p/ prova"                                  '[[ "$STATUS" == 200 && "$(prio cp)" == prova ]] && jq -e ".changed|index(\"CONTEST_PRIORITY=prova\")" <<<"$BODY" >/dev/null'
ck "auditado no contest: de/para/via e quem"        'grep -qP "\tcp\.admin\tpriority\tde=não-definida para=prova via=regras$" "$C/var/admin-audit.log"'
ck "e na trilha central do treino"                  'grep -qP "\tcp\.admin\tcontest-priority\tcontest=cp de=não-definida para=prova via=regras$" "$T/var/admin-audit.log"'
n1="$(aud cp 'priority')"; regras '{"priority":"prova"}'
ck "mesma prioridade: 200 e nada auditado"          '[[ "$STATUS" == 200 && "$(aud cp priority)" == "$n1" ]]'
regras '{"priority":"super"}'
ck "Super pelas Regras: 403 priority_forbidden"     '[[ "$STATUS" == 403 && "$(jq -r .error.code <<<"$BODY")" == priority_forbidden && "$(prio cp)" == prova ]]'
regras '{"priority":"urgente"}'
ck "valor inválido: 422"                            '[[ "$STATUS" == 422 && "$(jq -r .error.code <<<"$BODY")" == priority_invalid ]]'
regras '{"priority":"lista-privada","score_anon":true}'
ck "junto com outra opção, as duas gravam"          '[[ "$STATUS" == 200 && "$(prio cp)" == lista-privada ]] && grep -q "^SCORE_ANON=1" "$C/conf"'

echo "== Painel do treino (super-admin) =="
call /treino/admin/contest-priority POST '{"contest":"cp","priority":"super"}' t-prof.admin
ck ".admin comum: 403"                              '[[ "$STATUS" == 403 && "$(jq -r .error.code <<<"$BODY")" == superadmin_required && "$(prio cp)" == lista-privada ]]'
call /treino/admin/contest-priority POST '{"contest":"cp","priority":"super"}' t-aluno
ck "aluno: 403"                                     '[[ "$STATUS" == 403 ]]'
call /treino/admin/contest-priority POST '{"contest":"cp","priority":"super"}' t-boss.admin
ck "super-admin dá Super"                           '[[ "$STATUS" == 200 && "$(prio cp)" == super && "$(jq -c "[.previous,.changed]" <<<"$BODY")" == "[\"lista-privada\",true]" ]]'
ck "auditado (contest e treino), via=painel-treino" 'grep -qP "\tboss\.admin\tpriority\tde=lista-privada para=super via=painel-treino$" "$C/var/admin-audit.log" && grep -qP "\tboss\.admin\tcontest-priority\tcontest=cp de=lista-privada para=super via=painel-treino$" "$T/var/admin-audit.log"'
regras '' GET
ck "Regras: GET diz travada"                        '[[ "$(jq -c "[.priority,.priority_locked]" <<<"$BODY")" == "[\"super\",true]" ]]'
regras '{"priority":"prova"}'
ck "admin do contest não tira Super (403 priority_locked)" '[[ "$STATUS" == 403 && "$(jq -r .error.code <<<"$BODY")" == priority_locked && "$(prio cp)" == super ]]'
regras '{"score_anon":false}'
ck "as outras Regras seguem salvando"               '[[ "$STATUS" == 200 ]] && ! grep -q "^SCORE_ANON=1" "$C/conf"'
call /treino/admin/contest-priority POST '{"contest":"naoexiste","priority":"prova"}' t-boss.admin
ck "contest inexistente: 404"                       '[[ "$STATUS" == 404 ]]'
call /treino/admin/contest-priority POST '{"contest":"cp","priority":"turbo"}' t-boss.admin
ck "prioridade inválida: 422"                       '[[ "$STATUS" == 422 && "$(prio cp)" == super ]]'
call /treino/admin/contests GET '' t-boss.admin
ck "lista do painel traz a prioridade"              '[[ "$(jq -r ".contests[] | select(.id==\"cp\") | .priority" <<<"$BODY")" == super ]]'

echo "== criação e duplicação =="
spec(){ printf '{"id":"%s","name":"%s","mode":"icpc","end":%s,"priority":"%s","problems":[{"problem_id":"a/b","name":"AB"}]}' "$1" "$1" "$FUT" "$2"; }
call /treino/contest-create/create POST "$(spec np1 super)" t-prof.admin
ck ".admin comum não cria Super (403)"              '[[ "$STATUS" == 403 && "$(jq -r .error.code <<<"$BODY")" == priority_forbidden && ! -d "$FIX/np1" ]]'
call /treino/contest-create/create POST "$(spec ns1 super)" t-boss.admin
ck "super-admin cria Super"                         '[[ "$STATUS" == 200 && "$(prio ns1)" == super ]]'
ck "nascimento na trilha (via=criação)"             'grep -qP "\tboss\.admin\tcontest-priority\tcontest=ns1 de=— para=super via=criação$" "$T/var/admin-audit.log" && grep -q "para=super via=criação" "$FIX/ns1/var/admin-audit.log"'
call /treino/contest-create/create POST "$(spec np2 prova)" t-prof.admin
ck ".admin comum cria Prova"                        '[[ "$STATUS" == 200 && "$(prio np2)" == prova ]]'
call /treino/contest-create/duplicate POST '{"from":"cp","id":"cpcopia"}' t-prof.admin
ck "duplicar Super sem ser super-admin nasce Prova" '[[ "$STATUS" == 200 && "$(prio cpcopia)" == prova ]]'
call /treino/contest-create/duplicate POST '{"from":"cp","id":"cpcopia2"}' t-boss.admin
ck "o super-admin duplica mantendo Super"           '[[ "$STATUS" == 200 && "$(prio cpcopia2)" == super ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
