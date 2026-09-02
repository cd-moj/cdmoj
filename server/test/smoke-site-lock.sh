#!/bin/bash
# TRAVA DE SEDE POR IP (lib/site-lock.sh + router): login de competidor num contest com
# SITE_LOCK prende o IP de origem até o fim da prova; daquele IP, treino/índice/outro contest
# levam 403 site_locked (sessão antiga inclusa); papel é isento; logout passa; solta/expira;
# claim-seen; e TUDO vai ao audit — reivindicação nova e bloqueio (com teto de 5 min).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
NOW=$EPOCHSECONDS
C="$FIX/sl"; mkdir -p "$C/var"
printf 'CONTEST_ID=sl\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nSITE_LOCK=1\nUSER_STORE=v2\n' "$((NOW-3600))" "$((NOW+3600))" > "$C/conf"
printf "PROBS=( x col#pa Alfa A col#pa )\n" >> "$C/conf"
T="$FIX/treino"; mkdir -p "$T/var"; printf 'CONTEST_ID=treino\nCONTEST_TYPE=treino\nUSER_STORE=v2\n' > "$T/conf"
O="$FIX/outro"; mkdir -p "$O/var"; printf 'CONTEST_ID=outro\nCONTEST_TYPE=icpc\nUSER_STORE=v2\n' > "$O/conf"
fx_user "$C" sl.admin p "Admin"; fx_user "$C" alice a "Alice"; fx_user "$C" bob b "Bob"
fx_user "$T" alice a "Alice"; fx_user "$T" tr.admin p "Admin T"; fx_user "$O" alice a "Alice O"
# sessão do treino aberta ANTES da prova (não expira) e sessão de admin do treino
printf 'CONTEST=treino\nLOGIN=alice\nUSERFULLNAME=Alice\nLOGINAT=1\nIP=5.5.5.5\n' > "$SESS/tralice"
printf 'CONTEST=treino\nLOGIN=tr.admin\nLOGINAT=1\n' > "$SESS/tradm"
printf 'CONTEST=sl\nLOGIN=sl.admin\nLOGINAT=1\n' > "$SESS/adm"
printf 'CONTEST=sl\nLOGIN=alice\nUSERFULLNAME=Alice\nLOGINAT=1\n' > "$SESS/slalice"
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-adm}" REMOTE_ADDR="${6:-9.9.9.9}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:220}"; ((fail++)); fi; }
J(){ printf '%s' "$BODY" | jq -r "$1" 2>/dev/null; }
AUD="$C/var/admin-audit.log"

echo "== antes da reivindicação: tudo livre =="
call /treino/problems GET '' tralice 'q=x' 5.5.5.5
ck "treino de 5.5.5.5 responde (sem trava ainda)" '[[ "$OUT" != *"site_locked"* ]]'

echo "== login de competidor reivindica o IP =="
call /auth/login POST '{"username":"alice","password":"a"}' none 'contest=sl' 5.5.5.5
ck "alice loga em sl"                    '[[ "$(J .logged_in)" == true ]]'
ck "run/site-lock/5.5.5.5 com linha do contest sl" '[[ -f "$RUN/site-lock/5.5.5.5" ]] && awk -F"\t" "\$2==\"sl\"" "$RUN/site-lock/5.5.5.5" | grep -q .'
ck "AUDIT: site-lock-claim ip=5.5.5.5 login=alice" 'grep -q "	site-lock-claim	ip=5.5.5.5 login=alice until=" "$AUD"'
ck "until = fim da prova + 3600"         '[[ "$(awk -F"\t" "\$2==\"sl\"{print \$3}" "$RUN/site-lock/5.5.5.5")" == "$((NOW+3600+3600))" ]]'
call /auth/login POST '{"username":"bob","password":"b"}' none 'contest=sl' 5.5.5.5
ck "2º login do mesmo IP renova (1 linha, logins=2) e NÃO audita de novo" '[[ "$(awk -F"\t" "\$2==\"sl\"{print \$6}" "$RUN/site-lock/5.5.5.5")" == 2 && "$(grep -c "	site-lock-claim	" "$AUD")" == 1 ]]'
call /auth/login POST '{"username":"sl.admin","password":"p"}' none 'contest=sl' 7.7.7.7
ck "login de PAPEL não reivindica"       '[[ "$(J .logged_in)" == true && ! -f "$RUN/site-lock/7.7.7.7" ]]'

