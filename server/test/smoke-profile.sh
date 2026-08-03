#!/bin/bash
# Testa o perfil self-service do treino contra um fixture store-v2 (não toca em dados reais).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
ROUTER="$ROOT/api/v1/router.sh"
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS"' EXIT
T="$FIX/treino"
mkdir -p "$T/var"
printf 'CONTEST_ID=treino\nCONTEST_NAME="Treino"\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\n' > "$T/conf"
fx_user "$T" alice secret "Alice Tester"
fx_user "$T" bob pw "Bob"
printf '1700000000:moj-problems#ola:C:Accepted,100p:1700000000:abc123\n'  >> "$T/users/alice/history"
printf '1700000100:moj-problems#soma:C:Wrong Answer:1700000100:def456\n'   >> "$T/users/alice/history"
printf '1700000200:moj-problems#ola:C:Accepted,100p:1700000200:ghi789\n'   >> "$T/users/bob/history"
echo 'int main(){}' > "$T/users/alice/submissions/abc123.c"

# contest que HERDA os usuários do treino (participante compartilhado: dir local sem
# account.json) e contest INDEPENDENTE com um `alice` que por acaso tem o mesmo nome.
X="$FIX/xcont"; mkdir -p "$X/users/alice" "$X/var"
printf 'CONTEST_ID=xcont\nCONTEST_TYPE=competicao\nUSERS_FROM=treino\n' > "$X/conf"
O="$FIX/outro"; mkdir -p "$O/var"
printf 'CONTEST_ID=outro\nCONTEST_TYPE=competicao\n' > "$O/conf"
fx_user "$O" alice outra "Alice de Outro Contest"

TOK="tok-alice"
mksess(){ printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=1700000000\n' "$2" "$3" "${4:-x}" > "$SESS/$1"; }
mksess "$TOK"      treino alice "Alice Tester"
mksess tok-cli     treino alice "Alice Tester"   # outro dispositivo (moj-cli): mesmo login
mksess tok-xcont   xcont  alice "Alice Tester"   # contest que herda os usuários do treino
mksess tok-outro   outro  alice "Alice de Outro Contest"  # login homônimo, OUTRA conta
mksess tok-bob     treino bob   "Bob"
mksess tok-fantasma treino sumido "Sumido"       # login sem account.json

# call <path> <method> [body] [token] [query]
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-$TOK}" \
  CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
slogin(){ local CONTEST="" LOGIN=""; source "$SESS/$1" 2>/dev/null; printf '%s' "$LOGIN"; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:160}"; ((fail++)); fi; }

echo "== GET profile =="
call /treino/profile GET
ck "name presente"   '[[ "$BODY" == *"Alice Tester"* ]]'
ck "remaining = 2"   '[[ "$(jq -r .username_changes_remaining <<<"$BODY")" == 2 ]]'

echo "== nome + universidade =="
call /treino/profile POST '{"name":"Alice Nova","university":"UnB-Gama"}'
ck "nome atualizado"  '[[ "$(jq -r .name <<<"$BODY")" == "Alice Nova" ]]'
ck "univ atualizada"  '[[ "$(jq -r .university <<<"$BODY")" == "UnB-Gama" ]]'
ck "account fullname" '[[ "$(jq -r .fullname "$T/users/alice/account.json")" == "Alice Nova" ]]'
ck "account university" '[[ "$(jq -r .university "$T/users/alice/account.json")" == "UnB-Gama" ]]'

echo "== senha =="
call /treino/profile/password POST '{"old_password":"secret","new_password":"novasenha"}'
ck "senha trocada"    '[[ "$(jq -r .updated <<<"$BODY")" == "true" ]]'
ck "account password" '[[ "$(jq -r .password "$T/users/alice/account.json")" == "novasenha" ]]'
call /treino/profile/password POST '{"old_password":"ERRADA","new_password":"x"}'
ck "senha velha errada -> 403" '[[ "$OUT" == *"Status: 403"* ]]'

echo "== troca de username (rename = mv do diretório) =="
call /treino/profile/username POST '{"new_username":"alice2"}'
ck "username trocado"     '[[ "$(jq -r .new_username <<<"$BODY")" == "alice2" ]]'
ck "diretório renomeado"  '[[ -d "$T/users/alice2" && ! -e "$T/users/alice" ]]'
ck "account login = alice2" '[[ "$(jq -r .login "$T/users/alice2/account.json")" == "alice2" ]]'
ck "history preservado (2 linhas)" '[[ "$(wc -l < "$T/users/alice2/history")" == 2 ]]'
ck "history do bob intacto" '[[ "$(wc -l < "$T/users/bob/history")" == 1 ]]'
ck "submissão preservada" '[[ -f "$T/users/alice2/submissions/abc123.c" ]]'
ck "remaining = 1"        '[[ "$(jq -r .username_changes_remaining <<<"$BODY")" == 1 ]]'

