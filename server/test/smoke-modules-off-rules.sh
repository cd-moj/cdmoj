#!/bin/bash
# smoke-modules-off-rules.sh — DESLIGAR O MÓDULO DESLIGA A REGRA (decisão do Ribas, 03/10/2026; lib/modules.sh).
# O MESMO contest, com todos os artefatos no disco, primeiro com os módulos ligados (a regra vale) e depois desligados
# pelo painel (a regra NÃO vale; nada é apagado):
#   maquinas   — gate de navegador (ua-gate.json) e trava de sede (SITE_LOCK; desligar SOLTA os IPs presos);
#   sedes      — prorrogação por sede (time-overrides.json): o fim efetivo do time volta ao do conf;
#   inscricoes — "só inscrito entra" (registrations.json);
#   coortes    — o corte do placar (cohorts.json): a coorte privada volta ao placar público;
#   baloes     — tarefas de balão do staff (religar faz a varredura completa: nada se perde).
set -u
export BALLOON_RECONCILE_FLOOR_S=0
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN"
NOW="$EPOCHSECONDS"; C="$FIX/mo"; mkdir -p "$C/var" "$C/print-requests"
{ printf 'CONTEST_ID=mo\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nSITE_LOCK=1\nUSER_STORE=v2\n' "$((NOW-600))" "$((NOW+3600))"
  printf 'CONTEST_MODULES=maquinas,sedes,inscricoes,coortes,baloes\n'
  printf 'PROBS=( cdmoj apc#p1 Um A apc#p1 )\n'; } > "$C/conf"
fx_user "$C" mo.admin p Admin; fx_user "$C" sede.staff p Staff
fx_user "$C" teama1 x "Time A1"; fx_user "$C" conv1 x "Convidado"
printf '{"mode":"enforce","by_regex":[{"regex":"^team","expect":"IMG-X"}]}' > "$C/ua-gate.json"
printf '[{"regex":"^teama","end":%s}]' "$((NOW+7200))" > "$C/time-overrides.json"
printf '{"version":1,"entries":{"teama1":{"kind":"individual"}},"teams":{}}' > "$C/registrations.json"
printf '{"version":1,"cohorts":[{"id":"oficial","name":"Oficiais","default":true,"public":true},{"id":"conv","name":"Conv","regex":"^conv","public":false}]}' > "$C/cohorts.json"
source "$ROOT/api/v1/lib/verdict.sh"; source "$ROOT/api/v1/lib/users.sh"
printf '%s:apc#p1:c:Accepted:%s:s1\n' 300 "$((NOW-300))" > "$C/users/teama1/history"; metrics_recompute mo teama1
touch "$C/var/.score-dirty"
printf 'CONTEST=mo\nLOGIN=mo.admin\nUSERFULLNAME=A\nLOGINAT=1\n' > "$SESS/adm"
# sessão do teama1 p/ o /contest/basic — criada na hora: o login com o gate valendo REVOGA as outras (sessão única)
tma(){ printf 'CONTEST=mo\nLOGIN=teama1\nUSERFULLNAME=T\nLOGINAT=1\n' > "$SESS/tma"; }

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${4:-contest=mo}" HTTP_AUTHORIZATION="Bearer ${5:-adm}" \
    HTTP_USER_AGENT="${6:-Mozilla/5.0 Chrome}" REMOTE_ADDR="${7:-7.7.7.7}" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
login(){ call /auth/login POST "{\"username\":\"$1\",\"password\":\"x\"}" contest=mo "" "${2:-Mozilla/5.0 Chrome}" "${3:-7.7.7.7}"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }
J(){ jq -r "$1" <<<"$BODY" 2>/dev/null; }
public_has(){ bash "$ROOT/score/build.sh" mo >/dev/null 2>&1; awk -F: 'NR>2' "$C/var/placar.txt" | grep -q ":$1:"; }
balloon_of(){ call /contest/staff/queue GET '' contest=mo; jq -e --arg l "$1" 'any(.requests[]; .kind == "balloon" and .login == $l)' <<<"$BODY" >/dev/null 2>&1; }

echo "== módulos LIGADOS: a regra vale =="
login teama1
ck "maquinas: navegador fora da imagem → 403 ua_gate" '[[ "$OUT" == *"Status: 403"* && "$(J .error.code)" == ua_gate ]]'
login teama1 "Mozilla/5.0 IMG-X"
ck "maquinas: com a imagem entra e PRENDE o IP (trava)" '[[ "$(J .logged_in)" == true && -f "$RUN/site-lock/7.7.7.7" ]]'
login conv1
ck "inscricoes: não inscrito → 403" '[[ "$OUT" == *"Status: 403"* ]]'
tma; call /contest/basic GET '' contest=mo tma
ck "sedes: o fim do teama1 é o prorrogado" '[[ "$(J .end_time)" == $((NOW+7200)) ]]'
ck "coortes: a coorte privada fica fora do placar público" '! public_has conv1 && public_has teama1'
ck "baloes: AC vira tarefa de balão" 'balloon_of teama1'

echo "== DESLIGADOS pelo painel: a regra NÃO vale (nada apagado) =="
call /contest/admin/modules POST '{"off":["maquinas","sedes","inscricoes","coortes","baloes"]}'
ck "desligar maquinas SOLTA os IPs presos por este contest" '[[ ! -f "$RUN/site-lock/7.7.7.7" ]]'
ck "os arquivos continuam no disco" '[[ -s "$C/ua-gate.json" && -s "$C/time-overrides.json" && -s "$C/registrations.json" && -s "$C/cohorts.json" ]]'
login teama1
ck "maquinas off: qualquer navegador entra, e o IP não é preso" '[[ "$(J .logged_in)" == true && ! -f "$RUN/site-lock/7.7.7.7" ]]'
login conv1
ck "inscricoes off: não inscrito entra" '[[ "$(J .logged_in)" == true ]]'
tma; call /contest/basic GET '' contest=mo tma
ck "sedes off: o fim do teama1 volta ao do conf" '[[ "$(J .end_time)" == $((NOW+3600)) ]]'
ck "coortes off: a coorte privada volta ao placar público" 'public_has conv1'
printf '%s:apc#p1:c:Accepted:%s:s2\n' 400 "$((NOW-200))" > "$C/users/conv1/history"; metrics_recompute mo conv1; sleep 1; touch "$C/var/.score-dirty"
ck "baloes off: AC novo NÃO vira tarefa" '! balloon_of conv1'
call /contest/admin/modules POST '{"on":["baloes"]}'
sleep 1; touch "$C/var/.score-dirty"
ck "religar baloes: a varredura completa cria o que faltou" 'balloon_of conv1'

echo; echo "RESULT: $pass passed, $fail failed"; (( fail == 0 ))