echo "== do IP preso: só o contest dono passa =="
call /treino/problems GET '' tralice 'q=x' 5.5.5.5
ck "treino (sessão antiga) → 403 site_locked" '[[ "$OUT" == *"Status: 403"* && "$(J .error.code)" == site_locked ]]'
ck "AUDIT: site-lock-block com ip/target/rota/login" 'grep -q "	site-lock-block	ip=5.5.5.5 target=- route=/treino/problems login=alice" "$AUD"'
call /auth/login POST '{"username":"alice","password":"a"}' none 'contest=treino' 5.5.5.5
ck "login no treino → 403 site_locked"   '[[ "$(J .error.code)" == site_locked ]]'
call /auth/login POST '{"username":"alice","password":"a"}' none 'contest=outro' 5.5.5.5
ck "login em OUTRO contest → 403"        '[[ "$(J .error.code)" == site_locked ]]'
call /index/status GET '' tralice '' 5.5.5.5
ck "índice → 403"                        '[[ "$(J .error.code)" == site_locked ]]'
call /contest/basic GET '' adm 'contest=sl' 5.5.5.5
ck "rota do contest dono passa"          '[[ "$OUT" != *"site_locked"* ]]'
call /auth/login POST '{"username":"alice","password":"a"}' none 'contest=sl' 5.5.5.5
ck "login no contest dono passa"         '[[ "$(J .logged_in)" == true ]]'
call /auth/logout POST '{}' tralice '' 5.5.5.5
ck "logout passa mesmo preso"            '[[ "$OUT" != *"site_locked"* ]]'
call /treino/problems GET '' tradm 'q=x' 5.5.5.5
ck "conta de PAPEL do treino é isenta"   '[[ "$OUT" != *"site_locked"* ]]'
call /treino/problems GET '' tralice 'q=x' 6.6.6.6
ck "outro IP segue livre"                '[[ "$OUT" != *"site_locked"* ]]'
call /treino/problems GET '' none 'q=x' 5.5.5.5
call /treino/problems GET '' none 'q=x' 5.5.5.5
ck "contador blocked sobe a cada bloqueio; audit com TETO (5 min): 1 linha p/ ip+alvo" '[[ "$(awk -F"\t" "\$2==\"sl\"{print \$7}" "$RUN/site-lock/5.5.5.5")" -ge 3 && "$(grep -c "	site-lock-block	ip=5.5.5.5 target=- " "$AUD")" == 1 ]]'
ck "alvo diferente audita à parte"       '[[ "$(grep -c "	site-lock-block	ip=5.5.5.5 target=treino " "$AUD")" == 1 && "$(grep -c "	site-lock-block	ip=5.5.5.5 target=outro " "$AUD")" == 1 ]]'

echo "== painel: GET/POST /contest/admin/site-lock =="
call /contest/admin/site-lock GET '' adm 'contest=sl'
ck "GET lista o IP preso com contadores e os bloqueios" '[[ "$(J .enabled)" == true && "$(J ".claims[0].ip")" == 5.5.5.5 && "$(J ".claims[0].blocked")" -ge 3 && "$(J ".blocks|length")" -ge 3 && "$(J ".claims_audit|length")" == 1 ]]'
call /contest/admin/site-lock GET '' slalice 'contest=sl' 6.6.6.6
ck "competidor → 403"                    '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/admin/site-lock POST '{"action":"release","ip":"5.5.5.5"}' adm 'contest=sl'
ck "release solta o IP (auditado)"       '[[ "$(J .released)" == true && ! -f "$RUN/site-lock/5.5.5.5" ]] && grep -q "	site-lock-release	ip=5.5.5.5" "$AUD"'
call /treino/problems GET '' tradm 'q=x' 5.5.5.5
call /auth/login POST '{"username":"alice","password":"a"}' none 'contest=treino' 5.5.5.5
ck "solto: treino volta a entrar"        '[[ "$(J .logged_in)" == true ]]'
# access.log tem 5.5.5.5 (alice/bob) e 7.7.7.7 (papel): claim-seen prende só o de competidor
call /contest/admin/site-lock POST '{"action":"claim-seen"}' adm 'contest=sl'
ck "claim-seen prende os IPs de competidor vistos (1 novo; papel fora)" '[[ "$(J .claimed)" == 1 && -f "$RUN/site-lock/5.5.5.5" && ! -f "$RUN/site-lock/7.7.7.7" ]]'
call /contest/admin/site-lock POST '{"action":"set","enabled":false}' adm 'contest=sl'
ck "set enabled:false grava SITE_LOCK=0"  'grep -q "^SITE_LOCK=0$" "$C/conf"'
call /auth/login POST '{"username":"alice","password":"a"}' none 'contest=sl' 8.8.8.8
ck "trava desligada: login não reivindica" '[[ "$(J .logged_in)" == true && ! -f "$RUN/site-lock/8.8.8.8" ]]'
call /contest/admin/site-lock POST '{"action":"set","enabled":true,"grace":600}' adm 'contest=sl'
ck "set enabled+grace"                    '[[ "$(J .enabled)" == true && "$(J .grace)" == 600 ]]'

echo "== expiração =="
printf '4.4.4.4\tsl\t%s\t1\t1\t1\t0\t0\t\n' "$((NOW-10))" > "$RUN/site-lock/4.4.4.4"
call /treino/problems GET '' tradm 'q=x' 4.4.4.4
call /auth/login POST '{"username":"alice","password":"a"}' none 'contest=treino' 4.4.4.4
ck "reivindicação vencida não prende"     '[[ "$(J .logged_in)" == true ]]'
echo "== prova acabada: não reivindica =="
sed -i "s/^CONTEST_END=.*/CONTEST_END=$((NOW-90000))/" "$C/conf"
call /auth/login POST '{"username":"alice","password":"a"}' none 'contest=sl' 3.3.3.3
ck "login depois do fim + folga não prende" '[[ "$(J .logged_in)" == true && ! -f "$RUN/site-lock/3.3.3.3" ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
