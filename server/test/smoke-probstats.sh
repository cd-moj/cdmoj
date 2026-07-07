#!/bin/bash
# Testa /treino/problem-stats (métricas, por-linguagem, editores, avatares, cache).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
T="$FIX/treino"; mkdir -p "$T/var/jsons"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\n' > "$T/conf"
fx_user "$T" alice s "Alice A"
fx_user "$T" bob s "Bob B"
fx_user "$T" carol s "Carol C"
fx_user "$T" dave s "Dave D"
fx_user "$T" zoe s "Zoe Z"
echo '{"id":"p#x","title":"Prob X"}' > "$T/var/jsons/p#x.json"
cat > "$T/users/alice/history" <<'EOF'
100:p#x:C:Wrong Answer:100:s1
200:p#x:C:Accepted,100p:200:s2
500:p#x:py3:Accepted,100p:500:s5
EOF
printf '300:p#x:C:Accepted,100p:300:s3\n' > "$T/users/bob/history"
printf '400:p#x:py3:Accepted,100p:400:s4\n' > "$T/users/carol/history"
printf '600:p#x:C:Wrong Answer:600:s6\n' > "$T/users/dave/history"
printf '700:other#y:C:Accepted,100p:700:s7\n' > "$T/users/zoe/history"
jq '.public=true | .favorite_editor="vim"' "$T/users/alice/account.json" > "$T/users/alice/a.n" && mv "$T/users/alice/a.n" "$T/users/alice/account.json"
jq '.public=false | .favorite_editor="emacs"' "$T/users/bob/account.json" > "$T/users/bob/a.n" && mv "$T/users/bob/a.n" "$T/users/bob/account.json"
jq '.favorite_editor="vim"' "$T/users/carol/account.json" > "$T/users/carol/a.n" && mv "$T/users/carol/a.n" "$T/users/carol/account.json"

call(){ OUT="$(PATH_INFO=/treino/problem-stats REQUEST_METHOD=GET QUERY_STRING="id=p#x" \
  CONTESTSDIR="$FIX" SESSIONDIR="$FIX/s" bash "$ROUTER" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

call
J(){ jq -r "$1" <<<"$BODY"; }
ck "total submissions = 6 (ignora outro problema)" '[[ "$(J .total_submissions)" == 6 ]]'
ck "distinct attempted = 4"   '[[ "$(J .distinct_attempted)" == 4 ]]'
ck "distinct solved = 3"      '[[ "$(J .distinct_solved)" == 3 ]]'
ck "acceptance ~0.667"        '[[ "$(J "(.acceptance_rate*1000|floor)")" == 666 ]]'
ck "C: solvers distintos = 2" '[[ "$(J ".by_language[]|select(.lang==\"c\").solvers")" == 2 ]]'
ck "C: submissões = 4"        '[[ "$(J ".by_language[]|select(.lang==\"c\").submissions")" == 4 ]]'
ck "py (history .py3 legado): solvers distintos = 2" '[[ "$(J ".by_language[]|select(.lang==\"py\").solvers")" == 2 ]]'
ck "editores: vim = 2"        '[[ "$(J ".editors[]|select(.editor==\"vim\").count")" == 2 ]]'
ck "editores: emacs = 1 (conta mesmo privado)" '[[ "$(J ".editors[]|select(.editor==\"emacs\").count")" == 1 ]]'
ck "avatares públicos = 2 (bob privado fora)" '[[ "$(J ".solver_avatars|length")" == 2 ]]'
ck "solvers_public_count = 2" '[[ "$(J .solvers_public_count)" == 2 ]]'
ck "avatar tem nome do account" '[[ "$(J ".solver_avatars[]|select(.login==\"alice\").name")" == "Alice A" ]]'
ck "não vaza lista solvers"   '[[ "$(J "has(\"solvers\")")" == "false" ]]'
ck "cache criado"             '[[ -f "$T/var/problem-stats/p#x.json" ]]'

# 2ª chamada deve vir do cache (mesmo conteúdo; não regenera)
cp "$T/var/problem-stats/p#x.json" "$FIX/snap"
call
ck "2ª chamada idêntica (cache)" 'diff -q <(echo "$BODY") "$FIX/snap" >/dev/null'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