# TODAS as sessões da conta seguem o rename — não só a que pediu a troca. Era o furo: a aba
# do outro computador continuava com o login velho e a próxima submissão por ela RECRIAVA o
# diretório do nome antigo (fantasma sem account.json).
echo "== o rename arrasta TODAS as sessões da conta =="
ck "sessão que pediu a troca" '[[ "$(slogin "$TOK")" == alice2 ]]'
ck "sessão do outro dispositivo (moj-cli)" '[[ "$(slogin tok-cli)" == alice2 ]]'
ck "sessão do contest que herda os usuários" '[[ "$(slogin tok-xcont)" == alice2 ]]'
ck "sessão homônima de OUTRO contest intacta" '[[ "$(slogin tok-outro)" == alice ]]'
ck "sessão do bob intacta" '[[ "$(slogin tok-bob)" == bob ]]'
ck "sessions_updated = 3" '[[ "$(jq -r .sessions_updated <<<"$BODY")" == 3 ]]'
call /auth/status GET '' tok-cli
ck "moj-cli segue logado, já como alice2" '[[ "$(jq -r .login <<<"$BODY")" == alice2 ]]'
call /auth/status GET '' tok-xcont
ck "participante compartilhado (USERS_FROM) segue válido" '[[ "$(jq -r .logged_in <<<"$BODY")" == true ]]'
call /auth/status GET '' tok-outro
ck "conta homônima de outro contest segue válida" '[[ "$(jq -r .login <<<"$BODY")" == alice ]]'

echo "== 2ª troca ok, 3ª bloqueada pelo limite =="
call /treino/profile/username POST '{"new_username":"alice3"}'
ck "2ª troca ok"          '[[ "$(jq -r .updated <<<"$BODY")" == "true" ]]'
call /treino/profile/username POST '{"new_username":"alice4"}'
ck "3ª bloqueada (limite) 403" '[[ "$OUT" == *"Status: 403"* && "$BODY" == *"Limite"* ]]'

echo "== sufixo reservado e nome em uso =="
call /treino/profile/username POST '{"new_username":"hacker.admin"}'
ck "sufixo .admin -> 400" '[[ "$OUT" == *"Status: 400"* ]]'
call /treino/profile/username POST '{"new_username":"bob"}'
ck "nome em uso -> (limite vem antes) 403/409" '[[ "$OUT" == *"Status: 4"* ]]'

# Sessão não expira; sem este corte ela seguia autenticada como um login que não existe mais
# (conta renomeada/removida, contest apagado) e o submit RECRIAVA o diretório do fantasma.
echo "== sessão de conta que não existe mais morre =="
call /auth/status GET '' tok-fantasma
ck "status = deslogado"        '[[ "$(jq -r .logged_in <<<"$BODY")" == false ]]'
call /treino/profile GET '' tok-fantasma
ck "rota autenticada -> 401"   '[[ "$OUT" == *"Status: 401"* ]]'
call /submit POST '{"problem_id":"moj-problems#ola","filename":"s.c","code_b64":"aQ=="}' tok-fantasma 'contest=treino'
ck "submit -> 401"             '[[ "$OUT" == *"Status: 401"* ]]'
ck "NÃO nasceu users/sumido"   '[[ ! -e "$T/users/sumido" ]]'
call /auth/logout POST '' tok-fantasma
ck "logout apaga a sessão zumbi" '[[ ! -e "$SESS/tok-fantasma" ]]'

# bin/user-merge.sh — o conserto do resíduo que o furo deixou (dir órfão com history).
echo "== user-merge (resíduo -> conta viva) =="
G="$T/users/7305847700"; mkdir -p "$G/submissions" "$G/results" "$G/mojlog"
printf '1700000050:moj-problems#ola:CPP:Accepted,100p:1700000050:zzz111\n'      >> "$G/history"
printf '1700000060:moj-problems#pilha:C:Wrong Answer,0p:1700000060:zzz222\n'    >> "$G/history"
echo 'int main(){}' > "$G/submissions/zzz111.cpp"; echo '{}' > "$G/results/zzz111.json"
printf '1700000050:zzz111:7305847700:web\n' > "$T/var/editor-log"
CONTESTSDIR="$FIX" bash "$ROOT/bin/user-merge.sh" treino 7305847700 alice3 >/dev/null 2>&1
ck "dry-run não move nada"     '[[ -f "$G/history" && "$(wc -l < "$T/users/alice3/history")" == 2 ]]'
CONTESTSDIR="$FIX" bash "$ROOT/bin/user-merge.sh" treino 7305847700 alice3 --apply >/dev/null 2>&1
ck "history fundido (4 linhas)" '[[ "$(wc -l < "$T/users/alice3/history")" == 4 ]]'
ck "history ordenado por epoch" '[[ "$(cut -d: -f1 "$T/users/alice3/history" | sort -n -c 2>&1)" == "" ]]'
ck "arquivo da submissão migrou" '[[ -f "$T/users/alice3/submissions/zzz111.cpp" ]]'
ck "resíduo saiu de users/"     '[[ ! -e "$G" ]]'
ck "resíduo arquivado"          '[[ -d "$(echo "$T"/var/merged/7305847700.*)" ]]'
ck "editor-log reatribuído"     'grep -q "^1700000050:zzz111:alice3:web$" "$T/var/editor-log"'
ck "metrics do destino somam"   '[[ "$(jq -r .submissions "$T/users/alice3/metrics.json")" == 4 ]]'
CONTESTSDIR="$FIX" bash "$ROOT/bin/user-merge.sh" treino bob alice3 --apply >/dev/null 2>&1
ck "recusa fundir conta VIVA"   '[[ -f "$T/users/bob/account.json" ]]'

echo ""
echo "RESULT: $pass passed, $fail failed"
exit $(( fail>0 ? 1 : 0 ))
