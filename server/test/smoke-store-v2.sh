#!/bin/bash
# Testa o store por-usuário (USER_STORE=v2) + overlay Telegram (cadastro/verify/recover/link)
# contra um fixture (não toca em dados reais). Router local; bot-token via BOT_TOKEN_FILE.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
T="$FIX/treino"
mkdir -p "$T/users" "$RUN/secrets" "$RUN/telegram"
printf 'CONTEST_ID=treino\nCONTEST_NAME="Treino"\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\n' > "$T/conf"
BOT="mojb_smoketoken"; printf '%s' "$BOT" > "$RUN/secrets/bot.token"

pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:180}"; ((fail++)); fi; }
call(){ # <auth> <path> <method> <qs> <body>
  OUT="$(env CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" BOT_TOKEN_FILE="$RUN/secrets/bot.token" \
    MOJ_CONF=/nonexistent PASSWORD_WORDLIST=/nonexistent TELEGRAM_BOT_USERNAME=mojinho_test \
    PATH_INFO="$2" REQUEST_METHOD="$3" QUERY_STRING="$4" HTTP_AUTHORIZATION="$1" bash "$ROUTER" <<<"${5:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }

echo "== cadastro web-first + verify =="
call "" /treino/signup/start POST "" '{"login":"joao","fullname":"João S","university":"UnB"}'
NONCE="$(jq -r .nonce <<<"$BODY")"
ck "start devolve nonce"        '[[ -n "$NONCE" && "$NONCE" != null ]]'
ck "deep_link com bot username" '[[ "$(jq -r .deep_link <<<"$BODY")" == *"mojinho_test?start="* ]]'
call "" /treino/signup/status GET "nonce=$NONCE" ""
ck "status pending"             '[[ "$(jq -r .status <<<"$BODY")" == pending ]]'
call "Bearer wrong" /treino/signup/verify POST "" "{\"nonce\":\"$NONCE\",\"telegram_id\":111}"
ck "verify sem bot-token -> 401" '[[ "$(jq -r .error.code <<<"$BODY")" == bot_unauth ]]'
call "Bearer $BOT" /treino/signup/verify POST "" "{\"nonce\":\"$NONCE\",\"telegram_id\":111,\"telegram_username\":\"joaotg\"}"
ck "verify cria conta joao"     '[[ "$(jq -r .status <<<"$BODY")" == created && "$(jq -r .login <<<"$BODY")" == joao ]]'
ck "verify devolve senha"       '[[ "$(jq -r ".password|type" <<<"$BODY")" == string ]]'
ck "account.json criado"        '[[ -f "$T/users/joao/account.json" ]]'
ck "university persistida"      '[[ "$(jq -r .university "$T/users/joao/account.json")" == UnB ]]'
ck "by-tgid/111 -> joao"        '[[ "$(jq -r .login "$T/var/telegram/by-tgid/111.json")" == joao ]]'
ck "account.json de joao criado"   '[[ -f "$T/users/joao/account.json" ]]'
call "" /treino/signup/status GET "nonce=$NONCE" ""
ck "status created, SEM senha"  '[[ "$(jq -r .status <<<"$BODY")" == created && "$(jq -r ".password" <<<"$BODY")" == null ]]'

echo "== uso único + anti-duplicata + recover =="
call "Bearer $BOT" /treino/signup/verify POST "" "{\"nonce\":\"$NONCE\",\"telegram_id\":111}"
ck "nonce uso único -> inválido" '[[ "$(jq -r .error.code <<<"$BODY")" == nonce_invalid ]]'
call "Bearer $BOT" /treino/signup/telegram POST "" '{"telegram_id":111,"telegram_username":"joaotg"}'
ck "participar mesmo tg -> already_linked" '[[ "$(jq -r .status <<<"$BODY")" == already_linked && "$(jq -r .login <<<"$BODY")" == joao ]]'
call "Bearer $BOT" /treino/recover-password POST "" '{"telegram_id":111}'
ck "recover tg=111 ok+senha"    '[[ "$(jq -r .status <<<"$BODY")" == ok && "$(jq -r ".password|type" <<<"$BODY")" == string ]]'
call "Bearer $BOT" /treino/recover-password POST "" '{"telegram_id":999}'
ck "recover tg desconhecido -> not_linked" '[[ "$(jq -r .status <<<"$BODY")" == not_linked ]]'
call "Bearer $BOT" /treino/signup/start POST "" '{"login":"joao","fullname":"x"}'
ck "signup/start login em uso -> 409" '[[ "$(jq -r .error.code <<<"$BODY")" == login_taken ]]'
call "" /treino/signup/start POST "" '{"login":"root.admin","fullname":"x"}'
ck "signup bloqueia sufixo de papel" '[[ "$(jq -r .error.code <<<"$BODY")" == login_reserved ]]'

echo "== leitores store-v2 (history/solvetry) =="
printf 'CONTEST="treino"\nLOGIN="joao"\nUSERFULLNAME="João S"\nLOGINAT=1\n' > "$SESS/tok-joao"
# injeta history do joao no store
hj="$T/users/joao/history"; printf '10:col#p1:C:Accepted,100p:10:s1\n20:col#p2:PY:Wrong Answer,0p:20:s2\n' >> "$hj"
call "Bearer tok-joao" /treino/history-full GET "user=joao" ""
ck "history-full 7 campos c/ login" '[[ "$(printf "%s" "$BODY" | head -1)" == "10:joao:col#p1:C:Accepted,100p:10:s1" ]]'
call "Bearer tok-joao" /treino/solvetry GET "" ""
ck "solvetry solved=[col#p1]" '[[ "$(jq -rc ".solved" <<<"$BODY")" == "[\"col#p1\"]" ]]'

echo "== link (conta logada vincula Telegram) =="
call "Bearer tok-joao" /treino/telegram/link-start POST "" ""
LN="$(jq -r .nonce <<<"$BODY")"
ck "link-start devolve nonce" '[[ -n "$LN" && "$LN" != null ]]'
# joao já está vinculado a 111 -> verify com novo tgid 222 deve dar already_linked (anti-dup por conta)
call "Bearer $BOT" /treino/signup/verify POST "" "{\"nonce\":\"$LN\",\"telegram_id\":111}"
ck "link do mesmo tg -> already_linked" '[[ "$(jq -r .status <<<"$BODY")" == already_linked ]]'

echo "== admin do contest v2 (user-add/disable/set-password/remove) =="
printf 'CONTEST=treino\nLOGIN=boss.admin\nUSERFULLNAME=Boss\nLOGINAT=1\n' > "$SESS/tok-adm"
call "Bearer tok-adm" /contest/admin/user-add POST "contest=treino" '{"login":"maria","password":"s3nh4","fullname":"Maria"}'
ck "user-add cria no store"      '[[ -f "$T/users/maria/account.json" ]]'
ck "account de maria (senha)"   '[[ "$(jq -r .password "$T/users/maria/account.json")" == "s3nh4" ]]'
call "Bearer tok-adm" /contest/admin/user-add POST "contest=treino" '{"login":"maria","password":"nova1","fullname":"Maria N"}'
ck "reset atualiza account.json" '[[ "$(jq -r .password "$T/users/maria/account.json")" == nova1 ]]'
ck "account atualizado (senha)"  '[[ "$(jq -r .password "$T/users/maria/account.json")" == "nova1" ]]'
call "Bearer tok-adm" /contest/admin/user-disable POST "contest=treino" '{"login":"maria"}'
ck "disable marca ! no account"  '[[ "$(jq -r .password "$T/users/maria/account.json")" == \!* ]]'
ck "account com senha !"        '[[ "$(jq -r .password "$T/users/maria/account.json")" == \!* ]]'
call "Bearer tok-adm" /contest/admin/users-set-password POST "contest=treino" '{"password":"prova1"}'
ck "set-password troca joao (pula desabilitada)" '[[ "$(jq -r .password "$T/users/joao/account.json")" == prova1 && "$(jq -r .count <<<"$BODY")" == 1 ]]'
ck "maria continua desabilitada" '[[ "$(jq -r .password "$T/users/maria/account.json")" == \!* ]]'
call "Bearer tok-adm" /contest/admin/users-set-password POST "contest=treino" '{"password":"prova2","include_disabled":true}'
ck "include_disabled reabilita maria (count 2)" '[[ "$(jq -r .password "$T/users/maria/account.json")" == prova2 && "$(jq -r .count <<<"$BODY")" == 2 ]]'
call "Bearer tok-adm" /contest/admin/user-remove POST "contest=treino" '{"login":"maria"}'
ck "remove move o diretório"     '[[ ! -d "$T/users/maria" ]] && ls "$T/.removed-users" 2>/dev/null | grep -q "^maria-"'
ck "conta de maria movida p/ .removed-users" '[[ ! -e "$T/users/maria" ]]'
call "Bearer tok-adm" /contest/admin/user-remove POST "contest=treino" '{"login":"maria"}'
ck "remove de inexistente 404"   '[[ "$OUT" == *"Status: 404"* ]]'

echo "== carga em lote no store v2 =="
call "Bearer tok-adm" /contest/admin/users-bulk POST "contest=treino" '{"users":[{"login":"lote1","fullname":"Lote Um"},{"login":"lote2","password":"pw2","fullname":"Lote Dois"},{"login":"joao","fullname":"Colide"}]}'
ck "bulk cria 2 no store"        '[[ "$(jq -r .counts.created <<<"$BODY")" == 2 && -f "$T/users/lote1/account.json" && -f "$T/users/lote2/account.json" ]]'
ck "account.json é a fonte"      '[[ "$(jq -r .password "$T/users/lote2/account.json")" == pw2 ]]'
ck "accounts do lote criados" '[[ -f "$T/users/lote1/account.json" && "$(jq -r .password "$T/users/lote2/account.json")" == "pw2" ]]'
ck "joao (existe) pulado"        '[[ "$(jq -r ".skipped[]|select(.login==\"joao\").reason" <<<"$BODY")" == exists ]]'
call "Bearer tok-adm" /contest/admin/users-bulk POST "contest=treino" '{"on_existing":"update","users":[{"login":"lote1","password":"nova","fullname":"Lote Um V2"}]}'
ck "bulk update no account.json"  '[[ "$(jq -r .password "$T/users/lote1/account.json")" == nova && "$(jq -r .fullname "$T/users/lote1/account.json")" == "Lote Um V2" ]]'
ck "account do lote atualizado" '[[ "$(jq -r .password "$T/users/lote1/account.json")" == "nova" && "$(jq -r .fullname "$T/users/lote1/account.json")" == "Lote Um V2" ]]'

echo
echo "RESULT: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
