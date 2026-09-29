#!/bin/bash
# Sorteio com problemas PRIVADOS (opt-in include_private=1) — admin do contest (/contest/admin/draw,
# /contest/admin/bank?meta=1) e wizard (/treino/contest-create/{draw,tags,collections}):
#   • padrão = só públicos (ninguém recebe privado sem pedir; a prova em elaboração de um colega
#     da org não cai num sorteio por tag);
#   • com include: dono, colaborador e membro da org (owners_visible_for); privado alheio nunca;
#     cada sorteado traz private/access; despublicado recém sai UMA vez, como privado;
#   • admin: o sujeito é o DONO do contest; contest sem owner = só públicos, e o login local
#     (boss.admin) NÃO puxa os privados de um homônimo do treino;
#   • tags/coleções do painel somam os privados só com include;
#   • índice de owners quebrado + include = 503 (nunca lista vazia calada); sem include segue 200.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; NOTOOLS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$NOTOOLS"' EXIT
# sem o gerador do índice: índice quebrado NÃO se regenera (é o caso do 503)
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" MOJTOOLS_DIR="$NOTOOLS"
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
T="$FIX/treino"; mkdir -p "$T/var/jsons" "$T/var/jsons-private"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\n' > "$T/conf"
fx_user "$T" regular s "Regular"
fx_user "$T" eve s "Eve"
fx_user "$T" boss.admin s "Homônimo do admin local"
printf '{"threshold":0,"allow":["regular","eve"],"deny":[]}' > "$T/var/contest-perms.json"
printf 'CONTEST=treino\nLOGIN=regular\nUSERFULLNAME=Regular\nLOGINAT=1\n' > "$SESS/reg"
printf 'CONTEST=treino\nLOGIN=eve\nUSERFULLNAME=Eve\nLOGINAT=1\n' > "$SESS/eve"
echo '{"myorg":{"members":["regular"],"admins":["eve"],"created_by":"eve","title":"My Org","public_allowed":false}}' > "$T/var/orgs.json"
# banco público (cache var/jsons): bankprob + priv#dup (despublicado recém: o cache ainda o lista)
printf '%s' '{"id":"bankprob","title":"Banco","tags":["#pub"],"collections":["Aula"]}' > "$T/var/jsons/bankprob.json"
printf '%s' '{"id":"priv#dup","title":"Despublicado","tags":["#pub"]}' > "$T/var/jsons/priv#dup.json"
# privados: o enunciado em base64 fica no arquivo; do arquivo o sorteio só lê as tags
for p in priv#mine priv#collab myorg#p priv#other boss#h priv#dup; do
  printf '{"id":"%s","title":"%s","tags":["#priv"],"statement_html_b64":"PHA+czwvcD4="}' "$p" "$p" > "$T/var/jsons-private/$p.json"
done
OWNERS='{"problems":[
 {"id":"bankprob","title":"Banco","owner":"someone","collaborators":[],"public":true,"collections":["Aula"]},
 {"id":"priv#mine","title":"Meu","owner":"regular","collaborators":[],"public":false,"collections":["Aula"]},
 {"id":"priv#collab","title":"Colab","owner":"eve","collaborators":["regular"],"public":false},
 {"id":"myorg#p","title":"Da org","owner":"eve","collaborators":[],"public":false,"repo":"myorg"},
 {"id":"priv#other","title":"Alheio","owner":"eve","collaborators":[],"public":false},
 {"id":"boss#h","title":"Do homônimo","owner":"boss.admin","collaborators":[],"public":false},
 {"id":"priv#dup","title":"Despublicado","owner":"regular","collaborators":[],"public":false}
]}'
printf '%s' "$OWNERS" > "$T/var/problem-owners.json"
NOW="$(date +%s)"; FUT=$(( NOW + 100000 ))
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-reg}" \
    bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
J(){ jq -r "$1" <<<"$BODY" 2>/dev/null; }
IDS(){ jq -rc '[.problems[].id]|sort' <<<"$BODY" 2>/dev/null; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:300}"; ((fail++)); fi; }

