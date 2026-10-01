#!/bin/bash
# smoke-shared-accounts.sh — os consertos do modo COMPARTILHADO (USERS_FROM=treino), 28/09/2026:
#   • criar conta por cima do dir de quem já submeteu NÃO zera o history (user-add/users-bulk/criação);
#   • desabilitar / desclassificar / remover participante compartilhado funciona (antes: 404) — overlay
#     local com senha `!…` autoritativa; {undo} devolve a entrada pela conta do treino;
#   • remover barra até quem nunca entrou (tombstone invisível no placar);
#   • a lista de contas mostra quem só tem dir (selo shared/dir_only), nome buscado na fonte por caminho;
#   • users-set-password num contest compartilhado = 409 shared_users;
#   • trocar o handle no treino leva o dir de TODO contest compartilhado (e barra com submissão pendente);
#   • duplicar um contest compartilhado NÃO herda o compartilhamento (só se pedido).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
fx_owners_index "$FIX"   # índice de problemas da fixture (nunca o banco real da máquina)
T="$FIX/treino"; mkdir -p "$T/var/jsons"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\n' > "$T/conf"
for u in ana bia caio duda eva fabio; do fx_user "$T" "$u" "s-$u" "Nome ${u^}"; done
fx_user "$T" prof.admin pa "Prof"
printf '{"threshold":0,"allow":["prof.admin"],"deny":[]}' > "$T/var/contest-perms.json"
printf '%s' '{"id":"bankprob","title":"Banco Prob","tags":["#x"],"statement_html_b64":"PGgxPm9pPC9oMT4="}' > "$T/var/jsons/bankprob.json"
printf 'CONTEST=treino\nLOGIN=prof.admin\nUSERFULLNAME=Prof\nLOGINAT=1\n' > "$SESS/tprof"
NOW="$(date +%s)"; FUT=$(( NOW + 100000 ))
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-x}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" MOJ_JOBS_SYNC=1 bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
login(){ call /auth/login POST "{\"username\":\"$2\",\"password\":\"$3\"}" none "contest=$1"; }
st(){ sed -n 's/^Status: \([0-9]*\).*/\1/p' <<<"$OUT" | head -1; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: $(st) ${BODY:0:200}"; ((fail++)); fi; }

call /treino/contest-create/create POST "{\"id\":\"sh\",\"name\":\"Prova\",\"mode\":\"icpc\",\"end\":$FUT,\"users_from\":\"treino\",\"admin\":{\"login\":\"prof\"},\"problems\":[{\"bank_id\":\"bankprob\",\"name\":\"P\"}]}" tprof
[[ "$(st)" == 200 ]] || { echo "SETUP FAIL: $BODY"; exit 1; }
C="$FIX/sh"
printf 'CONTEST=sh\nLOGIN=prof.admin\nUSERFULLNAME=Prof\nLOGINAT=1\n' > "$SESS/adm"
# participantes que já ENTRARAM/SUBMETERAM: dir local sem account.json (como o /submit cria)
for u in ana bia caio duda; do mkdir -p "$C/users/$u/submissions"; printf '%s:A:C:Accepted:%s:s-%s\n' 60 "$NOW" "$u" > "$C/users/$u/history"; done

echo "== lista de contas: quem só tem dir aparece =="
call /contest/admin/users GET '' adm 'contest=sh'
ck "ana (só dir) listada com shared:true, dir_only:true e o nome da fonte" '[[ "$(jq -r ".users[]|select(.login==\"ana\")|[.shared,.dir_only,.fullname]|join(\"|\")" <<<"$BODY")" == "true|true|Nome Ana" ]]'
ck "quem nunca entrou (eva) não aparece" '[[ -z "$(jq -r ".users[]|select(.login==\"eva\")" <<<"$BODY")" ]]'

echo "== desabilitar compartilhado =="
login sh ana s-ana; ck "(controle) ana entra pela conta do treino" '[[ "$(st)" == 200 ]]'
call /contest/admin/user-disable POST '{"login":"ana"}' adm 'contest=sh'
ck "desabilitar ana → 200 (antes 404) e overlay local com !…" '[[ "$(st)" == 200 && "$(jq -r ".password|startswith(\"!\")" "$C/users/ana/account.json")" == true ]]'
ck "…o history de ana intacto" 'grep -q ":s-ana$" "$C/users/ana/history"'
login sh ana s-ana; ck "ana desabilitada não entra mais com a senha do treino" '[[ "$(st)" != 200 ]]'
call /contest/admin/user-disable POST '{"login":"ana","undo":true}' adm 'contest=sh'
login sh ana s-ana; ck "undo: ana volta a entrar com a senha do treino" '[[ "$(st)" == 200 ]]'
call /contest/admin/user-disable POST '{"login":"eva"}' adm 'contest=sh'
ck "desabilitar quem nunca entrou → 404 (use remover)" '[[ "$(st)" == 404 && ! -e "$C/users/eva" ]]'

echo "== desclassificar compartilhado =="
call /contest/admin/user-disqualify POST '{"login":"bia"}' adm 'contest=sh'
ck "desclassificar bia → 200 (antes 404) e marca no overlay" '[[ "$(st)" == 200 && "$(jq -r .disqualified "$C/users/bia/account.json")" == true ]]'
login sh bia s-bia; ck "desclassificada continua entrando (≠ desabilitar)" '[[ "$(st)" == 200 ]]'

echo "== remover compartilhado =="
call /contest/admin/user-remove POST '{"login":"caio"}' adm 'contest=sh'
ck "remover caio → 200, dir vai p/ .removed-users" '[[ "$(st)" == 200 ]] && ls "$C/.removed-users" | grep -q "^caio-"'
login sh caio s-caio; ck "caio removido NÃO volta pela conta do treino (tombstone)" '[[ "$(st)" != 200 && "$(jq -r .disqualified "$C/users/caio/account.json")" == true ]]'
call /contest/admin/user-remove POST '{"login":"eva"}' adm 'contest=sh'
login sh eva s-eva; ck "remover quem nunca entrou barra a entrada dele" '[[ "$(st)" != 200 ]]'
call /contest/admin/user-remove POST '{"login":"ninguem"}' adm 'contest=sh'
ck "remover login que não existe em lugar nenhum → 404" '[[ "$(st)" == 404 ]]'

echo "== criar conta por cima de quem já submeteu não zera o history =="
call /contest/admin/user-add POST '{"login":"duda","password":"local1","fullname":"Duda"}' adm 'contest=sh'
ck "user-add sobre o dir de duda: 200 e history preservado" '[[ "$(st)" == 200 ]] && grep -q ":s-duda$" "$C/users/duda/history"'

echo "== troca de senha geral num contest compartilhado =="
call /contest/admin/users-set-password POST '{"password":"x9"}' adm 'contest=sh'
ck "users-set-password → 409 shared_users" '[[ "$(st)" == 409 && "$(jq -r .error.code <<<"$BODY")" == shared_users ]]'

echo "== rename no treino leva o dir do contest compartilhado =="
mkdir -p "$C/users/fabio"; printf '1:A:C:Accepted:%s:s-fabio\n' "$NOW" > "$C/users/fabio/history"
printf 'CONTEST=treino\nLOGIN=fabio\nUSERFULLNAME=Fabio\nLOGINAT=1\n' > "$SESS/tfab"
printf 'CONTEST=sh\nLOGIN=fabio\nUSERFULLNAME=Fabio\nLOGINAT=1\n' > "$SESS/sfab"
printf '2:A:C:Not Answered Yet:%s:s-f2\n' "$NOW" >> "$C/users/fabio/history"
call /treino/profile/username POST '{"new_username":"fabio2"}' tfab
ck "submissão pendente no contest compartilhado barra o rename (409)" '[[ "$(st)" == 409 && "$(jq -r .error.code <<<"$BODY")" == uname_pending ]]'
sed -i '/Not Answered Yet/d' "$C/users/fabio/history"
call /treino/profile/username POST '{"new_username":"fabio2"}' tfab
ck "rename 200; o dir do contest compartilhado seguiu (history junto)" '[[ "$(st)" == 200 && ! -e "$C/users/fabio" ]] && grep -q ":s-fabio$" "$C/users/fabio2/history"'
ck "…e a sessão do contest compartilhado seguiu o nome" 'grep -q "^LOGIN=fabio2$" "$SESS/sfab"'

echo "== duplicar um contest compartilhado não herda o compartilhamento =="
call /treino/contest-create/duplicate POST '{"from":"sh","id":"sh-copia","admin":{"login":"prof","password":"novo"}}' tprof
ck "cópia sem USERS_FROM" '[[ "$(st)" == 200 ]] && ! grep -q "^USERS_FROM=" "$FIX/sh-copia/conf"'
call /treino/contest-create/duplicate POST '{"from":"sh","id":"sh-copia2","users_from":"treino"}' tprof
ck "…a não ser que peça explicitamente" '[[ "$(st)" == 200 ]] && grep -q "^USERS_FROM=treino" "$FIX/sh-copia2/conf"'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
