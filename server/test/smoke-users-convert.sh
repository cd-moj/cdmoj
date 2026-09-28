#!/bin/bash
# smoke-users-convert.sh — CONVERTER um contest com usuários do Treino Livre em contas PRÓPRIAS (28/09/2026).
# O "desfazer" do compartilhamento: POST /contest/admin/users-convert (lib/users-convert.sh). Afirma:
#   • a PRÉVIA não grava nada e conta certo: dir, sessão viva, access.log, overlay de inscrição, times,
#     membro com history, membro que perde o login, o admin do treino que ganha conta local;
#   • quem nunca tocou o contest fica de fora; da fonte só vem o nome (nada de email);
#   • execução: plan_id errado = 409 plan_changed; antes da prova basta confirm:true, durante/depois só o
#     id do contest digitado; o placar (sc_users) é o MESMO antes e depois; history intacto;
#   • depois: senha do treino não entra, a nova entra; o TIME entra com a senha única, o membro não; o
#     membro com history vira conta desabilitada (a linha fica); quem só tinha SESSÃO continua logado;
#     roster arquivado; USERS_FROM e SHARED_ADMIN fora do conf; superadmin do treino não entra mais;
#     as etiquetas saem com a senha; 2ª chamada = 409 already_converted;
#   • 2000 contas convertem em < 15 s (nada de processo por conta).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
T="$FIX/treino"; mkdir -p "$T/var/jsons"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\nSUPERADMINS=chefe.admin\n' > "$T/conf"
for u in ana bia caio dave eve fabio gil hugo ivo jose; do fx_user "$T" "$u" "s-$u" "Nome ${u^}" "$u@treino.example"; done
fx_user "$T" prof.admin pa "Prof"; fx_user "$T" chefe.admin ca "Super"
printf '{"threshold":0,"allow":["prof.admin"],"deny":[]}' > "$T/var/contest-perms.json"
printf '%s' '{"id":"bankprob","title":"Banco Prob","tags":["#x"],"statement_html_b64":"PGgxPm9pPC9oMT4="}' > "$T/var/jsons/bankprob.json"
printf 'CONTEST=treino\nLOGIN=prof.admin\nUSERFULLNAME=Prof\nLOGINAT=1\n' > "$SESS/tprof"
NOW="$(date +%s)"; FUT=$(( NOW + 100000 ))
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-x}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" MOJ_JOBS_SYNC=1 bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
login(){ call /auth/login POST "{\"username\":\"$2\",\"password\":\"$3\"}" none "contest=$1"; }
st(){ sed -n 's/^Status: \([0-9]*\).*/\1/p' <<<"$OUT" | head -1; }
J(){ jq -r "$1" <<<"$BODY" 2>/dev/null; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: $(st) ${BODY:0:300}"; ((fail++)); fi; }
rows(){ ( export CONTESTSDIR="$FIX" CONTESTDIR="$FIX/$1"; source "$ROOT/score/score-common.sh" >/dev/null 2>&1; _sc_users_compute ) | cut -d$'\x01' -f1 | sort | tr '\n' ' '; }
tree_sum(){ (cd "$FIX/$1" && find . -type f ! -name '*.lock' ! -path './var/.*' -print0 | sort -z | xargs -0 md5sum | md5sum); }

# contest que ainda NÃO começou (start no futuro), admin = o do treino (reusado)
call /treino/contest-create/create POST "{\"id\":\"cv\",\"name\":\"Prova\",\"mode\":\"icpc\",\"start\":$(( NOW + 3600 )),\"end\":$FUT,\"users_from\":\"treino\",\"admin\":{\"login\":\"prof\"},\"problems\":[{\"bank_id\":\"bankprob\",\"name\":\"P\"}]}" tprof
[[ "$(st)" == 200 ]] || { echo "SETUP FAIL: $BODY"; exit 1; }
C="$FIX/cv"; U="$C/users"
# ana: inscrita individual (overlay sem senha) + history; bia/caio: só dir; gil+hugo: time azul (gil tem
# history de antes); fabio: só SESSÃO viva; eve: só no access.log; dave: nunca tocou o contest
mkdir -p "$U/ana" "$U/bia" "$U/caio" "$U/gil" "$U/time-azul"
jq -cn '{login:"ana",fullname:"Nome Ana",status:"active",registered_at:1,team:{cohort:"individual"}}' > "$U/ana/account.json"
for u in ana bia gil; do printf '60:A:C:Accepted:%s:s-%s\n' "$NOW" "$u" > "$U/$u/history"; done; : > "$U/caio/history"
jq -cn '{login:"time-azul",password:"!abc-uuid",fullname:"Azul",status:"active",is_team:true,team:{cohort:"times",members:["gil","hugo"],captain:"gil"}}' > "$U/time-azul/account.json"
printf '70:A:C:Wrong Answer:%s:s-azul\n' "$NOW" > "$U/time-azul/history"
jq -cn '{entries:{ana:{kind:"individual"},gil:{kind:"team",team:"time-azul"},hugo:{kind:"team",team:"time-azul"}},
         teams:{"time-azul":{name:"Azul",members:["gil","hugo"],captain:"gil",invited:[]}}}' > "$C/registrations.json"