# contest do regular (owner = regular) e um contest legado (sem owner)
for c in dp-c dp-leg; do
  call /treino/contest-create/create POST "{\"id\":\"$c\",\"name\":\"$c\",\"mode\":\"icpc\",\"end\":$FUT,\"admin\":{\"login\":\"boss\",\"password\":\"sek\",\"fullname\":\"Boss\"},\"problems\":[{\"bank_id\":\"bankprob\",\"name\":\"P1\",\"letter\":\"A\"}]}" reg
  [[ "$(J .admin_login)" == boss.admin ]] || { echo "SETUP FAIL ($c): $BODY"; exit 1; }
  printf 'CONTEST=%s\nLOGIN=boss.admin\nUSERFULLNAME=Boss\nLOGINAT=1\n' "$c" > "$SESS/adm-$c"
done
[[ "$(head -1 "$FIX/dp-c/owner")" == regular ]] || { echo "SETUP FAIL: owner"; exit 1; }
rm -f "$FIX/dp-leg/owner"
PUB='["bankprob","priv#dup"]'
REG='["bankprob","myorg#p","priv#collab","priv#dup","priv#mine"]'

echo "== admin: padrão = só públicos =="
call /contest/admin/draw GET '' adm-dp-c 'contest=dp-c&count=100&seed=1'
ck "draw sem include: só o banco público"          '[[ "$(IDS)" == "$PUB" && "$(J .private_included)" == false ]]'
ck "…e todo sorteado vem private:false/public"      '[[ "$(J "[.problems[]|select(.private or .access!=\"public\")]|length")" == 0 ]]'
call /contest/admin/bank GET '' adm-dp-c 'contest=dp-c&meta=1'
ck "meta sem include: sem as tags dos privados"     '[[ "$(J "[.tags[].tag]|index(\"#priv\")")" == null && "$(J .private_included)" == false ]]'

echo "== admin: include_private=1 (sujeito = dono do contest) =="
call /contest/admin/draw GET '' adm-dp-c 'contest=dp-c&count=100&seed=1&include_private=1'
ck "dono, colaborador e org entram; alheio e homônimo não" '[[ "$(IDS)" == "$REG" && "$(J .private_included)" == true ]]'
ck "access: mine / shared / public"                 '[[ "$(J "[.problems[]|select(.id==\"priv#mine\")][0].access")" == mine && "$(J "[.problems[]|select(.id==\"priv#collab\")][0].access")" == shared && "$(J "[.problems[]|select(.id==\"myorg#p\")][0].access")" == shared && "$(J "[.problems[]|select(.id==\"bankprob\")][0].access")" == public ]]'
ck "despublicado recém: uma vez só, como privado"   '[[ "$(J "[.problems[]|select(.id==\"priv#dup\")]|length")" == 1 && "$(J "[.problems[]|select(.id==\"priv#dup\")][0].private")" == true ]]'
ck "tags do privado vêm do jsons-private"           '[[ "$(J "[.problems[]|select(.id==\"priv#mine\")][0].tags|index(\"#priv\")")" == 0 ]]'
D1="$(IDS)"; call /contest/admin/draw GET '' adm-dp-c 'contest=dp-c&count=3&seed=7&include_private=1'; D1="$(J '[.problems[].id]|join(",")')"
call /contest/admin/draw GET '' adm-dp-c 'contest=dp-c&count=3&seed=7&include_private=1'
ck "reproduzível por seed com privados"             '[[ "$(J "[.problems[].id]|join(\",\")")" == "$D1" && -n "$D1" ]]'
call /contest/admin/draw GET '' adm-dp-c 'contest=dp-c&count=100&include_private=1&collections=%5B%22Aula%22%5D'
ck "coleção filtra privados também"                 '[[ "$(IDS)" == "[\"bankprob\",\"priv#mine\"]" ]]'
call /contest/admin/draw GET '' adm-dp-c 'contest=dp-c&count=100&include_private=1&tags=%23priv'
ck "tag só dos privados"                            '[[ "$(IDS)" == "[\"myorg#p\",\"priv#collab\",\"priv#dup\",\"priv#mine\"]" ]]'
call /contest/admin/bank GET '' adm-dp-c 'contest=dp-c&meta=1&include_private=1'
ck "meta com include: #priv conta os 4 do dono"     '[[ "$(J "[.tags[]|select(.tag==\"#priv\")][0].count")" == 4 && "$(J .private_included)" == true ]]'
ck "meta com include: coleção Aula = 2"             '[[ "$(J "[.collections[]|select(.collection==\"Aula\")][0].count")" == 2 ]]'

