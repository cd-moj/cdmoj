#!/bin/bash
# smoke-shared-roles.sh — CONTEST COMPARTILHADO × PAPÉIS (28/09/2026).
# Num contest com USERS_FROM a senha pode ser conferida no TREINO, e o papel vem só do sufixo do login.
# Antes: qualquer .admin/.judge/.staff do treino entrava com esse papel em TODO contest compartilhado (na
# produção, o .admin de um professor administrava a prova de outro). Agora, pela fonte, conta de papel só
# entra se for o admin DONO (SHARED_ADMIN, ou o derivado do `owner`) ou um SUPERADMIN. Afirma também:
#   • a senha LOCAL é autoritativa (conta local criada pelo admin não aceita mais a senha do treino);
#   • a criação só reusa o .admin do PRÓPRIO criador (o de outro = 422 admin_login_foreign) e grava SHARED_ADMIN;
#   • o SHARED_ADMIN segue o rename da conta (lib/owner-rename.sh);
#   • server/bin/shared-admin-audit.sh relata e o --apply grava.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
fx_owners_index "$FIX"   # índice de problemas da fixture (nunca o banco real da máquina)
T="$FIX/treino"; mkdir -p "$T/var/jsons"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\nSUPERADMINS=chefe.admin\n' > "$T/conf"
fx_user "$T" aluno a "Aluno"
fx_user "$T" aluno2 a2 "Aluno Dois"
fx_user "$T" prof p "Prof (conta comum)"
fx_user "$T" prof.admin pa "Prof Admin"
fx_user "$T" outro.admin oa "Outro Professor"
fx_user "$T" juiz.judge jj "Juiz do treino"
fx_user "$T" sala.staff ss "Staff do treino"
fx_user "$T" chefe.admin ca "Super"
printf '{"threshold":0,"allow":["prof","prof.admin"],"deny":[]}' > "$T/var/contest-perms.json"
printf '%s' '{"id":"bankprob","title":"Banco Prob","tags":["#x"],"statement_html_b64":"PGgxPm9pPC9oMT4="}' > "$T/var/jsons/bankprob.json"
printf 'CONTEST=treino\nLOGIN=prof\nUSERFULLNAME=Prof\nLOGINAT=1\n' > "$SESS/tprof"
printf 'CONTEST=treino\nLOGIN=prof.admin\nUSERFULLNAME=Prof\nLOGINAT=1\n' > "$SESS/tprofadm"

