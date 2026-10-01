#!/bin/bash
# smoke-classify-mundial.sh — motor `latam-mundial` (score/classify-mundial.sh), "Promotion to the World Finals": o
# campeão de cada região (≥1 resolvido), N_WF − campeões do geral, 1 time por instituição, região sem time elegível
# vira vaga do geral (ou não, com region_slot_unfilled:none), prêmios informativos com empate que estica a medalha,
# exclude/preassigned, N_WF ausente, --check e o estágio no handler (chip "Mundial").
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
export CONTESTSDIR="$FIX"
ENG="$ROOT/score/classify-mundial.sh"
C="$FIX/lac"; mkdir -p "$C/var" "$C/enunciados"
NOW=$(date +%s); T0=$(( NOW - 7200 ))
{ printf 'CONTEST_ID=lac\nCONTEST_TYPE=icpc\nCONTEST_NAME=LAC\nLOCALE=es\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$T0" "$(( NOW + 3600 ))"
  printf 'PROBS=( x col#p1 P1 A col#p1 x col#p2 P2 B col#p2 x col#p3 P3 C col#p3 x col#p4 P4 D col#p4 x col#p5 P5 E col#p5 )\n'
} > "$C/conf"
jq -n '[{name:"LATAM", regex:"^team"}]' > "$C/regions.json"
mkteam(){ local login="$1" univ="$2" mins="$3"; mkdir -p "$C/users/$login"
  jq -cn --arg l "$login" --arg u "$univ" '{login:$l, fullname:("Time " + $l), password:"x", team:{univ_short:$u, univ_full:("Univ " + $u)}}' > "$C/users/$login/account.json"
  : > "$C/users/$login/history"; local i=0 m se
  for m in ${mins//,/ }; do i=$((i+1)); se=$(( T0 + m*60 ))
    printf '%s:col#p%d:C:Accepted:%s:id%s%d\n' "$se" "$i" "$se" "$login" "$i" >> "$C/users/$login/history"; done; }
mkteam teambrbr01 USP     "1,1,2,3,3"     # 1
mkteam teambrbr02 USP     "2,3,4,5,6"     # 2  (USP: já tem o br01)
mkteam teammxmx01 UNAM    "6,7,8,9,10"    # 3
mkteam teamsoar01 UBA     "3,4,6,7"       # 4  ┐ empatados: a medalha de ouro vai a 5 times
mkteam teambrbr03 UNICAMP "3,4,6,7"       # 4  ┘
mkteam teamsocl01 UCHILE  "6,7,8,9"       # 6
mkteam teamnove01 USB     "2,3,5"         # 7
mkteam teammxmx02 ITESM   "5,7,8"         # 8
mkteam teamcbcu01 UH      "4,6"           # 9
mkteam teambrbr04 UFMG    "9,11"          # 10
mkteam teamnoco01 UNAL    "10"            # 11
mkteam teamcacr01 TEC     ""              # 12  0 resolvidos: a América Central fica sem campeão elegível
( cd "$ROOT/score" && CONTESTSDIR="$FIX" bash build.sh lac >/dev/null 2>&1 )
[[ -s "$C/var/placar.txt" ]] || { echo "build.sh não gerou placar"; exit 1; }

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
bad(){ FAIL=$((FAIL+1)); echo "FALHOU: $*" >&2; }
eqk(){ [[ "$1" == "$2" ]] && ok || bad "$3 (veio '$1', esperado '$2')"; }
jq '.N_WF = 8' "$ROOT/score/classify-seeds/latam-mundial-2027.json" > "$FIX/cfg.json"
run(){ bash "$ENG" lac "$1" "$2" 2>"$FIX/err"; }
O="$FIX/o.json"; run "$FIX/cfg.json" "$O" || { cat "$FIX/err"; echo "motor falhou"; exit 1; }
lst(){ jq -r --arg v "$1" '[.classified[] | select(.via == $v) | .login] | join(",")' "$2"; }

eqk "$(lst wf-region "$O")" "teambrbr01,teamcbcu01,teammxmx01,teamnove01,teamsoar01" "campeões das regiões (≥1 resolvido; ca sem elegível)"
eqk "$(jq -r '[.warnings[] | select(.code=="wf_region_unfilled") | .data.region] | join(",")' "$O")" "ca" "aviso: região sem campeão elegível"
eqk "$(lst wf-overall "$O")" "teambrbr03,teamsocl01,teammxmx02" "geral: 8 − 6 + 1 (a vaga da ca) = 3, 1 por instituição (USP já foi)"
eqk "$(jq -r '.total' "$O")" "8" "N_WF times"
eqk "$(jq -r '[.classified[] | select(.login=="teamnove01") | .sede] | join("")' "$O")" "Sudamérica Norte" "região pelo LOCALE (es)"
eqk "$(jq -r '[.awards.champion[].login] | join(",")' "$O")" "teambrbr01" "campeão LATAM"
eqk "$(jq -r '[(.awards.medals.gold | length), (.awards.medals.silver | length), (.awards.medals.bronze | length)] | join(",")' "$O")" "5,3,4" "medalhas: empate no 4º estica o ouro"
eqk "$(jq -r '[.warnings[] | select(.code=="award_tie") | "\(.data.medal):\(.data.teams)"] | join(",")' "$O")" "gold:5" "aviso award_tie"
eqk "$(jq -r '[.awards.regional[] | "\(.region)=\(.login)"] | join(",")' "$O")" "br=teambrbr01,cb=teamcbcu01,ca=teamcacr01,mx=teammxmx01,no=teamnove01,so=teamsoar01" "campeões regionais (informativo: a ca tem título mesmo com 0)"
eqk "$(jq -r '.awards.regional[] | select(.region=="cb") | .title' "$O")" "Campeones Regionales del Caribe" "título da região no LOCALE"
jq '.region_slot_unfilled = "none"' "$FIX/cfg.json" > "$FIX/c2.json"; run "$FIX/c2.json" "$FIX/o2.json"
eqk "$(lst wf-overall "$FIX/o2.json"):$(jq -r '.total' "$FIX/o2.json")" "teambrbr03,teamsocl01:7" "region_slot_unfilled none: a vaga da região sem time some"
jq '. + {exclude:["teambrbr01"]}' "$FIX/cfg.json" > "$FIX/c3.json"; run "$FIX/c3.json" "$FIX/o3.json"
eqk "$(jq -r '.classified[] | select(.via=="wf-region" and .region=="br") | .login' "$FIX/o3.json")" "teambrbr02" "exclude: a USP volta a ter vaga (br02 campeão)"
jq '. + {preassigned:[{login:"teambrbr03"}]}' "$FIX/cfg.json" > "$FIX/c4.json"; run "$FIX/c4.json" "$FIX/o4.json"
eqk "$(lst wf-overall "$FIX/o4.json")" "teamsocl01,teammxmx02,teambrbr04" "preassigned: fora do cálculo, a UNICAMP conta como instituição com time"
jq '.N_WF = null' "$FIX/cfg.json" > "$FIX/c5.json"; run "$FIX/c5.json" "$FIX/o5.json"
eqk "$(jq -r '"\(.total) \([.warnings[] | select(.code=="n_wf_missing")] | length)"' "$FIX/o5.json")" "0 1" "sem N_WF: ninguém, com aviso"
jq '.region_slot_unfilled = "x"' "$FIX/cfg.json" > "$FIX/k1.json"
bash "$ENG" --check "$FIX/k1.json" 2>"$FIX/k1.err"; eqk "$?" "2" "--check reprova region_slot_unfilled inválido"
bash "$ENG" --check "$ROOT/score/classify-seeds/latam-mundial-2027.json" && ok || bad "a semente oficial passa no --check"

# handler: estágio mundial (padrão do motor) com o chip
ROUTER="$ROOT/api/v1/router.sh"
mkdir -p "$C/users/lac.admin"; jq -cn '{login:"lac.admin", fullname:"Admin", password:"x"}' > "$C/users/lac.admin/account.json"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' lac lac.admin Admin "$NOW" > "$SESS/t-adm"
calla(){ OUT="$(PATH_INFO=/contest/admin/classify REQUEST_METHOD="$1" QUERY_STRING="contest=lac" HTTP_AUTHORIZATION="Bearer t-adm" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${2:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
calla POST "$(jq -cn --slurpfile c "$FIX/cfg.json" '{action:"apply", config:$c[0]}')"
eqk "$(jq -r '.stage' <<<"$BODY")" "mundial" "apply: estágio padrão do motor"
eqk "$(jq -r '.stages[] | select(.id=="mundial") | "\(.chip) \(.teams | length) \(.labels["wf-region"].es)"' "$C/classification.json")" "Mundial 8 Campeón de la región" "estágio com chip, times e rótulos"
calla POST '{"action":"promote_next","stage":"mundial","reason":"x"}'
eqk "$(jq -r '.error.code' <<<"$BODY")" "waitlist_unsupported" "Mundial não tem lista de espera"

echo "smoke-classify-mundial: PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
