#!/bin/bash
# smoke-classify-pda.sh — motor `latam-pda` (score/classify-pda.sh), regra "2026-2027 ICPC Latin America – Promotion
# Rules", num contest pelo STORE REAL (history → build.sh → placar) com N=12. Cada caso abaixo foi conferido à mão.
#   P1 desempenho (≤2 por escola: o 3º da USP pula) · P2 países (teto min(N/4, X) − 1 e a variante, país só com
#   0 resolvidos = zero_solved) · P3 sede (vai a uma escola NÃO-sede) · P4 geográfica (frações, empate que estoura
#   N, região sem time elegível) · femininas ignoram a regra geral (3º time da USP) · pendente que não conta ·
#   participação por país (contagens do contest e a tabela do RCD, desempate por instituições) · sede extra sem a
#   regra geral · reserva · lista de espera com e sem a regra geral · preassigned/exclude · recusa por código ·
#   --check · exatidão inteira (--geo) · e o handler (estágio pda + chip, promote_next, reserva cheia).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
export CONTESTSDIR="$FIX"
ENG="$ROOT/score/classify-pda.sh"
C="$FIX/lar"; mkdir -p "$C/var" "$C/enunciados"
NOW=$(date +%s); T0=$(( NOW - 7200 ))
{ printf 'CONTEST_ID=lar\nCONTEST_MODULES=sedes,maquinas,baloes,coortes,inscricoes\nCONTEST_TYPE=icpc\nCONTEST_NAME=LAR\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$T0" "$(( NOW + 3600 ))"
  printf 'PROBS=( x col#p1 P1 A col#p1 x col#p2 P2 B col#p2 x col#p3 P3 C col#p3 x col#p4 P4 D col#p4 x col#p5 P5 E col#p5 )\n'
} > "$C/conf"
F3='teammxmx03|teambrbr07|teammxmx04|teamsocl02'; F2='teambrbr08'; F1='teamsoar03'
jq -n --arg f3 "^($F3)$" --arg f2 "^($F2)$" --arg f1 "^($F1)$" '[
  {name:"LATAM", regex:"^team"},
  {name:"Times femininos", regex:"^team", view:true, subregions:[
    {name:"3 competidoras", regex:$f3, view:true}, {name:"2 competidoras", regex:$f2, view:true},
    {name:"1 competidora", regex:$f1, view:true}]}]' > "$C/regions.json"
