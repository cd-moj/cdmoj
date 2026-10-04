#!/bin/bash
# smoke-user-promote.sh — PROMOVER uma conta do treino a um papel (server/bin/user-promote.sh, 04/10/2026: Eri,
# idlechara → idlechara.admin). O usuário não pode ganhar sufixo de papel sozinho (smoke-profile); o admin da
# plataforma pode, com a MESMA cascata da troca de login (lib/rename-cascade.sh). Afirma:
#   • dry-run não muda nada; recusa sem sufixo, login já existente, conta inexistente, submissão pendente;
#   • --apply: conta movida (senha igual), Telegram, org (membro e a implícita), posse (contest + permissão de criar
#     contest), sessão aberta (segue logada, já .admin), audit, `.promoted`, sem gastar o limite anual de trocas;
#   • --message-file: a DM vai p/ a fila do mojinho (outbox) com o chat do Telegram VINCULADO e group:false;
#   • a troca pelo PRÓPRIO usuário (handler) segue igual depois da extração da cascata.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"; BIN="$ROOT/bin/user-promote.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$HERE/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" MOJ_PROBLEMS_DIR="$FIX/moj-problems" MOJ_JOBS_SYNC=1
mkdir -p "$MOJ_PROBLEMS_DIR"
NOW="$EPOCHSECONDS"; T="$FIX/treino"; mkdir -p "$T/var/telegram/by-tgid" "$T/var/telegram/by-login"
printf 'CONTEST_ID=treino\nCONTEST_END=%s\n' "$((NOW+86400))" > "$T/conf"
fx_user "$T" eri s3nha "Erik Teste" >/dev/null; fx_user "$T" bia s "Bia" >/dev/null; fx_user "$T" pend s "Pend" >/dev/null
: > "$T/users/eri/history"
printf '%s:p#x:C:Not Answered Yet:%s:s1\n' "$NOW" "$NOW" > "$T/users/pend/history"
# Telegram vinculado, org (membro de uma, admin da implícita), dono de contest, permissão de criar contest
jq -cn '{telegram_id:777, login:"eri", username:"eri_tg", linked_at:1, source:"link", last_seen:1}' > "$T/var/telegram/by-tgid/777.json"
printf '777\n' > "$T/var/telegram/by-login/eri"
jq -cn '{eri:{implicit:true, members:["eri"], admins:["eri"]}, tcp:{members:["eri","bia"], admins:["bia"]}}' > "$T/var/orgs.json"
mkdir -p "$FIX/cx"; printf 'CONTEST_ID=cx\n' > "$FIX/cx/conf"; printf 'eri\n' > "$FIX/cx/owner"
jq -cn '{allow:["eri","bia"]}' > "$T/var/contest-perms.json"
printf 'CONTEST=treino\nLOGIN=eri\nUSERFULLNAME=Erik\nLOGINAT=%s\n' "$NOW" > "$SESS/tok-eri"
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${OUT:0:300}"; ((fail++)); fi; }
run(){ OUT="$(bash "$BIN" "$@" 2>&1)"; RC=$?; }

echo "== dry-run e recusas =="
run eri eri.admin
ck "dry-run diz o que mudaria e não muda nada" '[[ $RC == 0 && "$OUT" == *"dry-run"* && "$OUT" == *"777"* && -d "$T/users/eri" && ! -e "$T/users/eri.admin" ]]'
run eri eri2 --apply
ck "sem sufixo de papel = recusa"              '[[ $RC != 0 && "$OUT" == *"sufixo de papel"* && -d "$T/users/eri" ]]'
fx_user "$T" bia.admin s "Bia adm" >/dev/null
run bia bia.admin --apply
ck "login novo já existe = recusa"             '[[ $RC != 0 && "$OUT" == *"já existe"* && -d "$T/users/bia" ]]'
run ninguem ninguem.admin --apply
ck "conta inexistente = recusa"                '[[ $RC != 0 && "$OUT" == *"não existe"* ]]'
run pend pend.admin --apply
ck "submissão pendente = recusa"               '[[ $RC != 0 && "$OUT" == *"pendente"* && -d "$T/users/pend" ]]'

