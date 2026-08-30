#!/bin/bash
# Integração NUTELLABOOT (/contest/nutella): config da chave (600, write-only), coleta
# contra um MOCK (nutella-mock.py, que registra POST/PUT), panorama hierárquico com
# rollups/ranks, ESCOPO por sede do .cstaff, e comandos (catálogo ao vivo, gates por
# papel, fail-closed sem escopo, auditoria).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; MOCKD="$(mktemp -d)"
MOCKPID=""
cleanup(){ [[ -n "$MOCKPID" ]] && kill "$MOCKPID" 2>/dev/null; rm -rf "$FIX" "$SESS" "$MOCKD"; }
trap cleanup EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"

C="$FIX/nt"; mkdir -p "$C/var" "$C/print-requests"
NOW=$(date +%s); T0=$(( NOW - 7200 )); TE=$(( NOW - 600 ))
{ printf 'CONTEST_ID=nt\nCONTEST_TYPE=icpc\nCONTEST_NAME=Prova\\ NB\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$T0" "$TE"
  printf "PROBS=( x col#pa Alfa A col#pa )\n"; } > "$C/conf"
fx_user "$C" nt.admin p "Admin"
fx_user "$C" sedea.cstaff p "Chefe Sede A"
fx_user "$C" solto.staff p "Staff sem escopo"
fx_user "$C" alice a "Time Alice"
fx_user "$C" bob b "Time Bob"
fx_user "$C" carol c "Time Carol"
fx_team(){ jq -c --arg r "$2" '. + {team:{region:$r, flag:"br"}}' \
  "$C/users/$1/account.json" > "$C/users/$1/account.json.n" && mv "$C/users/$1/account.json.n" "$C/users/$1/account.json"; }
fx_team alice "Sede A"; fx_team bob "Sede A"; fx_team carol "Sede B"
jq -n '{"sedea.cstaff":["region:Sede A"]}' > "$C/print-requests/staff-filters.json"
jq -n '[{name:"País X", regex:"^(alice|bob|carol)$", subregions:[
         {name:"Sede A", regex:"^(alice|bob)$"}, {name:"Sede B", regex:"^carol$"}]}]' > "$C/regions.json"
for u in adm:nt.admin cst:sedea.cstaff stf:solto.staff usr:alice; do
  printf 'CONTEST=nt\nLOGIN=%s\nLOGINAT=1\n' "${u#*:}" > "$SESS/${u%%:*}"
done

# --- fixtures do mock (shapes REAIS do nutellaboot, encolhidos) --------------------------
M1=aa-bb-01; M2=aa-bb-02; M3=aa-bb-03
jq -n '{images:[{id:"26tsca", fullname:"Cidade A", model:"m"}, {id:"26tscb", fullname:"Cidade B", model:"m"},
               {id:"26zzzz", fullname:"Outro Evento", model:"m"}]}' > "$MOCKD/images.json"
jq -n '{roster:[{user_id:"alice", name:"Time Alice", country:"BRA"}, {user_id:"bob", name:"Time Bob", country:"BRA"}]}' > "$MOCKD/roster.26tsca.json"
jq -n '{roster:[{user_id:"carol", name:"Time Carol", country:"BRA"}]}' > "$MOCKD/roster.26tscb.json"
jq -n '{roster:[{user_id:"ninguem001", name:"X", country:"ARG"}]}' > "$MOCKD/roster.26zzzz.json"
mkmach(){ jq -n --arg mac "$1" --argjson seen "$2" --arg cpu "$3" --argjson cores "$4" --argjson mem "$5" --argjson ed "$6" \
  '{mac:$mac, first_seen:($seen-3600), last_seen:$seen, online:false,
    status:{hwinfo:{processor:$cpu, cores:$cores, memtotal_mb:$mem},
            sysresources:{mem_pct:20, loadavg:[0.5,0.4,0.3]},
            sysdisk:{home_pct:10, root_free_mb:3000},
            operations:{firewall:true, screen_lock:false,
                        editors:[], editors_time:$ed}},
    binding:null, lock:{locked:false}, alerts:[]}'; }
jq -n --argjson a "$(mkmach $M1 "$TE" "Intel i5" 4 7812 '{"code":120,"total":150}')" \
      --argjson b "$(mkmach $M2 "$TE" "Intel i7" 8 15624 '{"vim":30,"code":10,"total":45}')" \
      '{machines:[$a, $b]}' > "$MOCKD/machines.26tsca.json"
