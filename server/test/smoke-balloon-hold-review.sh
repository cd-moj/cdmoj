#!/bin/bash
# smoke-balloon-hold-review.sh — a ESPERA do "primeiro da sede" (lib/print.sh, .balloon-hold) × FREEZE, rejulgamento e
# volume:
#   S1  AC DEPOIS do freeze num par retido: vira lápide na hora e não entra no `held` da fila da sede;
#   S1b descongelar ("Encerrar evento") com o par ainda esperando não solta o balão do freeze;
#   S2  o AC retido que vira WA (rejulgamento/revisão) não ganha balão nem estrela;
#   S4  GET /contest/admin/balloon-release com 1.500 retidos (240 KB): 200.
set -u
export BALLOON_RECONCILE_FLOOR_S=0
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$ROOT/test/fixture.sh"
export MOJ_JOBS_SYNC=1 CONTESTSDIR="$FIX"
C="$FIX/bs"; mkdir -p "$C/var" "$C/print-requests"
NOW="$(date +%s)"; T0=$((NOW-3600))
conf(){ { printf 'CONTEST_ID=bs\nCONTEST_MODULES=sedes,maquinas,baloes,coortes,inscricoes\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nUSER_STORE=v2\n' "$T0" "$((NOW+3600))"
          printf 'PROBS=( cdmoj apc#p1 Um A apc#p1 )\n'
          [[ -n "${1:-}" ]] && printf '%s\n' "$1"; } > "$C/conf"; }
conf "FREEZE_TIME=$((T0+1000))"
fx_user "$C" bs.admin p "Admin"; fx_user "$C" sa.staff p "Staff A"; fx_user "$C" sa.cstaff p "Chefe A"
for u in a1 a2 b1; do fx_user "$C" "$u" x "Time ${u}"; done
setreg(){ local u="$1" r="$2" f; f="$C/users/$u/account.json"; jq -c --arg r "$r" '.team = ((.team // {}) + {region:$r})' "$f" > "$f.t" && mv "$f.t" "$f"; }
setreg a1 "Sede A"; setreg a2 "Sede A"; setreg b1 "Sede B"
printf '%s' '{"sa.staff":["region:Sede A"],"sa.cstaff":["region:Sede A"]}' > "$C/print-requests/staff-filters.json"
for t in bs.admin:adm sa.staff:stf sa.cstaff:cst; do printf 'CONTEST=bs\nLOGIN=%s\nUSERFULLNAME=x\nLOGINAT=1\n' "${t%%:*}" > "$SESS/${t##*:}"; done
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD=GET QUERY_STRING="${2:-}" HTTP_AUTHORIZATION="Bearer ${3:-adm}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" </dev/null 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
source "$ROOT/api/v1/lib/verdict.sh"; source "$ROOT/api/v1/lib/users.sh"
hist(){ printf '%s\n' "$2" > "$C/users/$1/history"; metrics_recompute bs "$1"; }
touchdirty(){ sleep 1; touch "$C/var/.score-dirty"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:300}"; ((fail++)); fi; }

echo "== S1: AC pós-freeze num par retido =="
hist a2 "$((T0+1100)):apc#p1:C:Not Answered Yet:$((T0+1100)):s1"
hist a1 "$((T0+1200)):apc#p1:C:Accepted,100p:$((T0+1200)):s2"
touchdirty
call /contest/staff/queue contest=bs stf; ck "staff: held vazio (o AC pós-freeze não aparece)" '[[ "$(jq -c ".held" <<<"$BODY")" == "[]" ]]'
call /contest/staff/queue contest=bs cst; ck "cstaff: held vazio" '[[ "$(jq -c ".held" <<<"$BODY")" == "[]" ]]'
ck "virou lápide do freeze, não espera" '[[ ! -s "$C/print-requests/.balloon-hold" && "$(wc -l < "$C/print-requests/.balloon-frozen")" == 1 ]]'

echo "== S1b: descongelar com o par ainda esperando =="
conf "FREEZE_TIME=0"
hist a2 "$((T0+1100)):apc#p1:C:Wrong Answer,0p:$((T0+1100)):s1"
touchdirty
call /contest/staff/queue contest=bs adm
ck "nenhuma tarefa de balão do freeze" '[[ "$(jq -c "[.requests[]|select(.kind==\"balloon\")]|length" <<<"$BODY")" == 0 ]]'

echo "== S2: AC revogado enquanto retido =="
rm -f "$C"/print-requests/bln* "$C/print-requests/.balloon-hold" "$C/print-requests/.balloon-stamp" "$C/print-requests/.balloon-frozen" "$C/print-requests/.balloon-prev"
conf ""
hist b1 "$((T0+100)):apc#p1:C:Not Answered Yet:$((T0+100)):s3"
setreg a1 "Sede B"
hist a1 "$((T0+200)):apc#p1:C:Accepted,100p:$((T0+200)):s4"
touchdirty; call /contest/staff/queue contest=bs adm
ck "o AC do a1 espera a run mais antiga do b1" '[[ "$(jq -c "[.held[]|.login]" <<<"$BODY")" == "[\"a1\"]" ]]'
hist a1 "$((T0+200)):apc#p1:C:Wrong Answer,0p:$((T0+200)):s4"
hist b1 "$((T0+100)):apc#p1:C:Wrong Answer,0p:$((T0+100)):s3"
touchdirty; call /contest/staff/queue contest=bs adm
ck "revogado: sem balão (e sem estrela)" '[[ "$(jq -c "[.requests[]|select(.kind==\"balloon\")]|length" <<<"$BODY")" == 0 && ! -s "$C/print-requests/.balloon-hold" ]]'

echo "== S4: GET balloon-release com muitos retidos =="
H="$C/print-requests/.balloon-hold"; : > "$H"
for i in $(seq 1 1500); do printf '{"login":"time-com-nome-longo-%05d","problem":"apc#p1","short":"A","region":"Sede Bem Comprida %d","sub_epoch":%d,"since":%d,"pend":%d}\n' $i $((i%7)) $((T0+i)) $NOW $T0 >> "$H"; done
call /contest/admin/balloon-release contest=bs adm
ck "200 com os 1.500" '[[ "$OUT" == *"Status: 200"* && "$(jq ".held|length" <<<"$BODY")" == 1500 ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
