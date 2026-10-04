#!/bin/bash
# Pessoas › Contas / Inscrições — o que a auditoria do painel (03/10/2026) pegou dando falsa impressão:
#   - desabilitar um TIME de inscrição não barrava ninguém (o membro entra pelo alias com a senha DELE) e todo time
#     aparecia "(desabilitado)" na lista por causa da senha `!<uuid>`;
#   - a desclassificação sumia na re-materialização (account.json reescrito do zero);
#   - remover um time em contest compartilhado dava 500 depois do mv e o membro voltava como ELE MESMO;
#   - Desligar → Ligar a inscrição gravava um roster VAZIO (o .off nunca voltava);
#   - "Criar time" engolia membro inexistente/recusado e respondia "Time criado.";
#   - remover um inscrito do roster e resetar a senha não derrubavam a sessão aberta;
#   - o atraso (min) da janela crescia a cada Salvar (a tela o recalculava de late_until − closes_at).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; SPOOL="$(mktemp -d)"; RUN="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$SPOOL" "$RUN"' EXIT
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" SPOOLDIR="$SPOOL" SCOREDIR="$ROOT/score" RUNDIR="$RUN"
NOW="$(date +%s)"
T="$FIX/treino"; mkdir -p "$T/var/jsons"
printf 'CONTEST_ID=treino\nCONTEST_NAME="Treino"\nCONTEST_TYPE=lista-publica\n' > "$T/conf"
for u in ana caio zeze bob; do fx_user "$T" "$u" s3nha "Fulano $u"; done
C="$FIX/esq"; mkdir -p "$C/var" "$C/users" "$C/enunciados"
{ printf 'CONTEST_ID=esq\nCONTEST_NAME="Esquenta"\nCONTEST_TYPE=icpc\nUSERS_FROM=treino\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW-600))" "$((NOW+10800))"
  printf 'PROBS=( cdmoj org#alfa Alfa A org#alfa )\n'; } > "$C/conf"
fx_user "$C" esq.admin adm "Admin"; fx_user "$C" own1 velha "Conta Própria"
printf '{"id":"org#alfa","title":"Alfa"}' > "$T/var/jsons/org#alfa.json"
printf 'CONTEST=esq\nLOGIN=esq.admin\nUSERFULLNAME=A\nLOGINAT=1\n' > "$SESS/tok-adm"
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-tok-adm}" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
adm(){ call /contest/admin/registrations POST "$1" tok-adm 'contest=esq'; }
login(){ call /auth/login POST "{\"username\":\"$1\",\"password\":\"${2:-s3nha}\"}" '' 'contest=esq'; }
alive(){ call /auth/status GET "" "$1" "contest=esq"; [[ "$(J .logged_in)" == true ]]; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }
J(){ jq -r "$1" <<<"$BODY" 2>/dev/null; }
TEAM=time-os-tres

echo "== Criar time: membro inexistente/além do máximo não é engolido =="
adm '{"action":"enable"}'
adm '{"action":"team-add","name":"Os Tres","members":["ana","naoexiste"]}'
ck "membro inexistente: 422 user_notfound, nada criado" '[[ "$(J .error.code)" == user_notfound && ! -d "$C/users/$TEAM" ]]'
adm '{"action":"team-add","name":"Os Tres","members":["ana","caio","bob","zeze"]}'
ck "mais membros que o máximo: 422 team_too_big" '[[ "$(J .error.code)" == team_too_big ]]'
adm '{"action":"team-add","name":"Os Tres","members":["ana","caio"]}'
ck "time criado com os dois" '[[ "$(J ".teams[0].members | length")" == 2 ]]'
TEAM="$(J '.teams[0].login')"
adm '{"action":"add","login":"zeze"}'

echo "== desabilitar o TIME barra o membro; a lista não marca todo time como desabilitado =="
call /contest/admin/users GET '' tok-adm 'contest=esq'
ck "time recém-criado NÃO aparece desabilitado (senha !uuid é do time)" '[[ "$(J ".users[] | select(.login==\"$TEAM\") | .disabled")" == false ]]'
login caio; TOKC="$(J .token)"
ck "membro entra como o time" '[[ "$(J .username)" == "$TEAM" ]]'
call /contest/admin/user-disable POST "{\"login\":\"$TEAM\"}" tok-adm 'contest=esq'
ck "desabilitar: sessão do time cai" '! alive "$TOKC"'
login caio
ck "…e o membro NÃO entra mais (401)" '[[ "$OUT" == *"Status: 401"* ]]'
call /contest/admin/users GET '' tok-adm 'contest=esq'
ck "lista: time desabilitado" '[[ "$(J ".users[] | select(.login==\"$TEAM\") | .disabled")" == true ]]'
call /contest/admin/user-disable POST "{\"login\":\"$TEAM\",\"undo\":true}" tok-adm 'contest=esq'
login caio
ck "reabilitar o time: membro volta a entrar" '[[ "$(J .username)" == "$TEAM" ]]'