jq -n --argjson a "$(mkmach $M3 "$TE" "AMD Ryzen" 16 31000 '{"gedit":5,"total":5}')" \
      '{machines:[$a]}' > "$MOCKD/machines.26tscb.json"
jq -n '{machines:[]}' > "$MOCKD/machines.26zzzz.json"
mksamp(){ jq -n --arg mac "$1" --argjson t0 "$2" \
  '{mac:$mac, points:[{t:$t0, mem:15, ld:0.5, sw:0, hd:10, ed:[], fw:1},
                      {t:($t0+600), mem:30, ld:1.5, sw:0, hd:10, ed:["code"], fw:1},
                      {t:($t0+1200), mem:25, ld:1.0, sw:0, hd:10, ed:["code"], fw:1}], truncated:false}'; }
mksamp "$M1" "$T0" > "$MOCKD/samples.26tsca.$M1.json"
mksamp "$M2" "$T0" > "$MOCKD/samples.26tsca.$M2.json"
mksamp "$M3" "$T0" > "$MOCKD/samples.26tscb.$M3.json"
jq -n '{allowed:["mlreboot","precontest","cleanhomenow"], blocked:{}}' > "$MOCKD/commands.json"

# --- sobe o mock -------------------------------------------------------------------------
export NB_MOCK_KEY="nb3a_mocktest123"
python3 "$(dirname "$(readlink -f "$0")")/nutella-mock.py" "$MOCKD" "$MOCKD/port" &
MOCKPID=$!
for _ in $(seq 50); do [[ -s "$MOCKD/port" ]] && break; sleep 0.1; done
[[ -s "$MOCKD/port" ]] || { echo "mock não subiu"; exit 1; }
MURL="http://127.0.0.1:$(cat "$MOCKD/port")"

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="contest=nt" HTTP_AUTHORIZATION="Bearer ${4:-adm}" \
  CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:220}"; ((fail++)); fi; }
J(){ printf '%s' "$BODY" | jq -r "$1" 2>/dev/null; }

echo "== gates básicos =="
call /contest/nutella GET '' usr
ck "competidor → 403"                '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/nutella GET ''
ck "admin sem config: configured=false, data=null" '[[ "$(J .configured)" == false && "$(J .data)" == null ]]'

echo "== config (chave write-only, 600) =="
call /contest/nutella POST '{"action":"config","key":"nb3a_mocktest123","url":"'"$MURL"'"}'
ck "config salva"                    '[[ "$(J .saved)" == true && "$(J .configured)" == true ]]'
ck "chave em secrets/ com 600"       '[[ "$(stat -c %a "$C/secrets/nutellaboot.key")" == 600 ]]'
ck "chave NÃO volta no GET"          'call /contest/nutella GET ""; [[ "$BODY" != *mocktest* ]]'
ck "URL gravada no conf"             'grep -q "^NUTELLABOOT_URL=" "$C/conf"'
call /contest/nutella POST '{"action":"config","key":"errada"}' cst
ck "config por não-admin → 403"      '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/nutella POST '{"action":"config","key":"formato-ruim"}'
ck "chave fora do formato → 422"     '[[ "$OUT" == *"Status: 422"* ]]'

echo "== coleta (gen direto contra o mock — determinístico) =="
CONTESTSDIR="$FIX" bash "$ROOT/score/nutella-gen.sh" nt >/dev/null 2>&1
ck "cache gerado"                    '[[ -s "$C/var/nutella.cache.json" ]]'
ck "status ok:true"                  '[[ "$(jq -r .ok "$C/var/nutella.status.json")" == true ]]'
CJ(){ jq -r "$1" "$C/var/nutella.cache.json" 2>/dev/null; }
ck "3 máquinas no global (26zzzz FORA — roster não casa)" '[[ "$(CJ .global.machines_total)" == 3 ]]'
ck "2 sedes, nome do STORE (Sede A/Sede B)" '[[ "$(CJ ".sedes|length")" == 2 && "$(CJ ".sedes[0].name")" == "Sede A" ]]'
ck "by_node tem País X agregando as duas"   '[[ "$(CJ ".by_node[\"País X\"].machines_total")" == 3 ]]'
ck "editores agregados (code=130 na Sede A)" '[[ "$(CJ ".sedes[]|select(.name==\"Sede A\")|.editors.code")" == 130 ]]'
ck "buckets de RAM (8+16 na Sede A)"  '[[ "$(CJ ".sedes[]|select(.name==\"Sede A\")|.ram_buckets|keys|sort|join(\",\")")" == "16,8" ]]'
ck "série por sede com janelas"       '[[ "$(CJ ".sedes[]|select(.name==\"Sede A\")|.series|length")" -ge 2 ]]'
ck "série: editores por janela"       '[[ "$(CJ ".sedes[]|select(.name==\"Sede A\")|[.series[].ed.code // 0]|max")" == 2 ]]'
ck "ranks geral e do país"            '[[ "$(CJ ".sedes[]|select(.name==\"Sede B\")|.ranks.geral.ram")" == 1 && "$(CJ ".sedes[]|select(.name==\"Sede B\")|.ranks.pais.n")" == 2 ]]'

