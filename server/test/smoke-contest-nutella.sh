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
# machine_id (32 hex) = o que o UA do navegador mlinux carrega — é o ELO máquina↔time.
# M1 e M2 têm o MESMO machine_id (imagem clonada, como Salvador/Goiânia na Maratona): só o
# par machine_id/boot_id separa as duas. M3 tem id próprio.
MID1=0123456789abcdef0123456789abcdef; MID2=$MID1; MID3=00112233445566778899aabbccddeeff
BOOT1=1111111111; BOOT2=2222222222; BOOT3=3333333333
jq -n '{images:[{id:"26tsca", fullname:"Cidade A", model:"m"}, {id:"26tscb", fullname:"Cidade B", model:"m"},
               {id:"26zzzz", fullname:"Outro Evento", model:"m"}]}' > "$MOCKD/images.json"
jq -n '{roster:[{user_id:"alice", name:"Time Alice", country:"BRA"}, {user_id:"bob", name:"Time Bob", country:"BRA"}]}' > "$MOCKD/roster.26tsca.json"
jq -n '{roster:[{user_id:"carol", name:"Time Carol", country:"BRA"}]}' > "$MOCKD/roster.26tscb.json"
jq -n '{roster:[{user_id:"ninguem001", name:"X", country:"ARG"}]}' > "$MOCKD/roster.26zzzz.json"
mkmach(){ jq -n --arg mac "$1" --argjson seen "$2" --arg cpu "$3" --argjson cores "$4" --argjson mem "$5" --argjson ed "$6" --arg mid "$7" --arg boot "$8" \
  '{mac:$mac, first_seen:($seen-3600), last_seen:$seen, online:false,
    status:{hwinfo:{processor:$cpu, cores:$cores, memtotal_mb:$mem, machine_id:$mid, boot_id:$boot, image:"26tsca"},
            sysresources:{mem_pct:20, loadavg:[0.5,0.4,0.3]},
            sysdisk:{home_pct:10, root_free_mb:3000},
            operations:{firewall:true, screen_lock:false,
                        editors:[], editors_time:$ed}},
    binding:null, lock:{locked:false}, alerts:[]}'; }
jq -n --argjson a "$(mkmach $M1 "$TE" "Intel(R) Core(TM) i5-8400 CPU @ 2.80GHz" 6 7812 '{"code":120,"total":150}' "$MID1" "$BOOT1")" \
      --argjson b "$(mkmach $M2 "$TE" "12th Gen Intel(R) Core(TM) i7-12700" 20 15624 '{"vim":30,"code":10,"total":45}' "$MID2" "$BOOT2")" \
      '{machines:[$a, $b]}' > "$MOCKD/machines.26tsca.json"
jq -n --argjson a "$(mkmach $M3 "$TE" "AMD Ryzen 5 PRO 4650GE with Radeon Graphics" 12 31000 '{"gedit":5,"total":5}' "$MID3" "$BOOT3")" \
      '{machines:[$a]}' > "$MOCKD/machines.26tscb.json"
jq -n '{machines:[]}' > "$MOCKD/machines.26zzzz.json"
# séries: 40 pontos a cada 120 s desde o INÍCIO da prova (cadência 2 min ⇒ 1 ponto = 2 min de editor).
#   M1: VS Code o tempo todo (80 min ⇒ usado), memória subindo, swap crescendo até 780 MB
#   M2: Vim nos 30 primeiros pontos (60 min ⇒ usado), depois VS Code (20 min ⇒ não conta) ⇒ perfil leve
#   M3: gedit só 6 pontos (12 min ⇒ máquina USADA, editor NÃO adotado) ⇒ perfil nenhum
mksamp(){ jq -n --arg mac "$1" --argjson t0 "$2" --arg kind "$3" \
  '{mac:$mac, truncated:false, points:[ range(0; 40) as $i
     | { t: ($t0 + $i * 120), ld: 0.5, hd: 10, fw: 1,
         mem: (if $kind == "code" then (30 + $i) else 40 end),
         sw: (if $kind == "code" then ($i * 20) else 0 end),
         ed: (if $kind == "code" then ["code"]
              elif $kind == "vim30" then (if $i < 30 then ["vim"] else ["code"] end)
              else (if $i < 6 then ["gedit"] else [] end) end) } ]}'; }
