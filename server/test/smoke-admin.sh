#!/bin/bash
# Testa o painel admin do treino: sessões (IP/UA), log de acesso, logout, lock, fila, stats.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
T="$FIX/treino"; mkdir -p "$T/controle" "$T/var"
printf 'CONTEST_ID=treino\nCONTEST_NAME="Treino Livre"\nCONTEST_TYPE=lista-publica\n' > "$T/conf"
printf 'alice:secret:Alice A\nboss.admin:bosspw:Boss Admin\n' > "$T/passwd"
printf '100:alice:p#x:C:Not Answered Yet:100:s1\n200:alice:p#x:C:Accepted,100p:200:s2\n' > "$T/controle/history"

# call <path> <method> <query> <token> <body> [ua] [xff]
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="$3" \
  HTTP_AUTHORIZATION="${4:+Bearer $4}" HTTP_USER_AGENT="${6:-}" HTTP_X_FORWARDED_FOR="${7:-}" \
  CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${5:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:160}"; ((fail++)); fi; }

call /auth/login POST "contest=treino" "" '{"username":"alice","password":"secret"}' "TestBrowser/1.0" "203.0.113.5"
ATOK="$(jq -r .token <<<"$BODY")"
call /auth/login POST "contest=treino" "" '{"username":"boss.admin","password":"bosspw"}' "AdminUA/2" "198.51.100.7"
BTOK="$(jq -r .token <<<"$BODY")"

echo "== sessões =="
call /treino/admin/sessions GET "" "$BTOK"
ck "admin lista 2 sessões"   '[[ "$(jq -r .count <<<"$BODY")" == 2 ]]'
ck "captura IP da alice"     '[[ "$(jq -r ".sessions[]|select(.login==\"alice\").ip" <<<"$BODY")" == "203.0.113.5" ]]'
ck "captura User-Agent"      '[[ "$(jq -r ".sessions[]|select(.login==\"alice\").user_agent" <<<"$BODY")" == "TestBrowser/1.0" ]]'
call /treino/admin/sessions GET "" "$ATOK"
ck "não-admin -> 403"        '[[ "$OUT" == *"Status: 403"* ]]'

echo "== log de acesso =="
call /treino/admin/access-log GET "" "$BTOK"
ck "2 entradas no log"       '[[ "$(jq -r ".entries|length" <<<"$BODY")" == 2 ]]'
ck "log tem ua decodificado" '[[ "$(jq -r ".entries[]|select(.login==\"alice\").user_agent" <<<"$BODY")" == "TestBrowser/1.0" ]]'
TODAY="$(date +%Y-%m-%d)"
call /treino/admin/access-log GET "day=$TODAY" "$BTOK"
ck "filtro por hoje funciona" '[[ "$(jq -r ".entries|length" <<<"$BODY")" -ge 2 ]]'
call /treino/admin/access-log GET "day=1999-01-01" "$BTOK"
ck "filtro dia vazio = 0"    '[[ "$(jq -r ".entries|length" <<<"$BODY")" == 0 ]]'

echo "== fila pendente =="
call /treino/admin/queue GET "" "$BTOK"
ck "1 submissão pendente"    '[[ "$(jq -r .total_pending <<<"$BODY")" == 1 ]]'
ck "lista treino aparece"    '[[ "$(jq -r ".lists[0].contest" <<<"$BODY")" == "treino" ]]'

echo "== stats =="
call /treino/admin/stats GET "" "$BTOK"
ck "users = 2"               '[[ "$(jq -r .users <<<"$BODY")" == 2 ]]'
ck "sessões ativas = 2"      '[[ "$(jq -r .active_sessions <<<"$BODY")" == 2 ]]'

echo "== deslogar usuário =="
call /treino/admin/logout-user POST "" "$BTOK" '{"login":"alice"}'
ck "removeu 1 sessão da alice" '[[ "$(jq -r .sessions_removed <<<"$BODY")" == 1 ]]'
call /treino/admin/sessions GET "" "$BTOK"
ck "agora só 1 sessão (boss)" '[[ "$(jq -r .count <<<"$BODY")" == 1 ]]'

echo "== travar acesso (troca senha) =="
call /treino/admin/lock-user POST "" "$BTOK" '{"login":"alice"}'
ck "lock ok"                 '[[ "$(jq -r .locked <<<"$BODY")" == "true" ]]'
ck "senha mudou (login antigo falha)" 'bash -c "PATH_INFO=/auth/login REQUEST_METHOD=POST QUERY_STRING=contest=treino CONTESTSDIR=$FIX SESSIONDIR=$SESS bash $ROUTER <<<'"'"'{\"username\":\"alice\",\"password\":\"secret\"}'"'"' 2>&1 | grep -q \"Status: 401\""'
call /treino/admin/lock-user POST "" "$BTOK" '{"login":"naoexiste"}'
ck "lock inexistente -> 404" '[[ "$OUT" == *"Status: 404"* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
