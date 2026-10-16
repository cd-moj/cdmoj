#!/bin/bash
# smoke-team-host.sh — TIME SÓ PELO ENDEREÇO DO PRÓPRIO CONTEST (lib/team-host.sh + router.sh + auth/login.sh), 16/10/2026.
# Numa máquina travada o time chegava pelo IP cru ou pelo site principal (?c=OUTRO) e logava em outro contest. Prende:
#   · login de TIME fora do subdomínio do contest (CONTEST_HOST vazio ou de outro) → 403 host_required com a URL certa,
#     sem sessão criada, com audit (team-host-block via=login);
#   · sessão de time fora do subdomínio → 403 host_required em TODA rota (contest, auth/status, índice); logout passa;
#     o `Bearer:` legado não desvia;
#   · papel, treino e id que não vira subdomínio (a.b) ficam de fora; contest compartilhado (USERS_FROM) entra na regra;
#   · contest apagado: o 401 é do handler e nada é recriado; teto do audit; chave 0/observe e o override em run/;
#   · com a trava de sede: site_locked mantém a prioridade.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export TEAM_HOST_LOCK=1 MOJ_PUBLIC_BASE=https://moj.naquadah.com.br
NOW=$EPOCHSECONDS
mkc(){ mkdir -p "$FIX/$1/var"; printf 'CONTEST_ID=%s\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nUSER_STORE=v2\n%s' \
  "$1" "$((NOW-3600))" "$((NOW+3600))" "${2:-}" > "$FIX/$1/conf"; }
mkc pv; mkc ou; mkc a.b; mkc sh $'USERS_FROM=treino\n'
mkdir -p "$FIX/treino/var"; printf 'CONTEST_ID=treino\nCONTEST_TYPE=treino\nUSER_STORE=v2\n' > "$FIX/treino/conf"
fx_user "$FIX/pv" t1 a "Time 1" >/dev/null; fx_user "$FIX/pv" pv.admin p "Admin" >/dev/null; fx_user "$FIX/pv" pv.judge j "Juiz" >/dev/null
fx_user "$FIX/ou" t1 a "Time 1 (ou)" >/dev/null; fx_user "$FIX/a.b" t9 a "Time 9" >/dev/null
fx_user "$FIX/treino" alice a "Alice" >/dev/null
ses(){ printf 'CONTEST=%s\nLOGIN=%s\nUSERFULLNAME=%s\nLOGINAT=1\n' "$2" "$3" "$3" > "$SESS/$1"; }
ses tk-t1 pv t1; ses tk-adm pv pv.admin; ses tk-ali treino alice; ses tk-t9 a.b t9; ses tk-gone gone t1
call(){ # <rota> <método> [corpo] [token] [query] — CH = CONTEST_HOST (o subdomínio por onde chegou), IP em RIP
  OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="${4:+Bearer $4}" \
         CONTEST_HOST="${CH:-}" REMOTE_ADDR="${RIP:-9.9.9.9}" HTTP_HOST="${HH:-}" HTTP_BEARER="${HB:-}" \
         CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  CODE="$(sed -n 's/^Status: \([0-9]*\).*/\1/p' <<<"$OUT" | head -1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${CODE:-} ${BODY:0:220}"; ((fail++)); fi; }
J(){ printf '%s' "$BODY" | jq -r "$1" 2>/dev/null; }
nsess(){ find "$SESS" -maxdepth 1 -type f | wc -l; }
LOGIN_T1='{"username":"t1","password":"a"}'

