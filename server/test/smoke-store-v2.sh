#!/bin/bash
# Testa o store por-usuário (USER_STORE=v2) + overlay Telegram (cadastro/verify/recover/link)
# contra um fixture (não toca em dados reais). Router local; bot-token via BOT_TOKEN_FILE.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; PROBS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN" "$PROBS"' EXIT
export MOJ_PROBLEMS_DIR="$PROBS"   # nunca o banco real (o índice de problemas abaixo é a fonte do "é privado?")
T="$FIX/treino"
mkdir -p "$T/users" "$T/var" "$RUN/secrets" "$RUN/telegram"
# índice de problemas FRESCO (o solvetry/history-full de quem não é o dono perguntam "é privado?" a ele): col#p1
# público, col#p2 PRIVADO de outro autor
jq -cn --argjson t "$EPOCHSECONDS" '{generated_at:$t, problems:[
  {id:"col#p1", title:"P1", owner:"x", collaborators:[], public:true},
  {id:"col#p2", title:"P2", owner:"outro", collaborators:[], public:false}]}' > "$T/var/problem-owners.json"
printf 'CONTEST_ID=treino\nCONTEST_NAME="Treino"\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\n' > "$T/conf"
BOT="mojb_smoketoken"; printf '%s' "$BOT" > "$RUN/secrets/bot.token"

pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:180}"; ((fail++)); fi; }
call(){ # <auth> <path> <method> <qs> <body>
  OUT="$(env CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" BOT_TOKEN_FILE="$RUN/secrets/bot.token" \
    MOJ_CONF=/nonexistent PASSWORD_WORDLIST=/nonexistent TELEGRAM_BOT_USERNAME=mojinho_test \
    PATH_INFO="$2" REQUEST_METHOD="$3" QUERY_STRING="$4" HTTP_AUTHORIZATION="$1" bash "$ROUTER" <<<"${5:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }

echo "== cadastro: login que some ou não loga (15/10/2026) =="
for n in '.....' '.x' '-rf' 'a..b'; do
  call "" /treino/signup/start POST "" "{\"login\":\"$n\",\"fullname\":\"x\"}"
  ck "signup/start [$n] -> 400 login_invalid" '[[ "$(jq -r .error.code <<<"$BODY")" == login_invalid ]]'
done
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
ck "o cadastro vai à trilha (via=site)" 'grep -qP "\tjoao\tsignup\tvia=site$" "$T/var/admin-audit.log"'
call "" /treino/signup/status GET "nonce=$NONCE" ""
ck "status created, SEM senha"  '[[ "$(jq -r .status <<<"$BODY")" == created && "$(jq -r ".password" <<<"$BODY")" == null ]]'

echo "== uso único + anti-duplicata + recover =="
call "Bearer $BOT" /treino/signup/verify POST "" "{\"nonce\":\"$NONCE\",\"telegram_id\":111}"
ck "nonce uso único -> inválido" '[[ "$(jq -r .error.code <<<"$BODY")" == nonce_invalid ]]'
call "Bearer $BOT" /treino/signup/telegram POST "" '{"telegram_id":111,"telegram_username":"joaotg"}'
ck "participar mesmo tg -> already_linked" '[[ "$(jq -r .status <<<"$BODY")" == already_linked && "$(jq -r .login <<<"$BODY")" == joao ]]'
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=1\n' treino joao "João S" > "$SESS/tok-joao-rec"   # sessão aberta (formato do create_session)
# a conta também está num contest que usa as contas do treino (direto e como ATOR de um time); um contest de contas
# próprias tem OUTRA conta com o mesmo nome
mkdir -p "$FIX/shr2/users/joao" "$FIX/ind2/users/joao"
printf 'CONTEST_ID=shr2\nUSERS_FROM=treino\n' > "$FIX/shr2/conf"; printf 'CONTEST_ID=ind2\n' > "$FIX/ind2/conf"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=1\n' shr2 joao "João S" > "$SESS/tok-joao-shr"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=1\nACTOR=%q\n' shr2 time-x "Time X" joao > "$SESS/tok-joao-actor"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=1\n' ind2 joao "Outro" > "$SESS/tok-joao-ind"
call "Bearer $BOT" /treino/recover-password POST "" '{"telegram_id":111}'
ck "recover tg=111 ok+senha"    '[[ "$(jq -r .status <<<"$BODY")" == ok && "$(jq -r ".password|type" <<<"$BODY")" == string ]]'
ck "recover encerra as sessões abertas da conta" '[[ ! -f "$SESS/tok-joao-rec" ]]'
ck "…também nos contests que usam as contas do treino (direto e como ator)" '[[ ! -f "$SESS/tok-joao-shr" && ! -f "$SESS/tok-joao-actor" ]]'
ck "…e a conta homônima de um contest de contas próprias fica" '[[ -f "$SESS/tok-joao-ind" ]]'
ck "recover vai à trilha"       'grep -qP "\tjoao\tpassword-recover\tvia=telegram " "$T/var/admin-audit.log"'
call "Bearer $BOT" /treino/recover-password POST "" '{"telegram_id":999}'
ck "recover tg desconhecido -> not_linked" '[[ "$(jq -r .status <<<"$BODY")" == not_linked ]]'
call "Bearer $BOT" /treino/signup/start POST "" '{"login":"joao","fullname":"x"}'
ck "signup/start login em uso -> 409" '[[ "$(jq -r .error.code <<<"$BODY")" == login_taken ]]'
# nome de uma org do treino = login em uso (o nome de um login é o da org pessoal dele)
[[ -s "$T/var/orgs.json" ]] || echo '{}' > "$T/var/orgs.json"
jq '. + {"orgx":{"members":["joao"],"admins":["joao"],"created_by":"joao"}}' "$T/var/orgs.json" > "$T/x" && mv "$T/x" "$T/var/orgs.json"
call "" /treino/signup/start POST "" '{"login":"orgx","fullname":"x"}'
ck "signup/start com o nome de uma org -> 409 login_taken" '[[ "$(jq -r .error.code <<<"$BODY")" == login_taken ]]'
call "Bearer $BOT" /treino/signup/telegram POST "" '{"telegram_id":333,"telegram_username":"orgx"}'
ck "cadastro pelo bot pula o nome da org (orgx_2) e vai à trilha (via=telegram)" '[[ "$(jq -r .login <<<"$BODY")" == orgx_2 ]] && grep -qP "\torgx_2\tsignup\tvia=telegram$" "$T/var/admin-audit.log"'
call "" /treino/signup/start POST "" '{"login":"root.admin","fullname":"x"}'
ck "signup bloqueia sufixo de papel" '[[ "$(jq -r .error.code <<<"$BODY")" == login_reserved ]]'

echo "== leitores store-v2 (history/solvetry) =="
printf 'CONTEST="treino"\nLOGIN="joao"\nUSERFULLNAME="João S"\nLOGINAT=1\n' > "$SESS/tok-joao"
# injeta history do joao no store
hj="$T/users/joao/history"; printf '10:col#p1:C:Accepted,100p:10:s1\n20:col#p2:PY:Wrong Answer,0p:20:s2\n' >> "$hj"
call "Bearer tok-joao" /treino/history-full GET "user=joao" ""
ck "history-full 7 campos c/ login (verdict canônico)" '[[ "$(printf "%s" "$BODY" | head -1)" == "10:joao:col#p1:C:Accepted:10:s1" ]]'
call "Bearer tok-joao" /treino/solvetry GET "" ""
ck "solvetry solved=[col#p1]" '[[ "$(jq -rc ".solved" <<<"$BODY")" == "[\"col#p1\"]" ]]'
# (1) o "usuário logado" só vale numa sessão DO TREINO; (2) privado sai p/ quem não é o dono
mkdir -p "$T/var/jsons-private"; printf '{}' > "$T/var/jsons-private/col#p2.json"   # col#p2 vira PRIVADO
call "Bearer tok-joao" /treino/solvetry GET "" ""
ck "solvetry do PRÓPRIO dono mantém o privado (attempted=[col#p2])" '[[ "$(jq -rc ".attempted" <<<"$BODY")" == "[\"col#p2\"]" ]]'
call "" /treino/solvetry GET "user=joao" ""
ck "solvetry ?user= anônimo: o privado SAI, o público fica" '[[ "$(jq -rc ".attempted" <<<"$BODY")" == "[]" && "$(jq -rc ".solved" <<<"$BODY")" == "[\"col#p1\"]" ]]'
# mesmo login com conta DE VERDADE no próprio contest (sessão viva: o load_session a aceita — o corte é a regra do treino)
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
mkdir -p "$FIX/outro"; printf 'CONTEST_ID=outro\nCONTEST_END=9999999999\n' > "$FIX/outro/conf"; fx_user "$FIX/outro" joao h "Outro"
printf 'CONTEST="outro"\nLOGIN="joao"\nUSERFULLNAME="Outro"\nLOGINAT=1\n' > "$SESS/tok-hom"
call "Bearer tok-hom" /treino/solvetry GET "" ""
ck "solvetry com sessão de OUTRO contest não vira o joao do treino (400 user_missing)" '[[ "$(jq -r .error.code <<<"$BODY")" == user_missing ]]'
call "Bearer tok-hom" /treino/solvetry GET "user=joao" ""
ck "…e com ?user=joao ela vê só o público" '[[ "$(jq -rc ".attempted" <<<"$BODY")" == "[]" ]]'
# history-full: as MESMAS regras
call "Bearer tok-joao" /treino/history-full GET "" ""
ck "history-full do PRÓPRIO dono mantém a linha do privado" 'grep -q ":col#p2:" <<<"$BODY"'
call "" /treino/history-full GET "user=joao" ""
ck "history-full ?user= anônimo: a linha do privado SAI, a pública fica" '! grep -q ":col#p2:" <<<"$BODY" && grep -q ":col#p1:" <<<"$BODY"'
call "Bearer tok-hom" /treino/history-full GET "" ""
ck "history-full com sessão de OUTRO contest não vira o joao do treino (400)" '[[ "$(jq -r .error.code <<<"$BODY" 2>/dev/null)" == user_missing ]]'
# perfil PRIVADO: o solvetry segue a regra do history-full (dono e admin do treino veem; o resto, vazio)
jq '.public=false' "$T/users/joao/account.json" > "$T/x" && mv "$T/x" "$T/users/joao/account.json"
call "" /treino/solvetry GET "user=joao" ""
ck "solvetry de perfil privado p/ anônimo = listas vazias" '[[ "$(jq -rc "[.solved,.attempted]" <<<"$BODY")" == "[[],[]]" ]]'
call "Bearer tok-joao" /treino/solvetry GET "" ""
ck "…e o dono segue vendo os dele"                         '[[ "$(jq -rc ".solved" <<<"$BODY")" == "[\"col#p1\"]" ]]'
jq 'del(.public)' "$T/users/joao/account.json" > "$T/x" && mv "$T/x" "$T/users/joao/account.json"
# índice de problemas ILEGÍVEL (e sem gerador p/ refazer): quem não é o dono recebe 503 — nunca o history inteiro
cp "$T/var/problem-owners.json" "$T/var/po.bak"; printf '{' > "$T/var/problem-owners.json"
MOJTOOLS_DIR=/nonexistent call "" /treino/history-full GET "user=joao" ""
ck "history-full: índice ilegível ⇒ 503, sem linha nenhuma" '[[ "$OUT" == *"Status: 503"* ]] && ! grep -q "col#p" <<<"$BODY"'
MOJTOOLS_DIR=/nonexistent call "" /treino/solvetry GET "user=joao" ""
ck "solvetry: idem 503"                                     '[[ "$OUT" == *"Status: 503"* ]]'
mv "$T/var/po.bak" "$T/var/problem-owners.json"
# dir ÓRFÃO (history sem account.json — resíduo de rename/remoção): o profile_is_public o daria como público
mkdir -p "$T/users/orfao"; printf '10:col#p1:C:Accepted,100p:10:o1\n' > "$T/users/orfao/history"
call "" /treino/solvetry GET "user=orfao" ""
ck "solvetry de dir ÓRFÃO p/ anônimo = listas vazias" '[[ "$(jq -rc "[.solved,.attempted]" <<<"$BODY")" == "[[],[]]" ]]'
call "" /treino/history-full GET "user=orfao" ""
ck "history-full de dir ÓRFÃO p/ anônimo = vazio"      '[[ -z "$BODY" ]]'
rm -f "$T/var/jsons-private/col#p2.json"

echo "== link (conta logada vincula Telegram) =="
call "Bearer tok-joao" /treino/telegram/link-start POST "" ""
LN="$(jq -r .nonce <<<"$BODY")"
ck "link-start devolve nonce" '[[ -n "$LN" && "$LN" != null ]]'
# joao já está vinculado a 111 -> verify com novo tgid 222 deve dar already_linked (anti-dup por conta)
call "Bearer $BOT" /treino/signup/verify POST "" "{\"nonce\":\"$LN\",\"telegram_id\":111}"
ck "link do mesmo tg -> already_linked" '[[ "$(jq -r .status <<<"$BODY")" == already_linked ]]'

echo "== admin do contest v2 (user-add/disable/set-password/remove) =="
# o admin precisa EXISTIR: sessão de conta inexistente morre em load_session (lib/auth.sh)
source "$(dirname "$(readlink -f "$0")")/fixture.sh"; fx_user "$T" boss.admin p "Boss"
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
# A troca de senha GERAL é barrada no treino de propósito: lá ela resetaria ~todas as contas da
# plataforma de uma vez. O contest é o lugar dela — então o guard e o comportamento são testados
# separados (antes este bloco rodava no treino e consagrava o que hoje é 400).
call "Bearer tok-adm" /contest/admin/users-set-password POST "contest=treino" '{"password":"prova1"}'
ck "troca geral BARRADA no treino"  '[[ "$OUT" == *"Status: 400"* && "$(jq -r .error.code <<<"$BODY")" == treino_forbidden ]]'
ck "e ninguém teve senha trocada"   '[[ "$(jq -r .password "$T/users/joao/account.json")" != prova1 ]]'
ck "maria continua desabilitada"    '[[ "$(jq -r .password "$T/users/maria/account.json")" == \!* ]]'

echo "== troca de senha geral (no contest, que é onde ela vale) =="
P="$FIX/prova9"; mkdir -p "$P/users"
printf 'CONTEST_ID=prova9\nCONTEST_NAME="Prova"\nCONTEST_TYPE=icpc\nUSER_STORE=v2\n' > "$P/conf"
fx_user "$P" p9.admin p "Chefe"; fx_user "$P" ana a "Ana"; fx_user "$P" bia b "Bia"
printf 'CONTEST=prova9\nLOGIN=p9.admin\nUSERFULLNAME=Chefe\nLOGINAT=1\n' > "$SESS/tok-p9"
call "Bearer tok-p9" /contest/admin/user-disable POST "contest=prova9" '{"login":"bia"}'
call "Bearer tok-p9" /contest/admin/users-set-password POST "contest=prova9" '{"password":"prova1"}'
ck "troca ana e pula a desabilitada" '[[ "$(jq -r .password "$P/users/ana/account.json")" == prova1 && "$(jq -r .count <<<"$BODY")" == 1 ]]'
ck "bia (desabilitada) intacta"      '[[ "$(jq -r .password "$P/users/bia/account.json")" == \!* ]]'
ck "conta de PAPEL fica de fora"     '[[ "$(jq -r .password "$P/users/p9.admin/account.json")" == p ]]'
call "Bearer tok-p9" /contest/admin/users-set-password POST "contest=prova9" '{"password":"prova2","include_disabled":true}'
ck "include_disabled alcança bia"    '[[ "$(jq -r .password "$P/users/bia/account.json")" == prova2 && "$(jq -r .count <<<"$BODY")" == 2 ]]'
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
# no TREINO o on_existing=update (reset em massa, com as senhas novas na resposta) é recusado (28/10/2026,
# a regra do users-set-password); a mecânica do update segue coberta nos contests (smoke-contest-users-admin,
# smoke-name-colon, smoke-contest-teams)
call "Bearer tok-adm" /contest/admin/users-bulk POST "contest=treino" '{"on_existing":"update","users":[{"login":"lote1","password":"nova","fullname":"Lote Um V2"}]}'
ck "bulk update no TREINO = 400 treino_forbidden" '[[ "$(jq -r .error.code <<<"$BODY")" == treino_forbidden ]]'
ck "…e a conta do lote NÃO mudou"               '[[ "$(jq -r .password "$T/users/lote1/account.json")" != nova && "$(jq -r .fullname "$T/users/lote1/account.json")" == "Lote Um" ]]'

echo
echo "RESULT: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