mksamp "$M1" "$T0" code   > "$MOCKD/samples.26tsca.$M1.json"
mksamp "$M2" "$T0" vim30  > "$MOCKD/samples.26tsca.$M2.json"
mksamp "$M3" "$T0" gedit6 > "$MOCKD/samples.26tscb.$M3.json"
# access.log do contest (epoch \t login \t ip \t ua_b64 [\t ator]) — o UA do mlinux liga o login à máquina.
# alice→M1 · bob→M2 (MESMO machine_id de M1; só o boot_id separa) · carol→M3 às 10h, ANTES da
# janela, e fica logada (sessão não expira: tem de valer) · nt.admin em M1 DEPOIS (papel: não
# pode roubar o elo) · alice com Firefox comum (ignorado) · dave nunca loga (ausente)
ua(){ printf 'Mozilla/5.0 (MLinux/26tsca/%s/%s) Gecko/20100101 Firefox/148.0' "$1" "$2" | base64 -w0; }
{ printf '%s\talice\t10.0.0.1\t%s\n'      "$((T0+600))"   "$(ua $MID1 $BOOT1)"
  printf '%s\tbob\t10.0.0.2\t%s\n'        "$((T0+100))"   "$(ua $MID2 $BOOT2)"
  printf '%s\tcarol\t10.0.0.3\t%s\tcarol\n' "$((T0-5000))" "$(ua $MID3 $BOOT3)"
  printf '%s\tnt.admin\t10.0.0.9\t%s\n'   "$((T0+700))"   "$(ua $MID1 $BOOT1)"
  printf '%s\talice\t10.0.0.1\t%s\n'      "$((T0+800))"   "$(printf 'Mozilla/5.0 (X11; Linux x86_64) Firefox/148.0' | base64 -w0)"
} > "$C/var/access.log"
fx_user "$C" dave d "Time Dave"; fx_team dave "Sede A"
jq -c '.roster += [{user_id:"dave", name:"Time Dave", country:"BRA"}]' "$MOCKD/roster.26tsca.json" > "$MOCKD/r.tmp" && mv "$MOCKD/r.tmp" "$MOCKD/roster.26tsca.json"
# placar completo (posição = ordem; convidado zz sem posição)
printf 'icpc s\ndesc:asc:flag:username:univ short:team name:univ full:P00:Total:Penalty:LastAC:guest\n' > "$C/var/placar-full.txt"
printf 'br:alice:U:Time Alice::1/600:1:10:10:\nbr:bob:U:Time Bob::1/900:1:15:15:\nbr:carol:U:Time Carol::2/-:0:0:0:\nbr:zz:U:Guest::1/300:1:5:5:1\n' >> "$C/var/placar-full.txt"
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
ck "faixas de RAM (8+16 na Sede A; 32 GB real cai em \"32\", não em \">32\")" '[[ "$(CJ ".sedes[]|select(.name==\"Sede A\")|.ram_bands|keys|sort|join(\",\")")" == "16,8" && "$(CJ ".global.ram_bands[\"32\"]")" == 1 && "$(CJ ".global.ram_bands[\">32\"] // 0")" == 0 ]]'
ck "série por sede com janelas"       '[[ "$(CJ ".sedes[]|select(.name==\"Sede A\")|.series|length")" -ge 2 ]]'
ck "série: editores por janela"       '[[ "$(CJ ".sedes[]|select(.name==\"Sede A\")|[.series[].ed.code // 0]|max")" == 2 ]]'
ck "ranks geral e do país"            '[[ "$(CJ ".sedes[]|select(.name==\"Sede B\")|.ranks.geral.ram")" == 1 && "$(CJ ".sedes[]|select(.name==\"Sede B\")|.ranks.pais.n")" == 2 ]]'

