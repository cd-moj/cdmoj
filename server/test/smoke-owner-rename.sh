#!/bin/bash
# A POSSE SEGUE O RENAME DA CONTA (lib/owner-rename.sh + treino/profile/username.sh + bin/owner-rename.sh).
# Relato (Daniel Saad, 2026-09-18): trocou o username e 201 problemas + 87 contests ficaram com o dono
# ANTIGO — sumiram de "Meus". E não é só cosmético: `owner` CONCEDE acesso (owners_visible,
# problems_denied_for); dono apontando p/ login que deixou de existir é posse solta.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; PROBS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN" "$PROBS"' EXIT
source "$HERE/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" MOJ_PROBLEMS_DIR="$PROBS" MOJ_JOBS_SYNC=1
NOW="$EPOCHSECONDS"; T="$FIX/treino"; mkdir -p "$T/var" "$RUN/tl"
printf 'CONTEST_ID=treino\nCONTEST_END=%s\n' "$((NOW+86400))" > "$T/conf"
for u in alice bob carol2; do fx_user "$T" "$u" s "$u"; printf 'CONTEST=treino\nLOGIN=%s\nUSERFULLNAME=%s\nLOGINAT=%s\n' "$u" "$u" "$NOW" > "$SESS/tok-$u"; done
echo '{"org":{"members":["alice","bob","carol2"],"admins":["alice"],"public_allowed":false,"title":"Org"}}' > "$T/var/orgs.json"
mkp(){ local P="$PROBS/org/$1"; mkdir -p "$P/tests/input" "$P/sols/good"; printf '1\n' > "$P/tests/input/t1"; printf 'x\n' > "$P/sols/good/s.c"
  jq -n --arg o "$2" '{owner:$o, public:false, display_title:"T", collections:["c1"]}' > "$P/.moj-meta.json"
  ( cd "$P" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm init ) 2>/dev/null; }
mkp p1 alice; mkp p2 bob; mkp p3 carol; mkp p4 alicea
jq -n '{problems:[
 {id:"org#p1",owner:"alice",repo:"org",prob:"p1",title:"T",public:false,collaborators:[],collections:["c1"]},
 {id:"org#p2",owner:"bob",repo:"org",prob:"p2",title:"T",public:false,collaborators:["alice"],collections:["c1"]},
 {id:"org#p3",owner:"carol",repo:"org",prob:"p3",title:"T",public:false,collaborators:[],collections:[]},
 {id:"org#p4",owner:"alicea",repo:"org",prob:"p4",title:"T",public:false,collaborators:[],collections:[]}]}' > "$T/var/problem-owners.json"