echo "== login de time =="
n0="$(nsess)"; HH=177.70.23.195 call /auth/login POST "$LOGIN_T1" '' 'contest=pv'
ck "pelo IP/site principal: 403 host_required" '[[ "$CODE" == 403 && "$(J .error.code)" == host_required ]]'
ck "…com a URL do subdomínio e o contest" '[[ "$(J .error.url)" == "https://pv.moj.naquadah.com.br/contest/" && "$(J .error.contest)" == pv ]]'
ck "…a URL também na mensagem (CLI antiga)" '[[ "$(J .error.message)" == *"https://pv.moj.naquadah.com.br/contest/"* ]]'
ck "…nenhuma sessão criada" '[[ "$(nsess)" == "$n0" ]]'
ck "…audit team-host-block via=login com host e ip" 'grep -q "	t1	team-host-block	via=login host=177.70.23.195 ip=9.9.9.9 route=/auth/login login=t1" "$FIX/pv/var/admin-audit.log"'
HH=177.70.23.195 call /auth/login POST '{"username":"t1","password":"errada"}' '' 'contest=pv'
ck "senha errada segue 401 (a regra vem depois da senha)" '[[ "$CODE" == 401 ]]'
CH=pv call /auth/login POST "$LOGIN_T1" '' 'contest=pv'
ck "pelo subdomínio do contest: entra" '[[ "$(J .logged_in)" == true ]]'
CH=ou call /auth/login POST "$LOGIN_T1" '' 'contest=pv'
ck "pelo subdomínio de OUTRO contest: contest_mismatch (de sempre)" '[[ "$CODE" == 403 && "$(J .error.code)" == contest_mismatch ]]'
call /auth/login POST '{"username":"pv.admin","password":"p"}' '' 'contest=pv'
ck "conta de papel pelo site principal: entra" '[[ "$(J .logged_in)" == true ]]'
call /auth/login POST '{"username":"alice","password":"a"}' '' 'contest=treino'
ck "treino pelo site principal: entra" '[[ "$(J .logged_in)" == true ]]'
call /auth/login POST '{"username":"t9","password":"a"}' '' 'contest=a.b'
ck "id que não vira subdomínio (a.b): isento" '[[ "$(J .logged_in)" == true ]]'
call /auth/login POST '{"username":"alice","password":"a"}' '' 'contest=sh'
ck "contest compartilhado (USERS_FROM): a regra vale" '[[ "$CODE" == 403 && "$(J .error.code)" == host_required && "$(J .error.url)" == "https://sh.moj.naquadah.com.br/contest/" ]]'

echo "== sessão de time fora do subdomínio =="
call /contest/basic GET '' tk-t1 'contest=pv'
ck "/contest/basic pelo site principal: 403 host_required" '[[ "$CODE" == 403 && "$(J .error.code)" == host_required ]]'
call /auth/status GET '' tk-t1 'contest=pv'
ck "/auth/status: 403 host_required (a tela mostra o endereço)" '[[ "$CODE" == 403 && "$(J .error.code)" == host_required ]]'
call /index/contests GET '' tk-t1 ''
ck "rota sem contest (índice) com o token do time: 403" '[[ "$CODE" == 403 && "$(J .error.code)" == host_required ]]'
CH=pv call /contest/basic GET '' tk-t1 'contest=pv'
ck "pelo subdomínio do contest: passa" '[[ "$(J .error.code)" != host_required && "$CODE" != 403 ]]'
CH=ou call /contest/basic GET '' tk-t1 'contest=ou'
ck "token de pv pelo subdomínio de ou: host_required (aponta p/ pv)" '[[ "$(J .error.code)" == host_required && "$(J .error.url)" == "https://pv.moj.naquadah.com.br/contest/" ]]'
HB=tk-t1 call /contest/basic GET '' '' 'contest=pv'
ck "cabeçalho Bearer: legado não desvia" '[[ "$CODE" == 403 && "$(J .error.code)" == host_required ]]'
call /contest/basic GET '' tk-adm 'contest=pv'
ck "sessão de papel pelo site principal: passa" '[[ "$(J .error.code)" != host_required ]]'
call /treino/problems GET '' tk-ali 'q=x'
ck "sessão do treino pelo site principal: passa" '[[ "$(J .error.code)" != host_required ]]'
call /contest/basic GET '' tk-t9 'contest=a.b'
ck "sessão de id isento (a.b): passa" '[[ "$(J .error.code)" != host_required ]]'
call /contest/basic GET '' tk-gone 'contest=gone'
ck "contest apagado: não é host_required, e nada é recriado" '[[ "$(J .error.code)" != host_required && ! -e "$FIX/gone" ]]'
n1="$(grep -c "	team-host-block	via=session" "$FIX/pv/var/admin-audit.log")"
call /contest/basic GET '' tk-t1 'contest=pv'; call /contest/problems GET '' tk-t1 'contest=pv'
ck "teto do audit: 1 linha por login+via a cada 5 min" '[[ "$(grep -c "	team-host-block	via=session" "$FIX/pv/var/admin-audit.log")" == "$n1" && "$n1" == 1 ]]'
call /auth/logout POST '' tk-t1 'contest=pv'
ck "logout pelo site principal passa e apaga a sessão" '[[ "$CODE" != 403 && ! -f "$SESS/tk-t1" ]]'