echo "== relatório 2.0: janela, elo máquina↔time, derivação na prova =="
ck "samples pedidos com since/until (a JANELA)" 'grep -q "samples?since=$((T0-3600))&until=" "$MOCKD/gets.log"'
ck "version 2 + contest{start,end}"   '[[ "$(CJ .version)" == 2 && "$(CJ .contest.start)" == "$T0" && "$(CJ .contest.end)" == "$TE" ]]'
ck "elo por UA: modo ua; 4 inscritos, 3 presentes, 3 vinculados = 100%" '[[ "$(CJ .link.mode)" == ua && "$(CJ ".link|[.teams,.present,.linked,.coverage]|join(\",\")")" == "4,3,3,100" ]]'
ck "pop global: 3 vistas, 3 usadas, 3 vinculadas, 3 de time, 4 inscritos, 3 presentes" '[[ "$(CJ ".global.pop|[.seen,.used,.linked,.chosen,.ranked,.tm,.teams,.present]|join(\",\")")" == "3,3,3,3,3,3,4,3" ]]'
ck "machine_id CLONADO: boot_id separa alice(M1) de bob(M2)" '[[ "$(CJ ".sedes[]|select(.name==\"Sede A\")|.machines[]|select(.mac==\"aa-bb-02\")|.team")" == bob ]]'
ck "login ANTES da janela (sessão antiga) vincula (carol→M3)" '[[ "$(CJ ".sedes[]|select(.name==\"Sede B\")|.machines[0].team")" == carol ]]'
ck "adoção ≥60 min NA PROVA: code=1 (M1), vim=1 (M2), gedit NÃO (12 min)" '[[ "$(CJ .global.ed_adopt.code)" == 1 && "$(CJ .global.ed_adopt.vim)" == 1 && "$(CJ ".global.ed_adopt.gedit // 0")" == 0 ]]'
ck "grupos e nº de editores por time"  '[[ "$(CJ .global.ed_groups.vscode)" == 1 && "$(CJ .global.ed_groups.light)" == 1 && "$(CJ ".global.ed_count[\"1\"]")" == 2 && "$(CJ ".global.ed_count[\"0\"]")" == 1 ]]'
ck "perfis puros: vscode/light/none"   '[[ "$(CJ ".global.profiles|[.vscode,.light,.none]|join(\",\")")" == "1,1,1" ]]'
ck "pressão 8|vscode: n=1, swap máx 780, 15 pts no início e 15 na última hora, 3 janelas de 30 min" '[[ "$(CJ ".global.pressure[\"8|vscode\"]|[.n,.sw_max,.mem0_n,.mem4_n,(.series|length)]|join(\",\")")" == "1,780,15,15,3" ]]'
ck "pressão 16|light existe (M2)"      '[[ "$(CJ ".global.pressure[\"16|light\"].n")" == 1 ]]'
ck "série de 10 min ganhou swap e firewall" '[[ "$(CJ ".global.series[0]|has(\"sw_sum\") and has(\"fw_off\")")" == true ]]'
ck "rank_ed: 3 ranqueados; top30=3; quartil=1; code no all" '[[ "$(CJ ".global.rank_ed|[.n,.top30.n,.q1.n,.p10.n,.all.ed.code]|join(\",\")")" == "3,3,1,1,1" ]]'
ck "rank_ed por nó e por sede"         '[[ "$(CJ ".by_node[\"País X\"].rank_ed.n")" == 3 && "$(CJ ".sedes[]|select(.name==\"Sede A\")|.rank_ed.n")" == 2 ]]'
ck "papel NÃO rouba o elo (M1 = alice, não nt.admin)" '[[ "$(CJ ".sedes[]|select(.name==\"Sede A\")|.machines[]|select(.mac==\"aa-bb-01\")|.team")" == alice ]]'
ck "PRIVACIDADE: sem _rows e sem machine_id no cache" '! grep -q "_rows" "$C/var/nutella.cache.json" && ! grep -q "$MID1" "$C/var/nutella.cache.json"'
ck "bruto guardado (var/nutella-raw) com meta"  '[[ -s "$C/var/nutella-raw/meta.json" && -s "$C/var/nutella-raw/samples/26tsca.$M1.json" ]]'
: > "$MOCKD/gets.log"
CONTESTSDIR="$FIX" bash "$ROOT/score/nutella-gen.sh" nt --reaggregate >/dev/null 2>&1
ck "--reaggregate refaz do bruto SEM rede (mesmo resultado)" '[[ ! -s "$MOCKD/gets.log" && "$(CJ .global.rank_ed.n)" == 3 && "$(CJ .link.mode)" == ua ]]'
mv "$C/var/access.log" "$C/var/access.log.off"
CONTESTSDIR="$FIX" bash "$ROOT/score/nutella-gen.sh" nt --reaggregate >/dev/null 2>&1
ck "sem access.log: modo proxy (usadas), sem rank_ed" '[[ "$(CJ .link.mode)" == proxy && "$(CJ .global.pop.tm)" == 3 && "$(CJ .global.rank_ed.n)" == 0 && "$(CJ .global.pop.linked)" == 0 ]]'
mv "$C/var/access.log.off" "$C/var/access.log"
CONTESTSDIR="$FIX" bash "$ROOT/score/nutella-gen.sh" nt --reaggregate >/dev/null 2>&1

echo "== GET com escopo =="
call /contest/nutella GET ''
ck "admin vê as 2 sedes"             '[[ "$(J ".data.sedes|length")" == 2 ]]'
call /contest/nutella GET '' cst
ck "cstaff vê SÓ a Sede A"           '[[ "$(J ".data.sedes|length")" == 1 && "$(J ".data.sedes[0].name")" == "Sede A" ]]'
ck "…com rank_ed/link do 2.0 passando pelo escopo" '[[ "$(J ".data.sedes[0].rank_ed.n")" == 2 && "$(J .data.link.mode)" == ua ]]'
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
ck "mock recebeu POST {command} na imagem" 'grep -q "/api/v1/site-images/26tsca/commands" "$MOCKD/posts.log" && grep -q "\\\\\"command\\\\\":\\\\\"mlreboot\\\\\"" "$MOCKD/posts.log"'
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
