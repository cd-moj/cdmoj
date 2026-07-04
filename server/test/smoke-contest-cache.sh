#!/bin/bash
# Cache preguiçoso de placar e estatísticas (regenera só quando a fonte muda; gera
# na hora se nada existe) + arquivo completo de contests encerrados (/index/contests?all=1).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; SPOOL="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$SPOOL"' EXIT

# --- contest (store v2) com history mas SEM placar ---
C="$FIX/lazy"; mkdir -p "$C/users/alice" "$C/users/bob" "$C/var"
{ printf 'CONTEST_ID=lazy\nCONTEST_TYPE=icpc\nCONTEST_NAME=Lazy\nCONTEST_START=1000\nCONTEST_END=2000\n'
  printf 'USER_STORE=v2\n'
  printf "PROBS=(f0 p/um Um A k0 f1 p/dois Dois B k1)\n"; } > "$C/conf"
printf 'lazy.admin:p:Admin\nalice:a:Alice\nbob:b:Bob\n' > "$C/passwd"
for u in alice bob; do
  jq -n --arg l "$u" '{login:$l,password:"x",fullname:$l,email:"",created_at:0,updated_at:0,status:"active",uname_changes:[]}' > "$C/users/$u/account.json"
done
printf '5:p#um:C:Accepted,100p:1718000000:h1\n' > "$C/users/alice/history"
{ printf '3:p#um:CPP:Wrong Answer:1718000010:h2\n'
  printf '2:p#dois:PY:Accepted,100p:1718000020:h3\n'; } > "$C/users/bob/history"
printf 'CONTEST=lazy\nLOGIN=lazy.admin\nLOGINAT=1\n' > "$SESS/adm"

# 22 contests encerrados extras p/ provar a paginação/arquivo (>20)
for i in $(seq -w 1 22); do d="$FIX/zz$i"; mkdir -p "$d"
  printf 'CONTEST_ID=zz%s\nCONTEST_NAME=Closed %s\nCONTEST_START=1000\nCONTEST_END=2000\n' "$i" "$i" > "$d/conf"; done

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-adm}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" SPOOLDIR="$SPOOL" SCOREDIR="$ROOT/score" bash "$ROUTER" <<<"${3:-}" 2>&1)"; \
    BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:160}"; ((fail++)); fi; }
mt(){ stat -c %Y "$1" 2>/dev/null || echo 0; }

echo "== placar: geração preguiçosa =="
placar="$C/var/placar.txt"
ck "placar não existe antes" '[[ ! -f "$placar" ]]'
call /contest/score GET '' '' 'contest=lazy'
ck "score 200" '[[ "$OUT" == *"Status: 200"* ]]'
ck "1ª linha = modo icpc" '[[ "$(head -1 <<<"$BODY")" == icpc ]]'
ck "placar foi gerado na hora" '[[ -s "$placar" ]]'
ck "tem ao menos uma linha de equipe (alice)" '[[ "$BODY" == *alice* ]]'

echo "== placar: cache estável e invalidação =="
T1="$(mt "$placar")"; sleep 1; call /contest/score GET '' '' 'contest=lazy'; T2="$(mt "$placar")"
ck "2ª chamada NÃO regerou (cache)" '[[ "$T1" == "$T2" ]]'
sleep 1; touch "$C/var/.score-dirty"; call /contest/score GET '' '' 'contest=lazy'; T3="$(mt "$placar")"
ck "history mudou (.score-dirty) -> placar regerado" '[[ "$T3" != "$T2" ]]'

echo "== estatísticas: cache preguiçoso =="
cache="$C/var/statistics.cache.json"
ck "cache de stats não existe antes" '[[ ! -f "$cache" ]]'
call /contest/statistics GET '' adm 'contest=lazy'
ck "stats 200" '[[ "$OUT" == *"Status: 200"* ]]'
ck "cache de stats criado" '[[ -s "$cache" ]]'
ck "stats: users=2 (privilegiado fora), problema A letra=A" '[[ "$(jq -r .totals.users <<<"$BODY")" == 2 && "$(jq -r ".problems[0].short_name" <<<"$BODY")" == A ]]'
S1="$(mt "$cache")"; sleep 1; call /contest/statistics GET '' adm 'contest=lazy'; S2="$(mt "$cache")"
ck "2ª chamada serviu do cache" '[[ "$S1" == "$S2" ]]'
sleep 1; touch "$C/var/.score-dirty"; call /contest/statistics GET '' adm 'contest=lazy'; S3="$(mt "$cache")"
ck "history mudou (.score-dirty) -> cache regerado" '[[ "$S3" != "$S2" ]]'

echo "== arquivo de encerrados: /index/contests?all=1 =="
call /index/contests GET '' '' ''
TOTAL="$(jq -r .closed.total <<<"$BODY")"
ck "default pagina em 20 (per_page)" '[[ "$(jq -r .closed.per_page <<<"$BODY")" == 20 ]]'
ck "há mais de 20 encerrados no fixture" '[[ "$TOTAL" -gt 20 ]]'
ck "default devolve só 20 itens" '[[ "$(jq -r ".closed.items|length" <<<"$BODY")" == 20 ]]'
call /index/contests GET '' '' 'all=1'
ck "all=1 devolve TODOS (items==total)" '[[ "$(jq -r ".closed.items|length" <<<"$BODY")" == "$(jq -r .closed.total <<<"$BODY")" ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