echo "== admin: contest sem owner = só públicos (sem homonímia) =="
call /contest/admin/draw GET '' adm-dp-leg 'contest=dp-leg&count=100&include_private=1'
ck "sem owner: include ignorado, só públicos"       '[[ "$(IDS)" == "$PUB" && "$(J .private_included)" == false ]]'
ck "…e o boss#h do homônimo boss.admin não vaza"    '[[ "$(J "[.problems[].id]|index(\"boss#h\")")" == null ]]'
call /contest/admin/bank GET '' adm-dp-leg 'contest=dp-leg&meta=1&include_private=1'
ck "sem owner: meta sem privados"                   '[[ "$(J "[.tags[].tag]|index(\"#priv\")")" == null && "$(J .private_included)" == false ]]'
call /contest/admin/draw GET '' reg 'contest=dp-c&count=2&include_private=1'
ck "sessão do treino (não admin do contest): 403"   '[[ "$OUT" == *"Status: 403"* ]]'

echo "== wizard: sujeito = quem cria =="
call /treino/contest-create/draw GET '' reg 'count=100&seed=1'
ck "wizard sem include: só públicos"                '[[ "$(IDS)" == "$PUB" && "$(J .private_included)" == false ]]'
call /treino/contest-create/draw GET '' reg 'count=100&seed=1&include_private=1'
ck "wizard com include (regular)"                   '[[ "$(IDS)" == "$REG" && "$(J .private_included)" == true ]]'
call /treino/contest-create/draw GET '' eve 'count=100&seed=1&include_private=1'
ck "wizard com include (eve): os dela, não o do regular" '[[ "$(IDS)" == "[\"bankprob\",\"myorg#p\",\"priv#collab\",\"priv#dup\",\"priv#other\"]" ]]'
ck "…e o priv#dup do regular volta a ser público p/ ela" '[[ "$(J "[.problems[]|select(.id==\"priv#dup\")][0].access")" == public ]]'
call /treino/contest-create/tags GET '' reg ''
ck "wizard tags sem include: sem #priv"             '[[ "$(J "[.tags[].tag]|index(\"#priv\")")" == null ]]'
call /treino/contest-create/tags GET '' reg 'include_private=1'
ck "wizard tags com include: #priv = 4"             '[[ "$(J "[.tags[]|select(.tag==\"#priv\")][0].count")" == 4 ]]'
call /treino/contest-create/collections GET '' reg 'include_private=1'
ck "wizard coleções com include: Aula = 2"          '[[ "$(J "[.collections[]|select(.collection==\"Aula\")][0].count")" == 2 ]]'
call /treino/contest-create/collections GET '' reg ''
ck "wizard coleções sem include: Aula = 1"          '[[ "$(J "[.collections[]|select(.collection==\"Aula\")][0].count")" == 1 ]]'

echo "== índice de owners quebrado =="
printf '{"problems":[' > "$T/var/problem-owners.json"
call /contest/admin/draw GET '' adm-dp-c 'contest=dp-c&count=5&include_private=1'
ck "admin draw com include: 503 index_unavailable"  '[[ "$OUT" == *"Status: 503"* && "$(J .error.code)" == index_unavailable ]]'
call /contest/admin/bank GET '' adm-dp-c 'contest=dp-c&meta=1&include_private=1'
ck "admin meta com include: 503"                    '[[ "$OUT" == *"Status: 503"* ]]'
call /contest/admin/draw GET '' adm-dp-c 'contest=dp-c&count=100'
ck "sem include segue 200 (não depende do índice)"  '[[ "$OUT" == *"Status: 200"* && "$(IDS)" == "$PUB" ]]'
for r in draw tags collections; do
  call /treino/contest-create/$r GET '' reg 'include_private=1'
  ck "wizard $r com include: 503"                   '[[ "$OUT" == *"Status: 503"* && "$(J .error.code)" == index_unavailable ]]'
done
printf '%s' "$OWNERS" > "$T/var/problem-owners.json"

echo
echo "RESULT: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