echo "== chave e override =="
ses tk-t1 pv t1
TEAM_HOST_LOCK=0 call /contest/basic GET '' tk-t1 'contest=pv'
ck "TEAM_HOST_LOCK=0: desligada" '[[ "$(J .error.code)" != host_required ]]'
printf '0\n' > "$RUN/team-host-lock"; call /contest/basic GET '' tk-t1 'contest=pv'
ck "override run/team-host-lock=0: desligada sem restart" '[[ "$(J .error.code)" != host_required ]]'
printf 'observe\n' > "$RUN/team-host-lock"; rm -rf "$RUN/team-host"; call /contest/basic GET '' tk-t1 'contest=pv'
ck "override observe: passa e registra team-host-observe" '[[ "$(J .error.code)" != host_required ]] && grep -q "	team-host-observe	via=session" "$FIX/pv/var/admin-audit.log"'
printf '1\n' > "$RUN/team-host-lock"; rm -rf "$RUN/team-host"; call /contest/basic GET '' tk-t1 'contest=pv'
ck "override 1 não ENDURECE além do env (env 1 → vale)" '[[ "$(J .error.code)" == host_required ]]'
TEAM_HOST_LOCK=0 call /contest/basic GET '' tk-t1 'contest=pv'
ck "env 0 vence o arquivo (o override só afrouxa)" '[[ "$(J .error.code)" != host_required ]]'
rm -f "$RUN/team-host-lock"

echo "== com a trava de sede (site_locked tem a prioridade) =="
printf 'CONTEST_MODULES=maquinas\nSITE_LOCK=1\n' >> "$FIX/pv/conf"; fx_user "$FIX/ou" ou.admin p "Admin ou" >/dev/null
RIP=5.5.5.5 CH=pv call /auth/login POST "$LOGIN_T1" '' 'contest=pv'
ck "login pelo subdomínio reivindica o IP" '[[ "$(J .logged_in)" == true && -f "$RUN/site-lock/5.5.5.5" ]]'
RIP=5.5.5.5 call /contest/basic GET '' tk-t1 'contest=ou'
ck "do IP preso, a outro contest: site_locked (antes do host_required)" '[[ "$CODE" == 403 && "$(J .error.code)" == site_locked ]]'
RIP=5.5.5.5 call /contest/basic GET '' tk-t1 'contest=pv'
ck "do IP preso, o próprio contest pelo site principal: host_required" '[[ "$CODE" == 403 && "$(J .error.code)" == host_required ]]'

echo "== contest_public_url =="
( source "$ROOT/api/v1/lib/team-host.sh"
  MOJ_PUBLIC_BASE=https://moj.charge.naquadah.com.br:8443; contest_public_url pv; echo
  MOJ_PUBLIC_BASE=https://moj.naquadah.com.br/; contest_public_url ab_c-1; echo
  contest_public_url a.b; echo ) > "$RUN/urls"
ck "com porta" '[[ "$(sed -n 1p "$RUN/urls")" == "https://pv.moj.charge.naquadah.com.br:8443/contest/" ]]'
ck "barra final e _ no id" '[[ "$(sed -n 2p "$RUN/urls")" == "https://ab_c-1.moj.naquadah.com.br/contest/" ]]'
ck "id sem subdomínio: o endereço clássico" '[[ "$(sed -n 3p "$RUN/urls")" == "https://moj.naquadah.com.br/contest/?c=a.b" ]]'

echo; echo "RESULT: $pass passed, $fail failed"; [[ $fail -eq 0 ]]