printf 'CONTEST=cv\nLOGIN=fabio\nUSERFULLNAME=Fabio\nLOGINAT=1\n' > "$SESS/sfabio"
printf 'CONTEST=cv\nLOGIN=prof.admin\nUSERFULLNAME=Prof\nLOGINAT=1\n' > "$SESS/adm"
mkdir -p "$C/var"; printf '%s\teve\t10.0.0.1\tYQ==\n' "$NOW" >> "$C/var/access.log"
fx_user "$C" juiz.judge jj "Juiz local"
# ivo: DESABILITADO pelo admin no modo compartilhado (A3: overlay com `!…`); jose: DESCLASSIFICADO
mkdir -p "$U/ivo" "$U/jose"; for u in ivo jose; do printf '80:A:C:Accepted:%s:s-%s\n' "$NOW" "$u" > "$U/$u/history"; done
call /contest/admin/user-disable POST '{"login":"ivo"}' adm 'contest=cv';    [[ "$(st)" == 200 ]] || { echo "SETUP FAIL disable: $BODY"; exit 1; }
call /contest/admin/user-disqualify POST '{"login":"jose"}' adm 'contest=cv'; [[ "$(st)" == 200 ]] || { echo "SETUP FAIL disqualify: $BODY"; exit 1; }
IVO0="$(md5sum < "$U/ivo/account.json")"

echo "== prévia =="
ROWS0="$(rows cv)"; SUM0="$(tree_sum cv)"
call /contest/admin/users-convert POST '{}' adm 'contest=cv'
P="$BODY"
ck "prévia 200, fase before" '[[ "$(st)" == 200 && "$(J .preview.phase)" == before ]]'
ck "individuais: ana, bia, caio, eve, fabio, jose (o desabilitado ivo fica como está)" '[[ "$(J ".preview.samples.individuals|sort|join(\",\")")" == "ana,bia,caio,eve,fabio,jose" ]]'
ck "linhas novas no placar = 2 (eve e fabio não tinham dir) + aviso" '[[ "$(J .preview.counts.new_scoreboard_rows)" == 2 && "$(J ".preview.warnings|index(\"new_scoreboard_rows\")")" != null ]]'
ck "origens: sessão (fabio), access.log (eve), inscrição (ana)" '[[ "$(J .preview.counts.from.session)" == 1 && "$(J .preview.counts.from.access_log)" == 1 && "$(J .preview.counts.from.registration)" == 1 && "$(J .preview.counts.from.dir)" == 4 ]]'
ck "1 time; gil (com history) desabilitado; hugo perde o login" '[[ "$(J .preview.counts.teams)" == 1 && "$(J ".preview.samples.members_with_history[0].login")" == gil && "$(J ".preview.samples.members_losing_login[0].login")" == hugo ]]'
ck "o admin do treino ganha conta local; dave (nunca tocou) fora" '[[ "$(J .preview.admin)" == prof.admin ]] && ! grep -q dave <<<"$P"'
ck "avisos: membros perdem o login, inscrição fecha, superadmins perdem acesso" '[[ "$(J ".preview.warnings|index(\"team_members_lose_login\")")" != null && "$(J ".preview.warnings|index(\"registration_closes\")")" != null && "$(J ".preview.warnings|index(\"superadmins_lose_access\")")" != null ]]'
ck "a prévia NÃO grava nada" '[[ "$(tree_sum cv)" == "$SUM0" ]]'
PID="$(J .preview.plan_id)"