echo '{"org#p1":{"id":"org#p1","owner":"alice","repo":"org","prob":"p1","title":"T","public":false,"collaborators":[],"collections":["c1"]}}' > "$T/var/authored.json"
echo '{"c1":{"owner":"alice","created_by":"alice","at":1},"c2":{"owner":"bob","created_by":"alice","at":1}}' > "$T/var/collections.json"
echo '{"threshold":0,"allow":["alice","bob"],"deny":[],"allow_meta":{"alice":{"by":"bob","at":1},"bob":{"by":"alice","at":2}},"deny_meta":{}}' > "$T/var/contest-perms.json"
for c in ca cb cc; do mkdir -p "$FIX/$c"; printf 'CONTEST_ID=%s\n' "$c" > "$FIX/$c/conf"; done
echo alice > "$FIX/ca/owner"; echo bob > "$FIX/cb/owner"; echo carol > "$FIX/cc/owner"
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }
call(){ OUT="$(PATH_INFO="$2" REQUEST_METHOD="${3:-GET}" QUERY_STRING="" HTTP_AUTHORIZATION="Bearer tok-$1" bash "$ROUTER" <<<"${4:-}" 2>/dev/null)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
J(){ jq -r "$1" "$2"; }

echo "== troca de username leva a POSSE =="
call alice /treino/profile/username POST '{"new_username":"alice2"}'
ck "rename ok"                                  '[[ "$(jq -r .new_username <<<"$BODY")" == alice2 ]]'
ck "índice: dono de p1 = alice2"                '[[ "$(J ".problems[]|select(.id==\"org#p1\")|.owner" "$T/var/problem-owners.json")" == alice2 ]]'
ck "índice: colaborador em p2 = alice2"         '[[ "$(J ".problems[]|select(.id==\"org#p2\")|.collaborators|join(\",\")" "$T/var/problem-owners.json")" == alice2 ]]'
ck "overlay authored acompanha"                 '[[ "$(J ".[\"org#p1\"].owner" "$T/var/authored.json")" == alice2 ]]'
ck "META do pacote reescrito (durável)"         '[[ "$(J .owner "$PROBS/org/p1/.moj-meta.json")" == alice2 ]]'
ck "…preservando os outros campos do meta"      '[[ "$(J ".collections|join(\",\")" "$PROBS/org/p1/.moj-meta.json")" == c1 && "$(J .display_title "$PROBS/org/p1/.moj-meta.json")" == T ]]'
ck "…e commitado no repo do problema"           'git -C "$PROBS/org/p1" log --format=%s -1 | grep -q "dono: alice -> alice2"'
ck "contest: arquivo owner trocado"             '[[ "$(cat "$FIX/ca/owner")" == alice2 ]]'
ck "coleções: owner e created_by"               '[[ "$(J ".c1.owner" "$T/var/collections.json")" == alice2 && "$(J ".c2.created_by" "$T/var/collections.json")" == alice2 && "$(J ".c2.owner" "$T/var/collections.json")" == bob ]]'
ck "permissões: lista, chave da trilha e by"    '[[ "$(J ".allow|join(\",\")" "$T/var/contest-perms.json")" == "alice2,bob" && "$(J ".allow_meta.alice2.by" "$T/var/contest-perms.json")" == bob && "$(J ".allow_meta.bob.by" "$T/var/contest-perms.json")" == alice2 ]]'
ck "o que é dos OUTROS não muda (nem prefixo: alicea)" '[[ "$(J .owner "$PROBS/org/p2/.moj-meta.json")" == bob && "$(J .owner "$PROBS/org/p4/.moj-meta.json")" == alicea && "$(cat "$FIX/cb/owner")" == bob && "$(J ".problems[]|select(.id==\"org#p4\")|.owner" "$T/var/problem-owners.json")" == alicea ]]'
printf 'CONTEST=treino\nLOGIN=alice2\nUSERFULLNAME=a\nLOGINAT=%s\n' "$NOW" > "$SESS/tok-alice2"
call alice2 /problems/mine GET
ck "\"Meus\" lista o problema p/ o login NOVO"  '[[ "$OUT" == *"Status: 200"* ]] && grep -q "org#p1" <<<"$BODY"'

echo "== ferramenta p/ o PASSADO (carol já tinha virado carol2 antes da correção) =="
TOOL="$ROOT/bin/owner-rename.sh"
o="$(bash "$TOOL" carol carol2 2>&1)"
ck "dry-run mostra e NÃO altera"                '[[ "$o" == *dry-run* && "$(J .owner "$PROBS/org/p3/.moj-meta.json")" == carol && "$(cat "$FIX/cc/owner")" == carol ]]'
o="$(bash "$TOOL" carol carol2 --apply 2>&1)"
ck "--apply troca meta, índice e contest"       '[[ "$(J .owner "$PROBS/org/p3/.moj-meta.json")" == carol2 && "$(cat "$FIX/cc/owner")" == carol2 && "$(J ".problems[]|select(.id==\"org#p3\")|.owner" "$T/var/problem-owners.json")" == carol2 ]]'
ck "…e o relatório final zera"                  '[[ "$o" == *"restou apontando"*"\"problems_meta\":0"* ]]'
o="$(bash "$TOOL" carol carol2 --apply 2>&1)";  ck "rodar de novo é inofensivo (idempotente)" '[[ "$o" == *"commitados: 0"* ]]'
o="$(bash "$TOOL" bob carol2 --apply 2>&1)";    ck "RECUSA quando o login antigo AINDA existe (não é rename)" '[[ "$o" == *RECUSADO* && "$(J .owner "$PROBS/org/p2/.moj-meta.json")" == bob ]]'
o="$(bash "$TOOL" fantasma naoexiste --apply 2>&1)"; ck "RECUSA quando o login novo não existe" '[[ "$o" == *RECUSADO* ]]'
echo; echo "RESULT: $pass passed, $fail failed"; (( fail == 0 ))
