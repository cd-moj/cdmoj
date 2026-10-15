#!/bin/bash
# smoke-change-limits.sh — limites de troca do TREINO (lib/profile.sh profile_limits, 15/10/2026): `UNAME_CHANGE_LIMIT`
# (handle) e `TELEGRAM_CHANGE_LIMIT` (desvínculo do Telegram) vêm do CONF DO TREINO, depois do env, depois do padrão
# (2 e 1). 0 = DESATIVADO, com recusa e tela próprias. Afirma:
#   • padrão sem nada no conf: 2 e 1 no GET /treino/profile;
#   • o conf vence o env;
#   • handle 0: GET diz 0 e o POST é 403 uname_disabled (nada muda); handle 1: troca uma vez, a 2ª é 403 uname_limit
#     com "1 troca" (singular);
#   • Telegram 0: GET diz 0, o desvínculo é 403 telegram_unlink_disabled e o vínculo fica; o `.admin` segue livre.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN"
unset UNAME_CHANGE_LIMIT TELEGRAM_CHANGE_LIMIT
T="$FIX/treino"; mkdir -p "$T/var/telegram/by-tgid" "$T/var/telegram/by-login"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\n' > "$T/conf"
fx_user "$T" alice s Alice >/dev/null; fx_user "$T" boss.admin s Boss >/dev/null
link(){ printf '{"telegram_id":%s,"login":"%s","username":null,"linked_at":1}' "$2" "$1" > "$T/var/telegram/by-tgid/$2.json"
        printf '%s' "$2" > "$T/var/telegram/by-login/$1"; }
link alice 111; link boss.admin 222
for l in alice boss.admin; do printf 'CONTEST=treino\nLOGIN=%s\nUSERFULLNAME=x\nLOGINAT=1\n' "$l" > "$SESS/tok-$l"; done
call(){ OUT="$(env ${ENVX:-} PATH_INFO="$1" REQUEST_METHOD="$2" HTTP_AUTHORIZATION="Bearer tok-$4" bash "$ROUTER" <<<"${3:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
J(){ jq -r "$1" <<<"$BODY" 2>/dev/null; }
setc(){ sed -i "/^$1=/d" "$T/conf"; [[ -n "$2" ]] && printf '%s=%s\n' "$1" "$2" >> "$T/conf"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:220}"; ((fail++)); fi; }

echo "== padrão (nada no conf) =="
call /treino/profile GET '' alice
ck "handle 2 e Telegram 1"                 '[[ "$(J .username_changes_limit)" == 2 && "$(J .telegram.changes_limit)" == 1 ]]'
echo "== o conf do treino vence o env =="
setc UNAME_CHANGE_LIMIT 1; ENVX="UNAME_CHANGE_LIMIT=5 TELEGRAM_CHANGE_LIMIT=7" call /treino/profile GET '' alice
ck "conf 1 vence env 5; sem chave no conf, vale o env (7)" '[[ "$(J .username_changes_limit)" == 1 && "$(J .telegram.changes_limit)" == 7 ]]'

echo "== handle 0 = DESATIVADO =="
setc UNAME_CHANGE_LIMIT 0; call /treino/profile GET '' alice
ck "GET diz 0"                              '[[ "$(J .username_changes_limit)" == 0 && "$(J .username_changes_remaining)" == 0 ]]'
call /treino/profile/username POST '{"new_username":"alice2"}' alice
ck "POST = 403 uname_disabled, nada mudou"  '[[ "$OUT" == *"Status: 403"* && "$(J .error.code)" == uname_disabled && -d "$T/users/alice" && ! -e "$T/users/alice2" ]]'

echo "== handle 1 =="
setc UNAME_CHANGE_LIMIT 1; call /treino/profile/username POST '{"new_username":"alice2"}' alice
ck "1ª troca passa"                         '[[ "$(J .new_username)" == alice2 && "$(J .username_changes_remaining)" == 0 ]]'
sed -i 's/^LOGIN=alice$/LOGIN=alice2/' "$SESS/tok-alice" 2>/dev/null
call /treino/profile/username POST '{"new_username":"alice3"}' alice
ck "2ª = 403 uname_limit, no singular"      '[[ "$(J .error.code)" == uname_limit && "$(J .error.message)" == *"Limite de 1 troca por ano"* && -d "$T/users/alice2" ]]'

echo "== Telegram 0 = desvínculo DESATIVADO (usuário comum) =="
setc TELEGRAM_CHANGE_LIMIT 0; call /treino/profile GET '' alice
ck "GET diz 0"                              '[[ "$(J .telegram.changes_limit)" == 0 && "$(J .telegram.linked)" == true ]]'
call /treino/telegram/unlink POST '{}' alice
ck "unlink = 403 telegram_unlink_disabled, vínculo intacto" '[[ "$OUT" == *"Status: 403"* && "$(J .error.code)" == telegram_unlink_disabled && -f "$T/var/telegram/by-tgid/111.json" ]]'
call /treino/telegram/unlink POST '{}' boss.admin
ck ".admin segue livre: desvincula"         '[[ "$(J .success)" == true && ! -f "$T/var/telegram/by-tgid/222.json" ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