echo "== execução =="
call /contest/admin/users-convert POST '{"dry_run":false,"plan_id":"errado","confirm":true}' adm 'contest=cv'
ck "plan_id errado → 409 plan_changed, com a prévia nova" '[[ "$(st)" == 409 && "$(J .error.code)" == plan_changed && "$(J .error.preview.plan_id)" == "$PID" ]]'
call /contest/admin/users-convert POST "{\"dry_run\":false,\"plan_id\":\"$PID\"}" adm 'contest=cv'
ck "sem confirmação → 409 confirm_required" '[[ "$(st)" == 409 && "$(J .error.code)" == confirm_required ]]'
call /contest/admin/users-convert POST "{\"dry_run\":false,\"plan_id\":\"$PID\",\"confirm\":true}" adm 'contest=cv'
R="$BODY"
ck "antes da prova, confirm:true converte (200)" '[[ "$(st)" == 200 && "$(J .converted)" == true ]]'
pw(){ jq -r --arg l "$1" '.credentials[]|select(.login==$l)|.password // empty' <<<"$R"; }
ck "credenciais: 5 individuais + time + admin com senha; gil desabilitado sem senha" '[[ -n "$(pw bia)" && -n "$(pw fabio)" && -n "$(pw time-azul)" && -n "$(pw prof.admin)" && -z "$(pw gil)" && "$(jq -r ".credentials[]|select(.login==\"gil\")|.kind" <<<"$R")" == member_disabled ]]'
ROWS1="$(rows cv)"
ck "placar: toda linha de antes continua (sc_users) — e só entram eve/fabio (contas novas, zeradas)" '[[ -z "$(comm -23 <(tr " " "\n" <<<"$ROWS0" | sed "/^$/d") <(tr " " "\n" <<<"$ROWS1" | sed "/^$/d"))" && "$(comm -13 <(tr " " "\n" <<<"$ROWS0" | sed "/^$/d") <(tr " " "\n" <<<"$ROWS1" | sed "/^$/d") | tr "\n" " ")" == "eve fabio " ]]'
ck "credenciais sem login repetido" '[[ "$(jq -r ".credentials|map(.login)|length" <<<"$R")" == "$(jq -r ".credentials|map(.login)|unique|length" <<<"$R")" ]]'
ck "history de bia intacto; email do treino NÃO copiado" 'grep -q ":s-bia$" "$U/bia/history" && [[ "$(jq -r .email "$U/bia/account.json")" == "" ]]'
ck "USERS_FROM e SHARED_ADMIN fora do conf; roster arquivado" '! grep -q "^USERS_FROM=\|^SHARED_ADMIN=" "$C/conf" && [[ ! -e "$C/registrations.json" ]] && ls "$C/var" | grep -q "^registrations.converted-"'