echo "== gate de navegador: o MEMBRO é cobrado pelo esperado do TIME (antes saía vazio e entrava de qualquer máquina) =="
printf '{"mode":"enforce","by_regex":[{"regex":"^time-","expect":"SEDE-X"}]}' > "$C/ua-gate.json"
OUT="$(PATH_INFO=/auth/login REQUEST_METHOD=POST QUERY_STRING=contest=esq HTTP_USER_AGENT="Mozilla/5.0 Chrome" bash "$ROUTER" <<<'{"username":"caio","password":"s3nha"}' 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"
ck "membro de máquina errada: 403 ua_gate" '[[ "$OUT" == *"Status: 403"* && "$(J .error.code)" == ua_gate ]]'
OUT="$(PATH_INFO=/auth/login REQUEST_METHOD=POST QUERY_STRING=contest=esq HTTP_USER_AGENT="Mozilla/5.0 SEDE-X img" bash "$ROUTER" <<<'{"username":"caio","password":"s3nha"}' 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"
ck "membro da máquina da sede: entra como o time" '[[ "$(J .username)" == "$TEAM" ]]'
rm -f "$C/ua-gate.json"

echo "== desclassificação sobrevive à re-materialização =="
call /contest/admin/user-disqualify POST "{\"login\":\"$TEAM\"}" tok-adm 'contest=esq'
adm '{"action":"materialize"}'
ck "time segue desclassificado depois do Re-materializar" '[[ "$(jq -r .disqualified "$C/users/$TEAM/account.json")" == true ]]'
call /contest/admin/user-disqualify POST "{\"login\":\"$TEAM\",\"undo\":true}" tok-adm 'contest=esq'

echo "== Desligar → Ligar devolve o roster =="
adm '{"action":"disable"}'; adm '{"action":"disable"}'
adm '{"action":"enable"}'
ck "roster de volta (1 time + 1 individual)" '[[ "$(J .totals.teams)" == 1 && "$(J .totals.individuals)" == 1 ]]'

echo "== remover do roster / resetar a senha derrubam a sessão =="
login zeze; TOKZ="$(J .token)"
adm '{"action":"rm","login":"zeze"}'
ck "removido do roster: token morto" '! alive "$TOKZ"'
call /auth/login POST '{"username":"own1","password":"velha"}' '' 'contest=esq'; TOKO="$(J .token)"
call /contest/admin/user-add POST '{"login":"own1","password":"nova123"}' tok-adm 'contest=esq'
ck "reset de senha: token antigo morto" '! alive "$TOKO"'

echo "== atraso da janela não cresce a cada Salvar =="
adm "{\"action\":\"window\",\"close\":$((NOW+3600)),\"late_minutes\":30}"
ck "GET devolve o atraso GRAVADO (30) e o fecha gravado" '[[ "$(J .window.late_minutes)" == 30 && "$(J .window.close_set)" == $((NOW+3600)) ]]'
adm "{\"action\":\"window\",\"late_minutes\":$(J .window.late_minutes)}"
ck "salvar de novo com o valor da tela: segue 30" '[[ "$(J .window.late_minutes)" == 30 ]]'
adm '{"action":"window","close":null}'
ck "fecha herdado: close_set null (a tela deixa o campo vazio)" '[[ "$(J .window.close_set)" == null ]]'

echo "== remover o TIME: lápide, nunca 500 nem membro voltando como ele mesmo =="
call /contest/admin/user-remove POST "{\"login\":\"$TEAM\"}" tok-adm 'contest=esq'
ck "remover o time: 200 (era 500 write_fail)" '[[ "$(J .removed)" == true ]]'
ck "lápide: desabilitado + desclassificado, dir no lugar" '[[ "$(jq -r "[.disabled, .disqualified] | join(\",\")" "$C/users/$TEAM/account.json")" == "true,true" ]]'
login caio
ck "membro não entra (nem como ele mesmo)" '[[ "$OUT" == *"Status: 401"* && ! -d "$C/users/caio" ]]'

echo "== Sessões: contador sem token repetido; pílula respeita a abertura; conta apagada não lista =="
login zeze >/dev/null; adm '{"action":"add","login":"zeze"}'; login zeze; TZ1="$(J .token)"
mkdir -p "$(dirname "$SESS/.idx/esq/zeze")"
call /contest/admin/sessions GET '' tok-adm 'contest=esq'   # semeia o índice
[[ -f "$SESS/.idx/esq/zeze" ]] && printf '%s\n' "$TZ1" >> "$SESS/.idx/esq/zeze"   # token repetido (semeadura só apêndice)
call /contest/admin/logout-all GET '' tok-adm 'contest=esq'
NC="$(J .sessions.competitors)"
ck "token repetido no índice não conta 2×" '[[ "$NC" == "$(grep -l "^CONTEST=esq" "$SESS"/* 2>/dev/null | xargs grep -L "LOGIN=esq.admin" | wc -l)" ]]'
printf 'LOGIN_START_TIME=%s\n' "$((NOW+7200))" >> "$C/conf"
call /contest/admin/logout-all GET '' tok-adm 'contest=esq'
ck "abertura do login no futuro: login_open_now false" '[[ "$(J .login_open_now)" == false && "$(J .login_enabled)" == true ]]'
sed -i '/^LOGIN_START_TIME=/d' "$C/conf"
fx_user "$C" sumido x Sumido; printf 'CONTEST=esq\nLOGIN=sumido\nUSERFULLNAME=S\nLOGINAT=1\n' > "$SESS/tok-sumido"; rm -rf "$C/users/sumido"
call /contest/admin/sessions GET '' tok-adm 'contest=esq'
ck "sessão de conta apagada não aparece como ativa" '[[ "$(J "[.sessions[] | select(.login==\"sumido\")] | length")" == 0 ]]'

echo; echo "RESULT: $pass passed, $fail failed"; (( fail == 0 ))
