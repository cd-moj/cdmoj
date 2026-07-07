#!/bin/bash
# Papel .cstaff (chefe de sede): placar congelado por padrão; full escopado (scope=mine)
# só quando o contest terminou PARA TODOS (time-overrides seguram a revelação); allowlist
# SCORE_FULL_USERS libera o full; etiquetas com senha são dele (.staff 403; toggle extinto
# → POST 405); fila em modo leitura (ações/PDF/arquivo 403); fora do placar; sem submit;
# navbuttons próprios (staff perde Etiquetas); isento do UA-gate.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"

NOW="$EPOCHSECONDS"; START=$(( NOW - 7200 )); FREEZE=$(( NOW - 3600 )); END=$(( NOW - 600 ))
C="$FIX/cs"; mkdir -p "$C/var" "$C/print-requests"
{ printf 'CONTEST_ID=cs\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nFREEZE_TIME=%s\nUSER_STORE=v2\n' \
    "$START" "$END" "$FREEZE"
  printf "PROBS=(f0 col/pa 'Prob A' A 'col#pa' f1 col/pb 'Prob B' B 'col#pb')\n"; } > "$C/conf"
fx_user "$C" cs.admin p "Admin"
fx_user "$C" sede1.cstaff p "Chefe Sede Um"
fx_user "$C" sede1.staff p "Staff Sede Um"
fx_user "$C" aluno1 a "Aluno Um"
fx_user "$C" aluno2 b "Aluno Dois"
# aluno1 (sede do cstaff): AC pré-freeze em A + AC pós-freeze em B (este só no full).
{ printf '10:col#pa:c:Accepted,100p:%s:s1\n' $(( START + 600 ))
  printf '20:col#pb:c:Accepted,100p:%s:s2\n' $(( FREEZE + 60 )); } > "$C/users/aluno1/history"
# aluno2 (outra sede): AC pré-freeze em A.
printf '15:col#pa:c:Accepted,100p:%s:s3\n' $(( START + 900 )) > "$C/users/aluno2/history"
# conta de papel com history: NÃO entra no placar nem vira balão (sc_is_real_user/reconcile).
printf '5:col#pa:c:Accepted,100p:%s:s4\n' $(( START + 300 )) > "$C/users/sede1.cstaff/history"
touch "$C/var/.score-dirty"    # o reconcile de balões só varre depois de submissão (marcador)
# escopo da sede 1: cstaff e staff só veem o aluno1
printf '%s' '{"sede1.cstaff":["^aluno1$"],"sede1.staff":["^aluno1$"]}' > "$C/print-requests/staff-filters.json"
# pedidos de impressão: pr1 do aluno1 (no escopo do cstaff), pr2 do aluno2 (fora)
mkpr(){ printf '{"id":"%s","seq":%s,"kind":"print","login":"%s","fullname":"%s","team":"","univ":"","filename":"sol.c","mime":"text/plain","size":10,"time":%s,"status":"pending","pages":1,"claimed_by":"","claimed_at":0,"processed_by":"","processed_at":0,"delivered_by":"","delivered_at":0}' \
  "$1" "$2" "$3" "$3" "$NOW" > "$C/print-requests/$1.json"; printf 'x' > "$C/print-requests/$1.src"; }
mkpr pr1 1 aluno1; mkpr pr2 2 aluno2