mkteam(){ # <login> <sigla> <minutos csv | ""> — 1 AC por problema nos minutos dados
  local login="$1" univ="$2" mins="$3"
  mkdir -p "$C/users/$login"
  jq -cn --arg l "$login" --arg u "$univ" '{login:$l, fullname:("Time " + $l), password:"x", team:{univ_short:$u, univ_full:("Univ " + $u), flag:"", region:""}}' \
    > "$C/users/$login/account.json"
  : > "$C/users/$login/history"
  local i=0 m se
  for m in ${mins//,/ }; do i=$((i+1)); se=$(( T0 + m*60 ))
    printf '%s:col#p%d:C:Accepted:%s:id%s%d\n' "$se" "$i" "$se" "$login" "$i" >> "$C/users/$login/history"; done
}
#      login        sigla    minutos            posição · total/pen
mkteam teambrbr01 USP     "1,1,2,3,3"        # 1  5/10
mkteam teambrbr02 USP     "2,3,4,5,6"        # 2  5/20
mkteam teambrbr03 USP     "4,5,6,7,8"        # 3  5/30  (3º da USP: fora do P1)
mkteam teammxmx01 UNAM    "6,7,8,9,10"       # 4  5/40
mkteam teambrbr04 UNICAMP "1,2,3,4"          # 5  4/10
mkteam teamsoar01 UBA     "3,4,6,7"          # 6  4/20
mkteam teambrbr05 UFMG    "6,7,8,9"          # 7  4/30
mkteam teamsoar02 UTN     "2,3,5"            # 8  3/10  (P3: escola não-sede)
mkteam teammxmx02 ITESM   "5,7,8"            # 9  3/20  (sede)
mkteam teamsocl01 UCHILE  "9,10,11"          # 10 3/30  (P2)
mkteam teamnove01 USB     "12,13,15"         # 11 3/40  (P2)
mkteam teamnoco01 UNAL    "4,6"              # 12 2/10
mkteam teamcbcu01 UH      "9,11"             # 13 2/20
mkteam teambrbr06 UFPE    "14,16"            # 14 2/30  (P4 br)
mkteam teammxmx03 IPN     "19,21"            # 15 2/40  ♀3 (feminina país-sede)
mkteam teambrbr07 USP     "10"               # 16 1/10  ♀3 (feminina LATAM: 3º time da USP)
mkteam teammxmx04 ITESM   "20"               # 17 1/20  ♀3 (feminina da sede)
mkteam teambrbr08 UFRJ    "30"               # 18 1/30  ♀2
mkteam teamsoar03 UBA     "40"               # 19 1/40  ♀1
mkteam teamsocl02 UCHILE  "50"               # 20 1/50  ♀3 (feminina da região so)
mkteam teambrbr09 UNB     "60"               # 21 1/60
mkteam teambrbr10 UFSC    "70"               # 22 1/70
mkteam teammxmx05 UANL    "80"               # 23 1/80
mkteam teamcacr01 TEC     ""                 # 0 resolvidos (país zero_solved)
mkteam teammxmx06 ITESM   ""                 # 0 resolvidos (sede extra)
( cd "$ROOT/score" && CONTESTSDIR="$FIX" bash build.sh lar >/dev/null 2>&1 )
[[ -s "$C/var/placar.txt" ]] || { echo "build.sh não gerou placar"; exit 1; }

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
bad(){ FAIL=$((FAIL+1)); echo "FALHOU: $*" >&2; }
eqk(){ [[ "$1" == "$2" ]] && ok || bad "$3 (veio '$1', esperado '$2')"; }
via(){ jq -r --arg l "$1" '[.classified[] | select(.login == $l) | .via] | join(",")' "$2"; }

# config de teste: a semente oficial com N=12, a ITESM como sede, cotas [2,1] e as faixas da lista de espera
jq '.N = 12 | .host_schools = ["mx:ITESM"]
  | .edition_blocks |= map(if .type == "country_participation" then .quotas = [2, 1] else . end)
  | .waitlist.tiers = [{id:"mty", schools:["mx:ITESM"]}, {id:"mx", countries:["mx"]}]' \
  "$ROOT/score/classify-seeds/latam-pda-2027.json" > "$FIX/cfg.json"
run(){ bash "$ENG" lar "$1" "$2" 2>"$FIX/err"; }
O="$FIX/o.json"; run "$FIX/cfg.json" "$O" || { cat "$FIX/err"; echo "motor falhou"; exit 1; }

echo "== passos padrão =="
eqk "$(jq -r '[.classified[] | select(.via=="p1") | .login] | join(",")' "$O")" "teambrbr01,teambrbr02,teammxmx01,teambrbr04,teamsoar01,teambrbr05" "P1: N/2 = 6, o 3º da USP pula"
eqk "$(jq -r '[.classified[] | select(.via=="p2") | .login] | join(",")' "$O")" "teamsocl01,teamnove01" "P2: teto min(3, X=5) − 1 = 2"
eqk "$(jq -r '.countries | "\(.participating_without_team) \(.cap) \(.zero_solved | join(","))"' "$O")" "5 2 cr" "P2: X, teto e país só com 0 resolvidos"
eqk "$(via teamsoar02 "$O")" "p3" "P3: nenhuma escola-sede com time ⇒ o melhor de escola SEM time (UTN, não-sede)"
eqk "$(jq -r '.host.condition' "$O")" "true" "P3: condição"
eqk "$(jq -r '.geo | "\(.schools_latam) \(.remaining) \(.allocated_after) \(.overflow)"' "$O")" "18 3 12 0" "P4: 18 escolas, 3 vagas restantes"
eqk "$(jq -r '[.geo.regions[] | "\(.code)=\(.nslots)+\(.extra)"] | join(" ")' "$O")" "br=1+0 cb=0+0 ca=0+0 mx=0+1 no=0+0 so=0+1" "P4: inteiros + frações (mx .667, so .5)"
eqk "$(jq -r '.fractions_out | to_entries | map("\(.key)=\(.value * 1000 | round)") | join(" ")' "$O")" "br=167 cb=167 ca=167 no=333" "P4: frações carregadas p/ o ano seguinte"
eqk "$(via teambrbr06 "$O"),$(via teammxmx02 "$O")" "p4,p4" "P4: br → UFPE, mx → ITESM"
eqk "$(jq -r '[.warnings[] | select(.code=="geo_unfilled") | .data.region] | join(",")' "$O")" "so" "P4: região so sem escola elegível ⇒ aviso, vaga sem uso"
eqk "$(via teammxmx03 "$O"),$(via teambrbr07 "$O")" "fem-host-country,fem-latam" "femininas padrão: país-sede, depois LATAM (3º time da USP: sem regra geral)"
echo "== blocos da edição =="
eqk "$(jq -r '[.classified[] | select(.via=="pend") | .login] | join(",")' "$O")" "ext:acxioma-uclv,ext:lugia-usb" "pendentes (ext:)"
eqk "$(via teammxmx04 "$O")" "fem-host-school" "feminina da instituição-sede"
eqk "$(jq -r '[.classified[] | select(.via=="fem-region") | .login] | join(",")' "$O")" "teamsocl02" "feminina por região (só a so tem)"
eqk "$(via teambrbr08 "$O"),$(via teamsoar03 "$O")" "fem2,fem1" "≥2 e ≥1 competidoras"
eqk "$(jq -r '[.classified[] | select(.via=="country-part") | .login] | join(",")' "$O")" "teambrbr09,teambrbr10,teammxmx05" "participação: br (2), mx (1), 1 por instituição"
eqk "$(jq -r '.country_participation["country-part"] | "\(.source) " + ([.ranking[0:2][] | "\(.country):\(.teams)"] | join(","))' "$O")" "contest br:10,mx:6" "participação: tabela vazia ⇒ contagens do contest"
eqk "$(jq -r '[.warnings[] | select(.code=="cycle_table_empty")] | length' "$O")" "1" "aviso cycle_table_empty"
eqk "$(via teammxmx06 "$O")" "host-extra" "sede extra sem a regra geral (ITESM já tinha 2)"
eqk "$(jq -r '.reserve.slots' "$O")" "6" "reserva reportada"
eqk "$(jq -r '.total' "$O")" "23" "total (6 + 2 + 1 + 2 + 2 femininas + 2 pendentes + 1 + 1 + 1 + 1 + 3 + 1)"
eqk "$(jq -r '[.classified[] | select(.via=="pend")][0] | "\(.place // "null") \(.detail // "")|\(.univ)"' "$O")" "null |Universidad Central \"Martha Abreu\" de Las Villas" "pendente sem posição, escola no campo univ"
eqk "$(jq -r '.unused["fem-region"]' "$O")" "5" "vagas não usadas por bloco"
eqk "$(jq -r '.labels["fem2"].es' "$O")" "Dos o más competidoras" "rótulos dos blocos (es)"
eqk "$(jq -r '.via_order | join(",")' "$O")" "p1,p2,p3,p4,fem-host-country,fem-latam,pend,fem-host-school,fem-region,fem2,fem1,country-part,host-extra" "ordem das vias (sem a reserva)"

echo "== variantes =="
jq '.countries.cap = "min_of_x_minus_1"' "$FIX/cfg.json" > "$FIX/c2.json"; run "$FIX/c2.json" "$FIX/o2.json"
eqk "$(jq -r '[.classified[] | select(.via=="p2") | .login] | join(",")' "$FIX/o2.json")" "teamsocl01,teamnove01,teamnoco01" "P2: min(N/4, X − 1) = 3"
jq '.fractions_prev = {cb:0.5, ca:0.5}' "$FIX/cfg.json" > "$FIX/c3.json"; run "$FIX/c3.json" "$FIX/o3.json"
eqk "$(jq -r '"\(.geo.allocated_after) \(.geo.overflow)"' "$FIX/o3.json")" "13 1" "P4: empate triplo (mx, cb, ca) na última vaga ESTOURA N"
eqk "$(jq -r '[.warnings[] | select(.code=="geo_tie_overflow") | .data.overflow] | join(",")' "$FIX/o3.json")" "1" "aviso geo_tie_overflow"
jq '.host_schools = []' "$FIX/cfg.json" > "$FIX/c4.json"; run "$FIX/c4.json" "$FIX/o4.json"
eqk "$(jq -r '"\(.host.condition) \([.classified[] | select(.via=="p3")] | length) \([.warnings[] | select(.code=="host_schools_empty")] | length)"' "$FIX/o4.json")" "null 0 3" "sem host_schools: P3 pulado com aviso"
jq '(.edition_blocks[] | select(.type == "country_participation")) |= (.cycle_teams = {ar:50, cl:50, br:10} | .cycle_institutions = {ar:10, cl:12})' \
  "$FIX/cfg.json" > "$FIX/c5.json"; run "$FIX/c5.json" "$FIX/o5.json"
eqk "$(jq -r '.country_participation["country-part"] | .source + " " + ([.ranking[] | "\(.country):\(.quota)"] | join(","))' "$FIX/o5.json")" "config cl:2,ar:1,br:0" "tabela do RCD: desempate por instituições"
eqk "$(jq -r '[.warnings[] | select(.code=="country_quota_unfilled") | .data.country] | join(",")' "$FIX/o5.json")" "cl,ar" "cota sem instituição livre ⇒ aviso"
jq '(.edition_blocks[] | select(.type == "country_participation")) |= (.cycle_teams = {ar:50, cl:50} | .cycle_institutions = {ar:10, cl:10})' \
  "$FIX/cfg.json" > "$FIX/c6.json"; run "$FIX/c6.json" "$FIX/o6.json"
eqk "$(jq -r '[.warnings[] | select(.code=="cycle_tie") | .data.countries | join("=")] | join(",")' "$FIX/o6.json")" "ar=cl" "empate em times e instituições ⇒ cycle_tie"

echo "== lista de espera =="
jq '.edition_blocks = []' "$FIX/cfg.json" > "$FIX/c7.json"; run "$FIX/c7.json" "$FIX/o7.json"
eqk "$(jq -r '[.waitlist[] | "\(.tier):\(.login)"] | join(",")' "$FIX/o7.json")" "mx:teammxmx05" "com a regra geral: ITESM já tem time; UANL"
jq '.waitlist.general_rule = false' "$FIX/c7.json" > "$FIX/c8.json"; run "$FIX/c8.json" "$FIX/o8.json"
eqk "$(jq -r '[.waitlist[] | "\(.tier):\(.login)"] | join(",")' "$FIX/o8.json")" "mty:teammxmx04,mty:teammxmx06,mx:teammxmx05" "sem a regra geral: faixa Monterrey antes do resto do México"
# --waitlist contra o ESTADO do estágio (o handler o monta): o mx05 já subiu da lista; o mx04 desistiu (skip)
jq --slurpfile o "$FIX/o8.json" '. + {waitlist_state:{promoted:([$o[0].classified[] | {key:.login}] + [{key:"teammxmx05"}]), skip:["teammxmx04"]}}' \
  "$FIX/c8.json" > "$FIX/c9.json"
bash "$ENG" --waitlist lar "$FIX/c9.json" "$FIX/o9.json" 2>"$FIX/err"
eqk "$(jq -r '[.waitlist[] | .login] | join(",")' "$FIX/o9.json")" "teammxmx06" "--waitlist: promovido some, quem desistiu fica de fora"

echo "== overrides e dados =="
jq '. + {preassigned:[{login:"teamsocl01", via:"manual"}]}' "$FIX/cfg.json" > "$FIX/p1.json"; run "$FIX/p1.json" "$FIX/op.json"
eqk "$(jq -r '[.classified[] | select(.via=="p2") | .login] | join(",")' "$FIX/op.json")" "teamnove01,teamnoco01" "preassigned conta como promovido (CL já tem time; X=4, teto 2)"
eqk "$(jq -r '[.classified[] | select(.login=="teamsocl01")] | length' "$FIX/op.json"),$(jq -r '.pre[0].login' "$FIX/op.json")" "0,teamsocl01" "preassigned fora do cálculo, em pre[]"
jq '. + {exclude:[{login:"teambrbr01", reason:"x"}]}' "$FIX/cfg.json" > "$FIX/x1.json"; run "$FIX/x1.json" "$FIX/ox.json"
eqk "$(jq -r '[.classified[] | select(.via=="p1") | .login] | join(",")' "$FIX/ox.json")" "teambrbr02,teambrbr03,teammxmx01,teambrbr04,teamsoar01,teambrbr05" "exclude: o 3º da USP entra no P1"
mkteam teamzzxx01 ZZ "1"
( cd "$ROOT/score" && CONTESTSDIR="$FIX" bash build.sh lar >/dev/null 2>&1 )
run "$FIX/cfg.json" "$FIX/oz.json"; rc=$?
eqk "$rc" "3" "região fora da tabela ⇒ RECUSA (rc 3)"
grep -q 'teamzzxx01 (região zz)' "$FIX/err" && ok || bad "a recusa diz qual login e qual código"
jq '. + {exclude:["teamzzxx01"]}' "$FIX/cfg.json" > "$FIX/x2.json"; run "$FIX/x2.json" "$FIX/ox2.json"
eqk "$?:$(jq -r '.total' "$FIX/ox2.json")" "0:23" "excluir o login resolve a recusa"
cp "$FIX/x2.json" "$FIX/cfg.json"

echo "== --check e --geo =="
jq '.N = 10' "$FIX/cfg.json" > "$FIX/k1.json"
bash "$ENG" --check "$FIX/k1.json" 2>"$FIX/k1.err"; eqk "$?" "2" "--check: N não múltiplo de 4"
grep -q 'múltiplo de 4' "$FIX/k1.err" && ok || bad "--check diz o erro"
jq '.edition_blocks[0].id = "p2"' "$FIX/cfg.json" > "$FIX/k2.json"
bash "$ENG" --check "$FIX/k2.json" 2>"$FIX/k2.err"; grep -q 'reservado' "$FIX/k2.err" && ok || bad "--check: id de bloco reservado"
jq '.login_regex = "^team(["' "$FIX/cfg.json" > "$FIX/k3.json"
bash "$ENG" --check "$FIX/k3.json" 2>"$FIX/k3.err"; grep -q 'não compila' "$FIX/k3.err" && ok || bad "--check: regex que não compila"
bash "$ENG" --check "$ROOT/score/classify-seeds/latam-pda-2027.json" && ok || bad "a semente oficial passa no --check"
# exatidão: 9 × 21 / 27 = 7 exatos (no ponto flutuante do PDF, 9 / (27/21) = 6,999… e o trunc dá 6)
echo '{"N":21,"allocated":0,"regions":["a","b"],"schools":{"a":9,"b":18}}' > "$FIX/g1.json"
eqk "$(bash "$ENG" --geo "$FIX/g1.json" | jq -c '[.regions.a.nslots, .regions.b.nslots, .regions.a.fraction_out, .allocated]')" "[7,14,0,21]" "--geo: inteiros exatos"
echo '{"N":40,"allocated":24,"regions":["br","cb","ca","mx","no","so"],"schools":{"br":300,"cb":20,"ca":40,"mx":250,"no":60,"so":80},"fractions_prev":{"cb":0.5}}' > "$FIX/g2.json"
eqk "$(bash "$ENG" --geo "$FIX/g2.json" | jq -c '[.regions[] | .slots]')" "[6,1,1,5,1,2]" "--geo: frações + herança (cb .5)"

echo "== empate na fronteira e placar COM coluna guest =="
C_SAVE="$C"; C="$FIX/lar2"; mkdir -p "$C/var" "$C/enunciados"
sed 's/^CONTEST_ID=lar$/CONTEST_ID=lar2/' "$C_SAVE/conf" > "$C/conf"
cp "$C_SAVE/regions.json" "$C/regions.json"
jq -cn '{version:1, results_released:true, cohorts:[
  {id:"oficial", name:"Oficiais", regex:"", public:true, unranked:false, ranking:false, default:true},
  {id:"conv", name:"Convidados", regex:"^cclx", public:false, unranked:true, ranking:false, default:false, sees:["oficial","conv"]}]}' > "$C/cohorts.json"
