#!/bin/bash
# DERRUBAR AS SESSÕES DE UM LOGIN SEM LER O DIRETÓRIO INTEIRO (lib/auth.sh remove_contest_sessions_v).
# Relato (Ribas, 2026-09-19): "nova senha" de uma conta gerida (`zan`) não mostrava a senha. O servidor
# gerava e devolvia — mas levava 38 s: o handler lia os 21.254 arquivos de sessão com um fork POR
# ARQUIVO, e quem clicava desistia antes (6 resets, nenhuma senha vista). Hoje: um grep acha os
# candidatos pelo texto `LOGIN=<login>` e só eles são confirmados por source. Este teste fixa a
# SEMÂNTICA (contest e login exatos; prefixo e outro contest ficam) e o CUSTO (milhares de sessões).
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$HERE/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN"
NOW="$EPOCHSECONDS"; T="$FIX/treino"; mkdir -p "$T/var" "$FIX/outro"
printf 'CONTEST_ID=treino\nCONTEST_END=%s\n' "$((NOW+86400))" > "$T/conf"; printf 'CONTEST_ID=outro\n' > "$FIX/outro/conf"
fx_user "$T" chefe.admin s "Chefe"
for u in zan zang ana bia 'jo.e@x'; do fx_user "$T" "$u" s "$u"; done
for u in zan zang; do jq '.managed={by:"chefe.admin",birthdate:"2014-01-01",created_at:1}' "$T/users/$u/account.json" > "$T/users/$u/a" && mv "$T/users/$u/a" "$T/users/$u/account.json"; done
ses(){ printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\nIP=%q\nUA_B64=%q\nMKEY=%q\n' "$2" "$3" "$3" "$NOW" 1.2.3.4 "" "" > "$SESS/$1"; }
ses tok-adm treino chefe.admin
ses z1 treino zan; ses z2 treino zan; ses zo outro zan; ses zg treino zang; ses zf treino 'zan zan'
ses a1 treino ana; ses b1 treino bia; ses j1 treino 'jo.e@x'
# milhares de sessões alheias: é o que tornava a rota lenta
for i in $(seq 1 6000); do printf 'CONTEST=treino\nLOGIN=u%d\nUSERFULLNAME=u\nLOGINAT=1\nIP=1\nUA_B64=\nMKEY=\n' "$i" > "$SESS/x$i"; done
call(){ local t0=$EPOCHREALTIME; OUT="$(PATH_INFO="$1" REQUEST_METHOD=POST QUERY_STRING= HTTP_AUTHORIZATION="Bearer tok-adm" bash "$ROUTER" <<<"$2" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; ELAPSED="$(awk -v a="$t0" -v b="$EPOCHREALTIME" 'BEGIN{printf "%.2f", b-a}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${OUT:0:220}"; ((fail++)); fi; }
has(){ [[ -f "$SESS/$1" ]]; }

echo "== nova senha de conta gerida (o relato) =="
call /treino/admin/managed-reset '{"login":"zan"}'
ck "200 e a senha VEM na resposta"                '[[ "$OUT" == *"Status: 200"* && -n "$(jq -r .password <<<"$BODY")" ]]'
ck "a senha devolvida é a gravada"                '[[ "$(jq -r .password "$T/users/zan/account.json")" == "$(jq -r .password <<<"$BODY")" ]]'
ck "caem as 2 sessões de zan no treino"           '[[ "$(jq -r .sessions_removed <<<"$BODY")" == 2 ]] && ! has z1 && ! has z2'
ck "ficam: zan em OUTRO contest, zang (prefixo), 'zan zan', o admin" 'has zo && has zg && has zf && has tok-adm'
ck "rápido com 6000 sessões no diretório (${ELAPSED}s)" 'awk -v e="$ELAPSED" "BEGIN{exit !(e < 4)}"'
echo "== as rotas irmãs usam o mesmo caminho =="
ses z3 treino zan
call /treino/admin/managed-update '{"login":"zan","disabled":true}'
ck "desabilitar derruba a sessão"                 '[[ "$OUT" == *"Status: 200"* ]] && ! has z3 && has zg'
call /treino/admin/lock-user '{"logins":["ana","bia"]}'
ck "lock-user (vários): as duas caem, conta"      '[[ "$(jq -r .sessions_removed <<<"$BODY")" == 2 ]] && ! has a1 && ! has b1'
ses a2 treino ana; ses a3 treino ana
call /treino/admin/logout-user '{"logins":["ana","jo.e@x","ninguem"]}'
ck "logout-user: conta e lista quem caiu"         '[[ "$(jq -r .sessions_removed <<<"$BODY")" == 3 && "$(jq -c ".users|sort" <<<"$BODY")" == "[\"ana\",\"jo.e@x\"]" ]] && ! has j1'
call /treino/admin/managed-remove '{"login":"zang"}'
ck "remover conta gerida derruba a sessão dela"   '[[ "$OUT" == *"Status: 200"* ]] && ! has zg && has zf'
echo "== o helper direto =="
( _LIBDIR="$ROOT/api/v1/lib"; source "$_LIBDIR/common.sh" 2>/dev/null; source "$_LIBDIR/session-index.sh" 2>/dev/null; source "$_LIBDIR/auth.sh" 2>/dev/null
  ses q1 outro zan; ses q2 outro ana
  printf '%s\n' "$(remove_contest_sessions_v outro zan ana | cut -f1,2 | sort | tr '\t\n' ':,')" > "$RUN/v.out"
  printf '%s' "$(remove_contest_sessions outro)" > "$RUN/n.out" ) 
ck "_v: token\\tlogin de cada removida (vários logins)" '[[ "$(cat "$RUN/v.out")" == "q1:zan,q2:ana,zo:zan," ]]'
ck "sem login: remove TODAS do contest (nenhuma sobrou)" '[[ "$(cat "$RUN/n.out")" == 0 ]] && ! grep -rlq "CONTEST=outro" "$SESS"'
echo "== aba \"Sessões ativas\" (GET /treino/admin/sessions): uma passada, mesma resposta de antes =="
ses u1 treino 'Zé da Silva'; printf 'USERFULLNAME=%q\n' $'Nome com\nquebra' >> "$SESS/u1"
UA="$(printf 'Mozilla/5.0 (X11) Firefox' | base64 -w0)"; sed -i "s/^UA_B64=.*/UA_B64=$UA/" "$SESS/u1"
GET(){ local t0=$EPOCHREALTIME; OUT="$(PATH_INFO="$1" REQUEST_METHOD=GET QUERY_STRING= HTTP_AUTHORIZATION="Bearer tok-adm" bash "$ROUTER" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; ELAPSED="$(awk -v a="$t0" -v b="$EPOCHREALTIME" 'BEGIN{printf "%.2f", b-a}')"; }
GET /treino/admin/sessions
N="$(grep -rlx 'CONTEST=treino' "$SESS" | wc -l)"
ck "lista TODAS as sessões do treino (e só elas)"     '[[ "$OUT" == *"Status: 200"* && "$(jq -r .count <<<"$BODY")" == "$N" ]]'
ck "user-agent decodificado, nome sem quebrar a linha" '[[ "$(jq -r ".sessions[]|select(.login==\"Zé da Silva\")|.user_agent" <<<"$BODY")" == "Mozilla/5.0 (X11) Firefox" && "$(jq -r ".sessions[]|select(.login==\"Zé da Silva\")|.name" <<<"$BODY")" == "Nome com quebra" ]]'
ck "ordenada pela hora de login (mais recente 1º)"   '[[ "$(jq -r "[.sessions[].login_at] | . == (sort|reverse)" <<<"$BODY")" == true ]]'
ck "rápido com milhares de sessões (${ELAPSED}s)"     'awk -v e="$ELAPSED" "BEGIN{exit !(e < 4)}"'
echo "== deslogar por IP =="
ses i1 treino ana; ses i2 treino bia; ses i3 outro ana; sed -i 's/^IP=.*/IP=10.0.0.9/' "$SESS/i1" "$SESS/i2" "$SESS/i3"
call /treino/admin/logout-ip '{"ip":"10.0.0.9"}'
ck "caem as 2 do treino naquele IP; a de outro contest fica" '[[ "$(jq -r .sessions_removed <<<"$BODY")" == 2 && "$(jq -c ".users|sort" <<<"$BODY")" == "[\"ana\",\"bia\"]" ]] && ! has i1 && ! has i2 && has i3'
echo; echo "RESULT: $pass passed, $fail failed"; (( fail == 0 ))