mktok(){ printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' cs "$1" "$1" "$NOW" > "$SESS/$2"; }
mktok cs.admin adm; mktok sede1.cstaff cst; mktok sede1.staff stf; mktok aluno2 alu

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="${2:-GET}" QUERY_STRING="${4:-}" \
    HTTP_AUTHORIZATION="${3:+Bearer $3}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${5:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }
a1cells(){ grep ":aluno1:" <<<"$BODY" | head -1; }

echo "== placar: cstaff default = congelado COMPLETO (sem recorte) =="
call /contest/score GET cst 'contest=cs'
ck "vê aluno2 (sem recorte)"          '[[ "$BODY" == *":aluno2:"* ]]'
ck "congelado (sem o AC pós-freeze)"  '[[ -n "$(a1cells)" && "$(a1cells)" != *"1/61"* ]]'
ck "conta de papel fora do placar"    '[[ "$BODY" != *":sede1.cstaff:"* ]]'

echo "== scope=mine: recorte por sede nas DUAS visões =="
call /contest/score GET cst 'contest=cs&view=public&scope=mine'
ck "frozen recortado: sem aluno2"     '[[ "$BODY" != *":aluno2:"* && "$BODY" == *":aluno1:"* ]]'
ck "modo+header intactos"             '[[ "$(head -1 <<<"$BODY")" == icpc && "$(sed -n 2p <<<"$BODY")" == *username* ]]'
call /contest/score GET cst 'contest=cs&scope=mine'
ck "pós-fim: full recortado (1/61)"   '[[ "$(a1cells)" == *"1/61"* && "$BODY" != *":aluno2:"* ]]'

echo "== prorrogação segura o full; allowlist SCORE_FULL_USERS libera =="
printf '[{"regex":"^aluno2","end":%s,"reason":"queda de energia"}]' $(( NOW + 1800 )) > "$C/time-overrides.json"
call /contest/score GET cst 'contest=cs&scope=mine'
ck "sede prorrogada: volta o frozen"  '[[ -n "$(a1cells)" && "$(a1cells)" != *"1/61"* ]]'
printf 'SCORE_FULL_USERS=sede1.cstaff\n' >> "$C/conf"
call /contest/score GET cst 'contest=cs&scope=mine'
ck "allowlist: full mesmo prorrogado" '[[ "$(a1cells)" == *"1/61"* ]]'
call /contest/score GET cst 'contest=cs'
ck "allowlist sem scope: full inteiro" '[[ "$(a1cells)" == *"1/61"* && "$BODY" == *":aluno2:"* ]]'
rm -f "$C/time-overrides.json"

echo "== scope=mine de não-cstaff é ignorado =="
call /contest/score GET alu 'contest=cs&scope=mine'
ck "aluno: sem recorte e congelado"   '[[ "$BODY" == *":aluno2:"* && -n "$(a1cells)" && "$(a1cells)" != *"1/61"* ]]'

echo "== etiquetas: staff 403; cstaff com senha; toggle extinto =="
call /contest/badges GET stf 'contest=cs'
ck "staff perdeu as etiquetas (403)"  '[[ "$OUT" == *"Status: 403"* && "$BODY" == *cstaff_required* ]]'
call /contest/badges GET cst 'contest=cs'
ck "cstaff vê aluno1 COM senha"       '[[ "$(jq -r ".users[]|select(.login==\"aluno1\").password" <<<"$BODY")" == a ]]'
ck "recorte: sem aluno2"              '[[ "$(jq -r "[.users[]|select(.login==\"aluno2\")]|length" <<<"$BODY")" == 0 ]]'
ck "a própria credencial entra"       '[[ "$(jq -r ".users[]|select(.login==\"sede1.cstaff\").password" <<<"$BODY")" == p ]]'
ck "staff fora do escopo não entra"   '[[ "$(jq -r "[.users[]|select(.login==\"sede1.staff\")]|length" <<<"$BODY")" == 0 ]]'
ck "flag staff_password extinta"      '[[ "$(jq -r "has(\"staff_password\")" <<<"$BODY")" == false ]]'
call /contest/badges GET cst 'contest=cs&staff=cs.admin'
ck "cstaff não espia outro arquivo"   '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/badges POST adm 'contest=cs' '{"staff_password":false}'
ck "POST extinto (405)"               '[[ "$OUT" == *"Status: 405"* ]]'
call /contest/badges GET adm 'contest=cs'
ck "seletor do admin = só .cstaff"    '[[ "$(jq -r ".staff|length" <<<"$BODY")" == 1 && "$(jq -r ".staff[0].login" <<<"$BODY")" == sede1.cstaff ]]'
ck "lista completa: os dois papéis"   '[[ -n "$(jq -r ".users[]|select(.login==\"sede1.staff\").login" <<<"$BODY")" && -n "$(jq -r ".users[]|select(.login==\"sede1.cstaff\").login" <<<"$BODY")" ]]'
call /contest/badges GET adm 'contest=cs&staff=sede1.cstaff'
ck "arquivo da sede p/ admin"         '[[ "$(jq -r "[.users[]|select(.login==\"aluno2\")]|length" <<<"$BODY")" == 0 && -n "$(jq -r ".users[]|select(.login==\"aluno1\").login" <<<"$BODY")" ]]'
call /contest/badges GET adm 'contest=cs&staff=sede1.staff'
ck "staff= só aceita .cstaff (400)"   '[[ "$OUT" == *"Status: 400"* ]]'

echo "== fila: cstaff lê o escopo, não age =="
call /contest/staff/queue GET cst 'contest=cs'
ck "vê pr1 (aluno1)"                  '[[ -n "$(jq -r ".requests[]|select(.id==\"pr1\").id" <<<"$BODY")" ]]'
ck "não vê pr2 (fora do escopo)"      '[[ "$(jq -r "[.requests[]|select(.id==\"pr2\")]|length" <<<"$BODY")" == 0 ]]'
ck "balões do escopo (só aluno1)"     '[[ "$(jq -r "[.requests[]|select(.kind==\"balloon\")]|length" <<<"$BODY")" == 2 && "$(jq -cr "[.requests[]|select(.kind==\"balloon\").login]|unique" <<<"$BODY")" == "[\"aluno1\"]" ]]'
call /contest/staff/queue GET adm 'contest=cs'
ck "reconcile ignora conta de papel"  '[[ "$(jq -r "[.requests[]|select(.kind==\"balloon\")]|length" <<<"$BODY")" == 3 && "$(jq -r "[.requests[]|select(.kind==\"balloon\" and .login==\"sede1.cstaff\")]|length" <<<"$BODY")" == 0 ]]'
call /contest/staff/print-action POST cst 'contest=cs' '{"id":"pr1","action":"claim"}'
ck "ação vedada ao cstaff (403)"      '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/staff/print-pdf GET cst 'contest=cs&id=pr1'
ck "PDF vedado ao cstaff (403)"       '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/print-file GET cst 'contest=cs&id=pr1'
ck "arquivo cru vedado (403)"         '[[ "$OUT" == *"Status: 403"* ]]'

echo "== papel: navbuttons, status, submit, problems =="
call /contest/navbuttons GET cst 'contest=cs'
ck "cstaff: Etiquetas + Revelação"    '[[ "$BODY" == *Etiquetas* && "$BODY" == *"Revela"* ]]'
call /contest/navbuttons GET stf 'contest=cs'
ck "staff sem Etiquetas"              '[[ "$BODY" != *Etiquetas* && "$BODY" == *"Impress"* ]]'
call /auth/status GET cst 'contest=cs'
ck "is_cstaff no status"              '[[ "$(jq -r .is_cstaff <<<"$BODY")" == true && "$(jq -r .is_staff <<<"$BODY")" == false ]]'
call /submit POST cst 'contest=cs' '{"problem_id":"col#pa","filename":"a.c","code_b64":"aQ=="}'
ck "cstaff não submete (403)"         '[[ "$OUT" == *"Status: 403"* && "$BODY" == *submit_forbidden* ]]'
call /contest/problems GET cst 'contest=cs'
ck "problems locked=staff"            '[[ "$(jq -r .locked <<<"$BODY")" == staff ]]'
ck "is_reserved_role_login .cstaff"   '(cd "$ROOT/api/v1" && bash -c "source lib/common.sh; source lib/auth.sh; is_reserved_role_login foo.cstaff")'

echo "== UA-gate: papel isento =="
printf 'LOGIN_UA_SUBSTRING=MOJBOX\n' >> "$C/conf"
call /auth/login POST '' 'contest=cs' '{"username":"sede1.cstaff","password":"p"}'
ck "cstaff loga sem o UA da prova"    '[[ "$(jq -r .success <<<"$BODY")" == true ]]'
call /auth/login POST '' 'contest=cs' '{"username":"aluno2","password":"b"}'
ck "aluno continua barrado (403)"     '[[ "$OUT" == *"Status: 403"* && "$BODY" == *ua_gate* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