echo "== depois =="
login cv bia s-bia;                ck "senha do treino não entra mais" '[[ "$(st)" != 200 ]]'
login cv bia "$(pw bia)";          ck "a senha nova entra" '[[ "$(st)" == 200 ]]'
login cv time-azul "$(pw time-azul)"; ck "o TIME entra direto com a senha única" '[[ "$(st)" == 200 ]]'
login cv hugo s-hugo;              ck "membro do time não entra mais com a conta dele" '[[ "$(st)" != 200 ]]'
login cv gil s-gil;                ck "membro com history: conta desabilitada" '[[ "$(st)" != 200 ]] && [[ "$(jq -r ".password|startswith(\"!\")" "$U/gil/account.json")" == true ]]'
call /contest/userinfo GET '' sfabio 'contest=cv'; ck "quem só tinha SESSÃO continua logado (e ganhou conta)" '[[ "$(st)" == 200 && -f "$U/fabio/account.json" ]]'
login cv prof.admin "$(pw prof.admin)"; ck "admin local com a senha nova" '[[ "$(st)" == 200 ]]'
login cv chefe.admin ca;           ck "superadmin do treino não entra mais (a fonte saiu)" '[[ "$(st)" != 200 ]]'
login cv juiz.judge jj;            ck "conta local que já existia segue igual" '[[ "$(st)" == 200 ]]'
ck "o DESABILITADO no modo compartilhado segue desabilitado, intocado e fora das credenciais" '[[ "$(md5sum < "$U/ivo/account.json")" == "$IVO0" && -z "$(jq -r ".credentials[]|select(.login==\"ivo\")|.login" <<<"$R")" ]]'
login cv ivo s-ivo;                ck "…e não entra" '[[ "$(st)" != 200 ]]'
ck "o DESCLASSIFICADO ganha conta mas segue desclassificado (fora do placar)" '[[ "$(jq -r .disqualified "$U/jose/account.json")" == true && -n "$(pw jose)" ]] && ! grep -qw jose <<<"$ROWS1"'
call /contest/badges GET '' adm 'contest=cv'
ck "etiquetas saem com a senha nova (conta própria)" '[[ "$(J "[..|objects|select(.login?==\"bia\")|.password][0]")" == "$(pw bia)" ]]'
call /contest/admin/users-convert POST '{}' adm 'contest=cv'
ck "2ª chamada → 409 already_converted, com o resumo (sem senha)" '[[ "$(st)" == 409 && "$(J .error.code)" == already_converted ]] && ! grep -q "$(pw bia)" <<<"$BODY"'

echo "== prova em andamento: só o id digitado =="
call /treino/contest-create/create POST "{\"id\":\"cv2\",\"name\":\"Prova 2\",\"mode\":\"icpc\",\"end\":$FUT,\"users_from\":\"treino\",\"admin\":{\"login\":\"prof\"},\"problems\":[{\"bank_id\":\"bankprob\",\"name\":\"P\"}]}" tprof
mkdir -p "$FIX/cv2/users/bia"; printf 'CONTEST=cv2\nLOGIN=prof.admin\nUSERFULLNAME=Prof\nLOGINAT=1\n' > "$SESS/adm2"
printf 'CONTEST=cv2\nLOGIN=bia\nUSERFULLNAME=Bia\nLOGINAT=1\n' > "$SESS/sbia2"
call /contest/userinfo GET '' sbia2 'contest=cv2'; ck "(bia logada no cv2 antes)" '[[ "$(st)" == 200 ]]'
call /contest/admin/users-convert POST '{}' adm2 'contest=cv2'; P2="$(J .preview.plan_id)"
ck "fase running + aviso live" '[[ "$(J .preview.phase)" == running && "$(J ".preview.warnings|index(\"live\")")" != null ]]'
call /contest/admin/users-convert POST "{\"dry_run\":false,\"plan_id\":\"$P2\",\"confirm\":true}" adm2 'contest=cv2'
ck "confirm:true NÃO basta com a prova rodando (need = o id)" '[[ "$(st)" == 409 && "$(J .error.need)" == cv2 ]]'
call /contest/admin/users-convert POST "{\"dry_run\":false,\"plan_id\":\"$P2\",\"confirm\":\"cv2\",\"logout_all\":true}" adm2 'contest=cv2'
ck "id digitado converte; logout_all derruba a sessão (sessions_removed ≥ 1)" '[[ "$(st)" == 200 && -f "$FIX/cv2/users/bia/account.json" && "$(J .sessions_removed)" -ge 1 ]]'
call /contest/userinfo GET '' sbia2 'contest=cv2'; ck "…e a sessão derrubada dá 401" '[[ "$(st)" == 401 ]]'
call /contest/userinfo GET '' adm2 'contest=cv2'; ck "…a do admin (papel) fica" '[[ "$(st)" == 200 ]]'
call /contest/admin/users-convert POST '{}' reg 'contest=cv2'; ck "sem sessão de admin → 401/403" '[[ "$(st)" == 401 || "$(st)" == 403 ]]'