mkteam cclxx01     GUEST "1,1,1,1,1"     # convidado: no placar, fora do cálculo
mkteam teambrbr01  USP   "1,2,3"
mkteam teamsoar01  UBA   "2,3"           # empatado com o próximo (mesmos minutos)
mkteam teammxmx01  UNAM  "2,3"
mkteam teamsocl01  UCHILE "9"
( cd "$ROOT/score" && CONTESTSDIR="$FIX" bash build.sh lar2 >/dev/null 2>&1 )
B2="$C/var/placar.txt"; [[ -s "$C/var/placar-full.txt" ]] && B2="$C/var/placar-full.txt"
grep -q ':guest' "$B2" && ok || bad "fixture sem coluna guest (devia ter)"
jq '.N = 4 | .edition_blocks = [] | .female = []' "$FIX/cfg.json" > "$FIX/t1.json"
bash "$ENG" lar2 "$FIX/t1.json" "$FIX/ot.json" 2>"$FIX/err" || { cat "$FIX/err"; bad "motor falhou (lar2)"; }
# os dois empatados (mesmos minutos) dividem a 2ª posição: entra um, o outro fica — e o motor avisa
eqk "$(jq -r '[.classified[] | select(.via=="p1") | .login][0]' "$FIX/ot.json")" "teambrbr01" "P1 (N/2 = 2) sem o convidado"
eqk "$(jq -r '[.warnings[] | select(.code=="tie_boundary") | "\(.data.block):\(.data.place):" + ([.data.last, .data.next] | sort | join("+"))] | join(",")' "$FIX/ot.json")" "p1:2:teammxmx01+teamsoar01" "empate na fronteira do P1 = aviso"
C="$C_SAVE"

