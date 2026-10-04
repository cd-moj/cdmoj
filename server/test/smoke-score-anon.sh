#!/bin/bash
# smoke-score-anon.sh — PLACAR ANÔNIMO CORTADO NA API (SCORE_ANON=1; decisão do Ribas, 03/10/2026). Antes o anônimo era
# só a TELA: o TXT com logins, nomes e notas ia a todos e o navegador escondia. Agora quem não é da ORGANIZAÇÃO (o
# conjunto da estatística: admin, chefe, juiz, .mon, .animeitor) recebe SÓ o agregado (X-MOJ-Anon: 1) — nem
# SCORE_FULL_USERS, coorte ou scope=mine furam —, e as outras portas do placar fecham: relatório publicado (409),
# site da rodada (404), classificação pública (vazia) e participação virtual (portão fechado).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" SCOREDIR="$ROOT/score" MOJ_JOBS_SYNC=1
NOW="$EPOCHSECONDS"; C="$FIX/an"; mkdir -p "$C/var"
conf(){ { printf 'CONTEST_ID=an\nCONTEST_TYPE=icpc\nCONTEST_NAME=Anonima\nSCORE_ANON=1\nCONTEST_START=%s\nCONTEST_END=%s\n' "$1" "$2"
          printf 'SCORE_FULL_USERS=zzalfa\nCONTEST_MODULES=virtual\n'
          printf 'PROBS=( x col#pa Alfa A col#pa x col#pb Beta B col#pb )\n'; } > "$C/conf"; }
conf "$((NOW-3600))" "$((NOW+3600))"
for u in zzalfa zzbeta zzgama; do fx_user "$C" "$u" x "Equipe ${u#zz}"; done
for u in an.admin juiz.judge mm.mon tv.animeitor sd.cstaff ap.staff; do fx_user "$C" "$u" x "$u"; done
se=$((NOW-3000))
printf '%s:col#pa:C:Accepted:%s:i1\n%s:col#pb:C:Accepted:%s:i2\n' "$se" "$se" "$((se+60))" "$((se+60))" > "$C/users/zzalfa/history"
printf '%s:col#pa:C:Accepted:%s:i3\n' "$((se+30))" "$((se+30))" > "$C/users/zzbeta/history"
source "$ROOT/api/v1/lib/verdict.sh"; source "$ROOT/api/v1/lib/users.sh"
for u in zzalfa zzbeta zzgama; do metrics_recompute an "$u"; done
for u in zzalfa an.admin juiz.judge mm.mon tv.animeitor sd.cstaff ap.staff; do printf 'CONTEST=an\nLOGIN=%s\nUSERFULLNAME=x\nLOGINAT=1\n' "$u" > "$SESS/t-$u"; done
call(){ OUT="$(env PATH_INFO="$1" REQUEST_METHOD="${2:-GET}" QUERY_STRING="${4:-contest=an}" HTTP_AUTHORIZATION="${3:+Bearer t-$3}" bash "$ROUTER" <<<"${5:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${OUT:0:240}"; ((fail++)); fi; }
J(){ jq -r "$1" <<<"$BODY" 2>/dev/null; }
noname(){ ! grep -q "zzalfa\|zzbeta\|Equipe" <<<"$BODY"; }

echo "== placar: fora da organização, só o agregado =="
call /contest/score
ck "anônimo (sem sessão): X-MOJ-Anon, JSON com 3 participantes, nenhum login/nome" '[[ "$OUT" == *"X-MOJ-Anon: 1"* && "$(J .n)" == 3 && "$(J ".per_problem.A")" == 2 && "$(J ".q.max")" == 2 ]] && noname'
call /contest/score GET zzalfa
ck "time NA SCORE_FULL_USERS: segue anônimo (não fura)" '[[ "$OUT" == *"X-MOJ-Anon: 1"* ]] && noname'
call /contest/score GET sd.cstaff 'contest=an&scope=mine'
ck "cstaff com scope=mine: agregado" '[[ "$OUT" == *"X-MOJ-Anon: 1"* ]] && noname'
call /contest/score GET ap.staff 'contest=an&view=geral'
ck "staff com view=geral: agregado" '[[ "$OUT" == *"X-MOJ-Anon: 1"* ]] && noname'
for r in an.admin juiz.judge mm.mon tv.animeitor; do
  call /contest/score GET "$r"
  ck "organização ($r) recebe o TXT nominal" '[[ "$OUT" != *"X-MOJ-Anon"* && "$BODY" == *zzalfa* ]]'
done

echo "== antes do início: nem a vitrine com os nomes =="
conf "$((NOW+3600))" "$((NOW+7200))"
call /contest/score
ck "pré-início: agregado só com quantos (sem problema nenhum)" '[[ "$OUT" == *"X-MOJ-Anon: 1"* && "$(J .n)" == 3 && "$(J ".problems|length")" == 0 ]] && noname'
call /contest/score GET mm.mon
ck "pré-início: .mon (organização) recebe a vitrine" '[[ "$OUT" != *"X-MOJ-Anon"* && "$BODY" == *zzalfa* ]]'

echo "== as outras portas do placar =="
conf "$((NOW-7200))" "$((NOW-3600))"
call /contest/admin/report-publish POST an.admin contest=an '{"action":"publish"}'
ck "relatório publicado: 409 score_anon" '[[ "$OUT" == *"Status: 409"* && "$(J .error.code)" == score_anon ]]'
mkdir -p "$C/rounds/aq/relatorio"; printf '<html>zzalfa</html>' > "$C/rounds/aq/relatorio/index.html"
printf '{"version":1,"active":"of","rounds":[{"slug":"aq","name":"Aq","kind":"warmup","state":"archived","published":true},{"slug":"of","name":"Of","kind":"official","state":"active"}]}' > "$C/rounds.json"
call /contest/round GET zzalfa 'contest=an&round=aq'
ck "site da rodada publicada: 404 p/ o time" '[[ "$OUT" == *"Status: 404"* ]] && noname'
call /contest/round GET juiz.judge 'contest=an&round=aq'
ck "…e abre p/ o juiz" '[[ "$OUT" == *"Status: 200"* && "$BODY" == *zzalfa* ]]'
printf '{"version":1,"stages":[{"id":"final-br","status":"published","name":"Final","teams":{"zzalfa":{"via":"regra1"}}}]}' > "$C/classification.json"
call /contest/classification
ck "classificação pública: nenhum estágio" '[[ "$(J ".stages|length")" == 0 ]] && noname'
call /contest/classification GET an.admin
ck "…a organização vê" '[[ "$(J ".stages|length")" == 1 ]]'
call /contest/admin/virtual GET an.admin
ck "virtual: a checklist acusa o placar anônimo" '[[ "$(J ".checks[] | select(.id==\"score_anon\") | .ok")" == false && "$(J .eligible)" == false ]]'

echo; echo "RESULT: $pass passed, $fail failed"; (( fail == 0 ))
