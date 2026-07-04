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

TOK="tok-alice"
printf 'CONTEST="treino"\nLOGIN="alice"\nUSERFULLNAME="Alice Tester"\nLOGINAT=1700000000\n' > "$SESS/$TOK"

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="" HTTP_AUTHORIZATION="Bearer $TOK" \
  CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
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
ck "sessão atualizada"    'grep -q "LOGIN=\"alice2\"" "$SESS/$TOK"'
ck "remaining = 1"        '[[ "$(jq -r .username_changes_remaining <<<"$BODY")" == 1 ]]'

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

echo ""
echo "RESULT: $pass passed, $fail failed"
exit $(( fail>0 ? 1 : 0 ))