echo "== handler: estágio pda, lista de espera, reserva, trava =="
ROUTER="$ROOT/api/v1/router.sh"
mkdir -p "$C/users/lar.admin"; jq -cn '{login:"lar.admin", fullname:"Admin", password:"x"}' > "$C/users/lar.admin/account.json"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' lar lar.admin Admin "$NOW" > "$SESS/t-adm"
calla(){ OUT="$(PATH_INFO=/contest/admin/classify REQUEST_METHOD="$1" QUERY_STRING="contest=lar" HTTP_AUTHORIZATION="Bearer t-adm" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${2:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
hk(){ jq -e "$1" <<<"$BODY" >/dev/null 2>&1 && ok || bad "$2  [${BODY:0:300}]"; }
stj(){ jq -r --arg s "$1" "first(.stages[] | select(.id == \$s)) | $2" "$C/classification.json"; }
CFGJ="$(cat "$FIX/cfg.json")"
calla GET
hk '(.algorithms | map(.id) | index("latam-pda")) != null and (.algorithms[1].seed.N == 40) and (.algorithms[1].stage == "pda")' "GET: catálogo com a semente oficial"
calla POST "$(jq -cn --argjson c "$CFGJ" '{action:"preview", config:$c}')"
hk '.stage == "pda" and (.relation | length) == 23 and (.preview.geo.schools_latam == 18)' "preview: estágio padrão pda"
calla POST "$(jq -cn --argjson c "$CFGJ" '{action:"apply", config:$c}')"
hk '.applied == true and .stage == "pda"' "apply no estágio pda"
eqk "$(stj pda '"\(.chip)|\(.name)|\(.next_stage)|\(.labels.p4.pt)|\(.labels.fem2.pt)|\(.teams | length)"')" "PDA|Campeonato Latino-Americano 2027|mundial|Passo 4 — representação geográfica|Duas ou mais competidoras|23" "estágio: chip, nome, próximo, rótulos (catálogo + blocos)"
calla POST '{"action":"apply","stage":"pda","config":{"algorithm":"sbc-fase1","r1":2}}'
hk '.error.code == "stage_algorithm_mismatch" and .error.stage_algorithm == "latam-pda"' "estágio de outro motor = 409"
calla POST '{"action":"withdraw","stage":"pda","login":"teamsoar02","reason":"desistiu"}'
hk '.total == 22' "withdraw no pda"
calla POST '{"action":"withdraw","stage":"pda","ext":"lugia-usb","reason":"não virá"}'
eqk "$(stj pda '(.teams | has("ext:lugia-usb")) | tostring')" "false" "withdraw de time externo (ext:)"
calla POST '{"action":"exclude","stage":"pda","ext":"acxioma-uclv","reason":"x"}'
hk '.error.code == "login_invalid"' "exclude de time externo = 400 (não está no placar)"
calla POST '{"action":"promote_next","stage":"pda"}'
hk '.error.code == "reason_required"' "promote_next sem motivo = 422"
calla POST '{"action":"promote_next","stage":"pda","reason":"vaga do UTN"}'
hk '.error.code == "waitlist_empty"' "lista vazia (todo o México já classificado) = 409"
calla POST '{"action":"promote_next","stage":"final-br","reason":"x"}'
hk '.error.code == "no_stage"' "promote_next em estágio inexistente = 404"
# estágio pda2: sem blocos da edição ⇒ a lista tem o UANL
calla POST "$(jq -cn --argjson c "$(jq -c '.edition_blocks = []' <<<"$CFGJ")" '{action:"apply", stage:"pda2", config:$c}')"
calla POST '{"action":"withdraw","stage":"pda2","login":"teambrbr06","reason":"desistiu"}'
calla POST '{"action":"promote_next","stage":"pda2","reason":"vaga do UFPE"}'
eqk "$(stj pda2 '.teams.teammxmx05.via'),$(stj pda2 '[.overrides[] | select(.op=="add")][0].reason')" "lista,vaga do UFPE" "promote_next: o 1º da lista entra via lista, com o motivo"
calla POST '{"action":"promote_next","stage":"pda2","reason":"outra"}'
hk '.error.code == "waitlist_empty"' "depois dele a lista esvazia (ITESM já tem time; regra geral)"
# recusa resolvida pelo override exclude (e não na config): apply e promote_next usam o mesmo cl_engine_cfg
CFGX="$(jq -c '.edition_blocks = [] | del(.exclude)' <<<"$CFGJ")"
calla POST "$(jq -cn --argjson c "$CFGX" '{action:"apply", stage:"pda4", config:$c}')"
hk '.error.code == "engine_refused" and (.error.message | test("teamzzxx01"))' "login fora do padrão = 422 engine_refused, dizendo qual"
calla POST '{"action":"exclude","stage":"pda4","login":"teamzzxx01","reason":"conta de teste"}'
calla POST "$(jq -cn --argjson c "$CFGX" '{action:"apply", stage:"pda4", config:$c}')"
hk '.applied == true' "com o override exclude, o apply passa"
calla POST '{"action":"withdraw","stage":"pda4","login":"teambrbr06","reason":"desistiu"}'
calla POST '{"action":"promote_next","stage":"pda4","reason":"vaga do UFPE"}'
eqk "$(stj pda4 '.teams.teammxmx05.via // "-"')" "lista" "promote_next respeita o exclude do override (sem recusa)"
# reserva: no máximo as vagas que o motor reportou
calla POST "$(jq -cn --argjson c "$(jq -c '.edition_blocks = [{id:"res", type:"reserve", slots:1}]' <<<"$CFGJ")" '{action:"apply", stage:"pda3", config:$c}')"
calla POST '{"action":"add","stage":"pda3","login":"teambrbr03","via":"reserva","reason":"novo país"}'
hk '.override == "ov-1"' "reserva 1/1"
calla POST '{"action":"add","stage":"pda3","login":"teamnoco01","via":"reserva","reason":"outro"}'
hk '.error.code == "reserve_full"' "reserva cheia = 409"
eqk "$(stj pda3 '.teams.teambrbr03.via')" "reserva" "time da reserva na lista"
# trava: 8 promoções em paralelo num estágio só-manual — 8 overrides, ids únicos, arquivo íntegro
for l in teambrbr03 teamnoco01 teamcbcu01 teamcacr01 teambrbr09 teambrbr10 teammxmx05 teammxmx06; do
  ( PATH_INFO=/contest/admin/classify REQUEST_METHOD=POST QUERY_STRING="contest=lar" HTTP_AUTHORIZATION="Bearer t-adm" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"{\"action\":\"add\",\"stage\":\"par\",\"login\":\"$l\",\"reason\":\"comitê\"}" >/dev/null 2>&1 ) &
done
wait
eqk "$(stj par '"\(.overrides | length) \([.overrides[].id] | unique | length) \(.teams | length)"')" "8 8 8" "8 adds em paralelo sob a trava"

echo "smoke-classify-pda: PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