echo "== --apply com mensagem =="
printf '<b>Hola</b>, Eri: tu login ahora es <code>eri.admin</code>.\n\nBruno Ribas' > "$FIX/msg.html"
run eri eri.admin --apply --message-file "$FIX/msg.html"
ck "promoveu (rc 0)"                           '[[ $RC == 0 && "$OUT" == *"promovido: eri.admin"* ]]'
ck "conta movida, mesma senha, login no account" '[[ ! -e "$T/users/eri" && "$(jq -r .login "$T/users/eri.admin/account.json")" == eri.admin && "$(jq -r .password "$T/users/eri.admin/account.json")" == s3nha ]]'
ck ".promoted registrado e o limite anual intacto" '[[ "$(jq -r ".promoted[0].from" "$T/users/eri.admin/account.json")" == eri && "$(jq -r "(.uname_changes // []) | length" "$T/users/eri.admin/account.json")" == 0 ]]'
ck "Telegram segue a conta"                    '[[ "$(jq -r .login "$T/var/telegram/by-tgid/777.json")" == eri.admin && "$(cat "$T/var/telegram/by-login/eri.admin")" == 777 && ! -e "$T/var/telegram/by-login/eri" ]]'
ck "orgs: membro/admin trocados"               '[[ "$(jq -c ".tcp.members" "$T/var/orgs.json")" == "[\"bia\",\"eri.admin\"]" && "$(jq -c ".eri.admins" "$T/var/orgs.json")" == "[\"eri.admin\"]" ]]'
ck "posse: dono do contest e permissão de criar" '[[ "$(cat "$FIX/cx/owner")" == eri.admin && "$(jq -c .allow "$T/var/contest-perms.json")" == "[\"bia\",\"eri.admin\"]" ]]'
ck "sessão aberta segue logada, já como .admin" '[[ "$(grep -c "^LOGIN=eri.admin$" "$SESS/tok-eri")" == 1 ]]'
ck "audit do treino registra"                  'grep -q "user-promote" "$T/var/admin-audit.log" 2>/dev/null || grep -rq "user-promote" "$T/var" 2>/dev/null'
OB="$(ls "$RUN/alerts/outbox/"*.json 2>/dev/null | head -1)"
ck "DM na fila do mojinho: chat 777, só p/ ele (group:false), o texto do arquivo" '[[ -n "$OB" && "$(jq -c .chats "$OB")" == "[777]" && "$(jq -r .group "$OB")" == false && "$(jq -r .text "$OB")" == *"<code>eri.admin</code>"* ]]'
run eri.admin eri.admin.admin --apply
ck "já tem o papel = recusa"                   '[[ $RC != 0 ]]'

echo "== a troca pelo PRÓPRIO usuário segue igual (cascata extraída p/ lib/rename-cascade.sh) =="
printf 'CONTEST=treino\nLOGIN=bia\nUSERFULLNAME=Bia\nLOGINAT=%s\n' "$NOW" > "$SESS/tok-bia"
OUT="$(PATH_INFO=/treino/profile/username REQUEST_METHOD=POST HTTP_AUTHORIZATION="Bearer tok-bia" bash "$ROUTER" <<<'{"new_username":"bia2"}' 2>&1)"
B="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"
ck "handler: troca ok, conta movida, 1 sessão seguiu, limite gasto" '[[ "$(jq -r .new_username <<<"$B")" == bia2 && "$(jq -r .sessions_updated <<<"$B")" == 1 && -d "$T/users/bia2" && "$(jq -r "(.uname_changes // []) | length" "$T/users/bia2/account.json")" == 1 ]]'
ck "handler: org e permissão seguiram"         '[[ "$(jq -c ".tcp.members" "$T/var/orgs.json")" == "[\"bia2\",\"eri.admin\"]" && "$(jq -c .allow "$T/var/contest-perms.json")" == "[\"bia2\",\"eri.admin\"]" ]]'
OUT="$(PATH_INFO=/treino/profile/username REQUEST_METHOD=POST HTTP_AUTHORIZATION="Bearer tok-bia" bash "$ROUTER" <<<'{"new_username":"bia2.admin"}' 2>&1)"
ck "handler: usuário NÃO ganha papel sozinho"  '[[ "$OUT" == *uname_reserved* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