echo "== retomada (a conversão caiu no meio) =="
call /treino/contest-create/create POST "{\"id\":\"cv3\",\"name\":\"Prova 3\",\"mode\":\"icpc\",\"start\":$(( NOW + 3600 )),\"end\":$FUT,\"users_from\":\"treino\",\"admin\":{\"login\":\"prof\"},\"problems\":[{\"bank_id\":\"bankprob\",\"name\":\"P\"}]}" tprof
U3="$FIX/cv3/users"; mkdir -p "$U3/bia" "$U3/caio"
jq -cn '{login:"bia",password:"velha1234",fullname:"Nome Bia",status:"active",converted_from:"treino",converted_at:1,converted_kind:"individual"}' > "$U3/bia/account.json"
jq -cn '{fullname:"Nome Caio",status:"active",shared_overlay:true}' > "$U3/caio/account.json"   # sem .login (implícito no dir)
touch "$FIX/cv3/var/users-convert.pending"
printf 'CONTEST=cv3\nLOGIN=prof.admin\nUSERFULLNAME=Prof\nLOGINAT=1\n' > "$SESS/adm3"
call /contest/admin/users-convert POST '{}' adm3 'contest=cv3'; P3="$(J .preview.plan_id)"
ck "prévia conta 1 retomada; caio (account.json sem .login) é individual" '[[ "$(J .preview.counts.resumed)" == 1 && "$(J ".preview.samples.individuals|join(\",\")")" == caio ]]'
call /contest/admin/users-convert POST "{\"dry_run\":false,\"plan_id\":\"$P3\",\"confirm\":true}" adm3 'contest=cv3'
ck "retomada: bia sai como resumed, SEM senha, e a senha dela não muda" '[[ "$(st)" == 200 && "$(J ".credentials[]|select(.login==\"bia\")|.resumed")" == true && -z "$(J ".credentials[]|select(.login==\"bia\")|.password // empty")" && "$(jq -r .password "$U3/bia/account.json")" == velha1234 ]]'
C3="$(J ".credentials[]|select(.login==\"caio\")|.password")"
ck "caio (sem .login) ganhou a senha que a resposta mostra, e o .login gravado" '[[ -n "$C3" && "$(jq -r .password "$U3/caio/account.json")" == "$C3" && "$(jq -r .login "$U3/caio/account.json")" == caio && ! -e "$FIX/cv3/var/users-convert.pending" ]]'

echo "== 2000 contas =="
B="$FIX/cvbig"; mkdir -p "$B/users" "$B/var"
printf 'CONTEST_ID=cvbig\nCONTEST_NAME=Big\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nUSERS_FROM=treino\nPROBS=()\n' "$(( NOW + 3600 ))" "$FUT" > "$B/conf"
printf 'prof.admin\n' > "$B/owner"
for i in $(seq -w 1 2000); do
  mkdir -p "$T/users/big$i" "$B/users/big$i"
  printf '{"login":"big%s","password":"s%s","fullname":"Big %s","status":"active"}\n' "$i" "$i" "$i" > "$T/users/big$i/account.json"
  printf '1:A:C:Accepted:%s:x%s\n' "$NOW" "$i" > "$B/users/big$i/history"
done
printf 'CONTEST=cvbig\nLOGIN=prof.admin\nUSERFULLNAME=Prof\nLOGINAT=1\n' > "$SESS/admbig"
t0=$EPOCHREALTIME
call /contest/admin/users-convert POST '{}' admbig 'contest=cvbig'; PB="$(J .preview.plan_id)"
call /contest/admin/users-convert POST "{\"dry_run\":false,\"plan_id\":\"$PB\",\"confirm\":true}" admbig 'contest=cvbig'
dt="$(awk -v a="$t0" -v b="$EPOCHREALTIME" 'BEGIN{printf "%.1f", b-a}')"
ck "2000 contas: prévia + conversão em < 15 s (${dt}s), 2000 credenciais, JSON válido" '[[ "$(st)" == 200 && "$(J ".credentials|length")" -ge 2000 ]] && awk -v d="$dt" "BEGIN{exit !(d < 15)}"'
ck "…todas com conta e history intacto" '[[ "$(find "$B/users" -name account.json | wc -l)" -ge 2000 ]] && grep -q ":x1000$" "$B/users/big1000/history"'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