NOW="$(date +%s)"; FUT=$(( NOW + 100000 ))
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-x}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
login(){ call /auth/login POST "{\"username\":\"$2\",\"password\":\"$3\"}" none "contest=$1"; }
st(){ sed -n 's/^Status: \([0-9]*\).*/\1/p' <<<"$OUT" | head -1; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: $(st) ${BODY:0:200}"; ((fail++)); fi; }

echo "== criação: só o .admin do PRÓPRIO criador é reusado =="
SPEC(){ printf '{"id":"%s","name":"Prova","mode":"icpc","end":%s,"users_from":"treino","admin":{"login":"%s"},"problems":[{"bank_id":"bankprob","name":"P"}]}' "$1" "$FUT" "$2"; }
call /treino/contest-create/create POST "$(SPEC sh-bad outro)" tprof
ck "indicar o .admin de OUTRO professor sem senha → 422 admin_login_foreign" '[[ "$(st)" == 422 && "$(jq -r .error.code <<<"$BODY")" == admin_login_foreign && ! -d "$FIX/sh-bad" ]]'
call /treino/contest-create/create POST "$(SPEC sh-c prof)" tprof
ck "o próprio .admin é reusado (sem conta local) e SHARED_ADMIN gravado" '[[ "$(st)" == 200 && "$(jq -r .admin_reused <<<"$BODY")" == true && ! -e "$FIX/sh-c/users/prof.admin/account.json" ]] && grep -qx "SHARED_ADMIN=prof.admin" "$FIX/sh-c/conf"'

echo "== login pela conta do treino =="
login sh-c aluno a;        ck "competidor do treino entra" '[[ "$(st)" == 200 ]]'
login sh-c prof.admin pa;  ck "o admin DONO entra pela conta do treino" '[[ "$(st)" == 200 ]]'
login sh-c chefe.admin ca; ck "SUPERADMIN entra pela conta do treino" '[[ "$(st)" == 200 ]]'
login sh-c outro.admin oa; ck ".admin de OUTRO professor NÃO entra" '[[ "$(st)" != 200 ]]'
login sh-c juiz.judge jj;  ck ".judge do treino NÃO entra" '[[ "$(st)" != 200 ]]'
login sh-c sala.staff ss;  ck ".staff do treino NÃO entra" '[[ "$(st)" != 200 ]]'

echo "== sessão já aberta de papel alheio morre =="
printf 'CONTEST=sh-c\nLOGIN=outro.admin\nUSERFULLNAME=Outro\nLOGINAT=1\n' > "$SESS/sout"
printf 'CONTEST=sh-c\nLOGIN=juiz.judge\nUSERFULLNAME=Juiz\nLOGINAT=1\n' > "$SESS/sjuiz"
printf 'CONTEST=sh-c\nLOGIN=prof.admin\nUSERFULLNAME=Prof\nLOGINAT=1\n' > "$SESS/sdono"
call /contest/admin/config GET '' sout 'contest=sh-c';  ck "sessão do .admin alheio → 401" '[[ "$(st)" == 401 ]]'
call /contest/admin/config GET '' sjuiz 'contest=sh-c'; ck "sessão do .judge do treino → 401" '[[ "$(st)" == 401 ]]'
call /contest/admin/config GET '' sdono 'contest=sh-c'; ck "sessão do dono segue valendo" '[[ "$(st)" == 200 ]]'

echo "== contas LOCAIS =="
fx_user "$FIX/sh-c" juiz2.judge j2 "Juiz local"
login sh-c juiz2.judge j2; ck "juiz LOCAL do contest entra" '[[ "$(st)" == 200 ]]'
fx_user "$FIX/sh-c" aluno2 nova "Aluno Dois (local)"
login sh-c aluno2 a2;   ck "senha LOCAL é autoritativa: a do treino não entra mais" '[[ "$(st)" != 200 ]]'
login sh-c aluno2 nova; ck "…e a local entra" '[[ "$(st)" == 200 ]]'

echo "== SHARED_ADMIN explícito manda; sem ele, vale o dono =="
printf 'SHARED_ADMIN=outro.admin\n' >> "$FIX/sh-c/conf"
sed -i '/^SHARED_ADMIN=prof.admin$/d' "$FIX/sh-c/conf"
login sh-c outro.admin oa; ck "com SHARED_ADMIN=outro.admin, ele entra" '[[ "$(st)" == 200 ]]'
login sh-c prof.admin pa;  ck "…e o derivado do dono deixa de valer" '[[ "$(st)" != 200 ]]'
sed -i '/^SHARED_ADMIN=/d' "$FIX/sh-c/conf"
login sh-c prof.admin pa;  ck "contest antigo sem SHARED_ADMIN: vale o derivado do owner" '[[ "$(st)" == 200 ]]'

echo "== auditoria (server/bin/shared-admin-audit.sh) =="
AUD="$(CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROOT/bin/shared-admin-audit.sh" 2>&1)"
ck "relata o contest, o admin alcançável e a sessão de papel que o corte derruba" 'grep -q "^sh-c" <<<"$AUD" && grep -q "alcançável depois do corte: sim" <<<"$AUD" && grep -q "derruba: .*outro.admin" <<<"$AUD"'
ck "dry-run não grava" '! grep -q "^SHARED_ADMIN=" "$FIX/sh-c/conf"'
CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROOT/bin/shared-admin-audit.sh" --apply >/dev/null 2>&1
ck "--apply grava SHARED_ADMIN=<dono>.admin" 'grep -qx "SHARED_ADMIN=prof.admin" "$FIX/sh-c/conf"'
mkdir -p "$FIX/sem-admin/users"; printf 'CONTEST_ID=sem-admin\nUSERS_FROM=treino\n' > "$FIX/sem-admin/conf"; printf 'ninguem\n' > "$FIX/sem-admin/owner"
AUD="$(CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROOT/bin/shared-admin-audit.sh" 2>&1)"; rc=$?
ck "contest sem admin alcançável: ⚠ e saída ≠ 0" '[[ $rc != 0 ]] && grep -q "SEM ADMIN depois do corte" <<<"$AUD"'

echo "== o SHARED_ADMIN segue o rename da conta =="
( export CONTESTSDIR="$FIX"; _DIR="$ROOT/api/v1"; source "$ROOT/api/v1/lib/common.sh" >/dev/null 2>&1
  source "$ROOT/api/v1/lib/owner-rename.sh" >/dev/null 2>&1; owner_rename_fast prof.admin mestre.admin >/dev/null )
ck "rename prof.admin → mestre.admin reescreve o SHARED_ADMIN" 'grep -qx "SHARED_ADMIN=mestre.admin" "$FIX/sh-c/conf" && ! grep -q "prof.admin" "$FIX/sh-c/conf"'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