echo "== GET com escopo =="
call /contest/nutella GET ''
ck "admin vê as 2 sedes"             '[[ "$(J ".data.sedes|length")" == 2 ]]'
call /contest/nutella GET '' cst
ck "cstaff vê SÓ a Sede A"           '[[ "$(J ".data.sedes|length")" == 1 && "$(J ".data.sedes[0].name")" == "Sede A" ]]'
ck "…mas o global segue inteiro"     '[[ "$(J .data.global.machines_total)" == 3 ]]'

echo "== action collect (contrato) =="
call /contest/nutella POST '{"action":"collect"}'
ck "collect dispara"                 '[[ "$(J .started)" == true ]]'
for _ in $(seq 100); do [[ "$(jq -r '.running' "$C/var/nutella.status.json" 2>/dev/null)" == false ]] && break; sleep 0.1; done
ck "coleta destacada terminou ok"    '[[ "$(jq -r .ok "$C/var/nutella.status.json")" == true ]]'

echo "== comandos =="
: > "$MOCKD/posts.log"
call /contest/nutella POST '{"action":"command","op":"mlreboot","image":"26tsca"}'
ck "admin comanda a sede → 200"      '[[ "$(J .sent)" == true ]]'
ck "mock recebeu POST {op} na imagem" 'grep -q "/api/v1/site-images/26tsca/commands" "$MOCKD/posts.log" && grep -q "mlreboot" "$MOCKD/posts.log"'
call /contest/nutella POST '{"action":"command","op":"hackop","image":"26tsca"}'
ck "op fora do catálogo → 422"       '[[ "$OUT" == *"Status: 422"* && "$OUT" == *op_not_allowed* ]]'
call /contest/nutella POST '{"action":"command","op":"mlreboot","image":"26tsca","mac":"'"$M1"'"}'
ck "comando numa MÁQUINA"            'grep -q "/machines/aa-bb-01/commands" "$MOCKD/posts.log"'
call /contest/nutella POST '{"action":"command","op":"mlreboot","image":"all"}'
ck "admin frota → POST /commands"    '[[ "$(J .sent)" == true ]] && grep -q "\"/api/v1/commands\"" "$MOCKD/posts.log"'
call /contest/nutella POST '{"action":"command","op":"mlreboot","image":"26tsca"}' cst
ck "cstaff na própria sede → 200"    '[[ "$(J .sent)" == true ]]'
call /contest/nutella POST '{"action":"command","op":"mlreboot","image":"26tscb"}' cst
ck "cstaff em sede ALHEIA → 403"     '[[ "$OUT" == *"Status: 403"* && "$OUT" == *site_forbidden* ]]'
call /contest/nutella POST '{"action":"command","op":"mlreboot","image":"all"}' cst
ck "cstaff frota → 403"              '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/nutella POST '{"action":"command","op":"mlreboot","image":"26tsca"}' stf
ck "staff SEM escopo → 403 (fail-closed)" '[[ "$OUT" == *"Status: 403"* && "$OUT" == *command_scope_required* ]]'
ck "comandos auditados"              'grep -q "nutella-command" "$C/var/admin-audit.log"'

echo "== push-roster =="
call /contest/nutella POST '{"action":"push-roster"}'
ck "sem force: roster povoado é PRESERVADO" '[[ "$(J .kept)" == 2 && "$(J .pushed)" == 0 ]]'
call /contest/nutella POST '{"action":"push-roster","force":true}'
ck "force: PUT do roster nas 2 imagens" '[[ "$(J .pushed)" == 2 ]] && grep -q "\"PUT\"" "$MOCKD/posts.log" && grep -q "Time Alice" "$MOCKD/posts.log"'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
