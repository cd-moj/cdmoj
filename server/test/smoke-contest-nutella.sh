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
# AGENTE NOVO só em M1 (t_agent, modelo do equipamento, reboot NO MEIO da prova); M2 segue com o
# agente antigo e ganha um alerta `identity.duplicate` do servidor. Frota mista é o caso real
# (conferido em 21/09/2026: a 26tete tinha uma máquina de cada).
jq -c --argjson lb "$((T0+1000))" --arg m1 "$M1" '
  .machines[0] |= (. + {last_boot:$lb, boots:2} | .status.t_agent = ($lb + 5)
                   | .status.hwinfo += {mac:$m1, product_vendor:"Dell Inc.", product_name:"OptiPlex 3090", hostname:"lab-01"})
  | .machines[1].alerts = [{id:"a1", kind:"identity.duplicate", detail:"machine_id repetido", other_mac:$m1, at:1}]' \
  "$MOCKD/machines.26tsca.json" > "$MOCKD/m.tmp" && mv "$MOCKD/m.tmp" "$MOCKD/machines.26tsca.json"
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
              else (if $i < 6 then ["gedit"] else [] end) end) }
       # pontos do AGENTE NOVO (só na máquina "code" = M1): PSI subindo, 2 OOM kills no meio,
       # ociosa 1 ponto em 4, relógio 5 min atrasado
       + (if $kind == "code" then { psi_mem: ($i / 10), psi_cpu: 1, psi_io: 0.5,
                                   oom: (if $i < 20 then 0 else 2 end),
                                   idle: (if ($i % 4) == 0 then 600 else 5 end), skew: 300 } else {} end) ]}'; }
mksamp "$M1" "$T0" code   > "$MOCKD/samples.26tsca.$M1.json"
mksamp "$M2" "$T0" vim30  > "$MOCKD/samples.26tsca.$M2.json"
mksamp "$M3" "$T0" gedit6 > "$MOCKD/samples.26tscb.$M3.json"
# access.log do contest (epoch \t login \t ip \t ua_b64 [\t ator]) — o UA do mlinux liga o login à máquina.
# alice→M1 · bob→M2 (MESMO machine_id de M1; só o boot_id separa) · carol→M3 às 10h, ANTES da
# janela, e fica logada (sessão não expira: tem de valer) · nt.admin em M1 DEPOIS (papel: não
# pode roubar o elo) · alice com Firefox comum (ignorado) · dave nunca loga (ausente)
# ⚠ carol está no roster da 26tscb mas o UA dela diz 26tsca (pendrive da sede vizinha): o ROSTER
# manda — ela NÃO pode contar nas duas sedes.
ua(){ printf 'Mozilla/5.0 (MLinux/%s/%s/%s) Gecko/20100101 Firefox/148.0' "${3:-26tsca}" "$1" "$2" | base64 -w0; }
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
export NB_MOCK_KEY="nb3a_mocktest123" NB_MOCK_SKEY="nb3s_servicetest456" NB_MOCK_SIMAGES="26ts*"
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
call /contest/nutella GET ''
ck "GET diz a CLASSE da chave (admin), nunca a chave" '[[ "$(J .key_kind)" == admin && "$BODY" != *mocktest* ]]'
call /contest/nutella POST '{"action":"config","images":"26tsca ../etc"}'
ck "site-image com caminho → 422"   '[[ "$OUT" == *"Status: 422"* && "$OUT" == *images_invalid* ]]'

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
ck "bruto guardado (var/nutella-raw) com meta — 1 NDJSON por sede"  '[[ -s "$C/var/nutella-raw/meta.json" && -s "$C/var/nutella-raw/samples/26tsca.ndjson" && "$(wc -l < "$C/var/nutella-raw/samples/26tsca.ndjson")" == 2 ]]'

echo "== coleta em LOTE (NutellaBoot 3) e a telemetria do agente novo =="
ck "UM request de samples por sede (2), nenhum por máquina" '[[ "$(grep -c "/samples?" "$MOCKD/gets.log")" == 2 ]] && ! grep -q "/machines/.*/samples" "$MOCKD/gets.log"'
ck "pede limit=5000 e active_since (sem reamostrar a janela)" 'grep -q "limit=5000&active_since=$((T0-3600))" "$MOCKD/gets.log"'
ck "saúde: 1 máquina com agente novo; PSI somado só dela" '[[ "$(CJ ".global.health|[.agent_new,.psi_n,.psi_mem_sum]|join(\",\")")" == "1,40,78" ]]'
ck "OOM: 2 kills em 1 máquina (incremento do contador, não o valor)" '[[ "$(CJ ".global.health|[.oom_machines,.oom_kills]|join(\",\")")" == "1,2" ]]'
ck "ociosidade: 10 de 40 pontos > 5 min"   '[[ "$(CJ ".global.health|[.idle_pts,.idle_hi]|join(\",\")")" == "40,10" ]]'
ck "relógio: 1 máquina com skew > 2 min"   '[[ "$(CJ ".global.health|[.skew_n,.skew_bad]|join(\",\")")" == "1,1" ]]'
ck "reboot NO MEIO da prova contado"       '[[ "$(CJ .global.health.reboots)" == 1 ]]'
ck "PSI entra na pressão por faixa×perfil" '[[ "$(CJ ".global.pressure[\"8|vscode\"]|[.psi_n,.psi_max]|join(\",\")")" == "40,3.9" && "$(CJ ".global.pressure[\"16|light\"].psi_n")" == 0 ]]'
ck "modelo do equipamento (máquinas de time)" '[[ "$(CJ ".global.model_tm[\"Dell Inc. OptiPlex 3090\"]")" == 1 ]]'
ck "alertas POR TIPO (identity.duplicate)"  '[[ "$(CJ ".global.alert_kinds[\"identity.duplicate\"]")" == 1 && "$(CJ .global.alerts)" == 1 ]]'
ck "rollup por nó e por sede carregam a saúde" '[[ "$(CJ ".by_node[\"País X\"].health.oom_kills")" == 2 && "$(CJ ".sedes[]|select(.name==\"Sede B\")|.health.agent_new")" == 0 ]]'
ck "série de 10 min ganhou PSI"            '[[ "$(CJ ".global.series|map(.psi_n)|add")" == 40 ]]'
ck "PRIVACIDADE: hostname e MAC do hwinfo não entram no cache" '! grep -q "lab-01" "$C/var/nutella.cache.json"'
# o bruto das coletas ANTERIORES (um arquivo por máquina — o da LATAM 2026) tem de reagregar IGUAL
cp "$C/var/nutella.cache.json" "$MOCKD/cache.lote.json"
RAWS="$C/var/nutella-raw/samples"
for nd in "$RAWS"/*.ndjson; do id="$(basename "$nd" .ndjson)"
  while IFS= read -r ln; do mac="$(jq -r .mac <<<"$ln")"; jq -c 'del(.native_points,.resampled,.interval_s,.since,.until)' <<<"$ln" > "$RAWS/$id.$mac.json"; done < "$nd"
  rm -f "$nd"; done
CONTESTSDIR="$FIX" bash "$ROOT/score/nutella-gen.sh" nt --reaggregate >/dev/null 2>&1
ck "bruto ANTIGO (por máquina, sem metadados) reagrega IGUAL ao lote" 'diff <(jq -S "del(.collected_at)" "$MOCKD/cache.lote.json") <(jq -S "del(.collected_at)" "$C/var/nutella.cache.json") >/dev/null'
# serviço SEM a rota de lote (404): o coletor cai no caminho por máquina e chega ao mesmo lugar
touch "$MOCKD/nolote"; : > "$MOCKD/gets.log"
CONTESTSDIR="$FIX" bash "$ROOT/score/nutella-gen.sh" nt >/dev/null 2>&1
ck "fallback por máquina quando o lote dá 404" 'grep -q "/machines/aa-bb-01/samples" "$MOCKD/gets.log" && [[ -s "$C/var/nutella-raw/samples/26tsca.$M1.json" ]]'
# (`window.end` fica de fora: prova ABERTA ⇒ é o "agora" de cada coleta, e são duas coletas)
ck "…com o MESMO resultado"                'diff <(jq -S "del(.collected_at, .window.end)" "$MOCKD/cache.lote.json") <(jq -S "del(.collected_at, .window.end)" "$C/var/nutella.cache.json") >/dev/null'
rm -f "$MOCKD/nolote"
CONTESTSDIR="$FIX" bash "$ROOT/score/nutella-gen.sh" nt >/dev/null 2>&1
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

echo "== comandos (NutellaBoot 3: SEMPRE a rota da sede, com target) =="
# O mock é ESTRITO como o serviço: POST …/machines/{mac}/commands = 405 e POST /commands sem
# `targets` = 400. O código anterior a 21/09/2026 caía nos dois (e o mock antigo aceitava tudo).
: > "$MOCKD/posts.log"; : > "$MOCKD/rejected.log"
call /contest/nutella POST '{"action":"command","op":"mlreboot","image":"26tsca"}'
ck "admin comanda a sede → 200"      '[[ "$(J .sent)" == true && "$(J .ok)" == 1 ]]'
ck "mock recebeu {command, target:all} na rota da sede" 'jq -e "select(.path==\"/api/v1/site-images/26tsca/commands\") | .body | fromjson | (.command==\"mlreboot\" and .target==\"all\")" "$MOCKD/posts.log" >/dev/null'
ck "a resposta traz command_id e nº de máquinas" '[[ "$(J ".sedes[\"26tsca\"].machines")" == 2 && -n "$(J ".sedes[\"26tsca\"].command_id")" ]]'
call /contest/nutella POST '{"action":"command","op":"hackop","image":"26tsca"}'
ck "op fora do catálogo → 422"       '[[ "$OUT" == *"Status: 422"* && "$OUT" == *op_not_allowed* ]]'
: > "$MOCKD/posts.log"
call /contest/nutella POST '{"action":"command","op":"mlreboot","image":"26tsca","mac":"'"$M1"'"}'
ck "comando numa MÁQUINA = rota da sede com target:[mac]" '[[ "$(J .sent)" == true ]] && jq -e "select(.path==\"/api/v1/site-images/26tsca/commands\") | .body | fromjson | .target == [\"aa-bb-01\"]" "$MOCKD/posts.log" >/dev/null'
ck "…e 1 máquina só"                 '[[ "$(J ".sedes[\"26tsca\"].machines")" == 1 ]]'
ck "NUNCA a rota inexistente …/machines/{mac}/commands" '! grep -q "/machines/aa-bb-01/commands" "$MOCKD/posts.log" "$MOCKD/rejected.log"'
: > "$MOCKD/posts.log"
call /contest/nutella POST '{"action":"command","op":"mlreboot","image":"all"}'
ck "\"todas\" = UMA ordem por sede DO CONTEST (2)" '[[ "$(J .sent)" == true && "$(J .ok)" == 2 && "$(J .failed)" == 0 ]]'
ck "…nas duas sedes do evento"       'grep -q "site-images/26tsca/commands" "$MOCKD/posts.log" && grep -q "site-images/26tscb/commands" "$MOCKD/posts.log"'
ck "…e NUNCA na frota do serviço (sede de outro evento fica de fora)" '! grep -q "\"/api/v1/commands\"" "$MOCKD/posts.log" "$MOCKD/rejected.log" && ! grep -q "26zzzz" "$MOCKD/posts.log"'
call /contest/nutella POST '{"action":"command","op":"mlreboot","image":"26tsca"}' cst
ck "cstaff na própria sede → 200"    '[[ "$(J .sent)" == true ]]'
call /contest/nutella POST '{"action":"command","op":"mlreboot","image":"26tscb"}' cst
ck "cstaff em sede ALHEIA → 403"     '[[ "$OUT" == *"Status: 403"* && "$OUT" == *site_forbidden* ]]'
call /contest/nutella POST '{"action":"command","op":"mlreboot","image":"all"}' cst
ck "cstaff em todas → 403"           '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/nutella POST '{"action":"command","op":"mlreboot","image":"26tsca"}' stf
ck "staff SEM escopo → 403 (fail-closed)" '[[ "$OUT" == *"Status: 403"* && "$OUT" == *command_scope_required* ]]'
ck "comandos auditados (um por sede)" '[[ "$(grep -c "nutella-command" "$C/var/admin-audit.log")" -ge 4 ]]'
# sede que RECUSA (cadeado do modelo): as outras seguem, e a recusada aparece pelo nome
jq -n '{allowed:["mlreboot","precontest","cleanhomenow","disablefirewall"], blocked:{disablefirewall:"DISABLE_FIREWALL"}}' > "$MOCKD/commands.json"
call /contest/nutella POST '{"action":"command","op":"disablefirewall","image":"26tsca"}'
ck "comando bloqueado pelo modelo → 502 com o motivo do serviço" '[[ "$OUT" == *"Status: 502"* && "$OUT" == *DISABLE_FIREWALL* ]]'
jq -n '{allowed:["mlreboot","precontest","cleanhomenow"], blocked:{}}' > "$MOCKD/commands.json"

echo "== push-roster =="
call /contest/nutella POST '{"action":"push-roster"}'
ck "sem force: roster povoado é PRESERVADO" '[[ "$(J .kept)" == 2 && "$(J .pushed)" == 0 ]]'
call /contest/nutella POST '{"action":"push-roster","force":true}'
ck "force: PUT do roster nas 2 imagens" '[[ "$(J .pushed)" == 2 ]] && grep -q "\"PUT\"" "$MOCKD/posts.log" && grep -q "Time Alice" "$MOCKD/posts.log"'

echo "== CHAVE DE SERVIÇO (nb3s_): a recomendada — protocolo NOVO (≥ 21/09/2026) =="
# Desde 21/09 o serviço responde /whoami e lista /site-images pelo glob da chave de serviço; rota de
# console dá 403 console_only; todo erro traz `code`. Antes o MOJ nem ACEITAVA o prefixo nb3s_.
call /contest/nutella POST '{"action":"config","key":"nb3s_servicetest456","images":""}'
ck "chave nb3s_ é aceita"            '[[ "$(J .saved)" == true && "$(J .key_kind)" == service ]]'
rm -f "$C/var/nutella.cache.json"
CONTESTSDIR="$FIX" bash "$ROOT/score/nutella-gen.sh" nt >/dev/null 2>&1
ck "SEM lista à mão a coleta funciona: as sedes vêm do glob da chave (2 de 3 do serviço)" '[[ "$(jq -r .ok "$C/var/nutella.status.json")" == true && "$(CJ ".sedes|length")" == 2 && "$(CJ .link.mode)" == ua ]]'
# a chave de serviço é criada POR EVENTO: o que ela lista é a lista do evento — sede do glob sem roster nem
# login ainda (véspera) ENTRA, como se estivesse em NUTELLABOOT_IMAGES (conferido na 26tete real: roster vazio)
cp "$MOCKD/roster.26tscb.json" "$MOCKD/roster.26tscb.bak3"; jq -n '{roster:[]}' > "$MOCKD/roster.26tscb.json"; cp "$C/var/access.log" "$MOCKD/access.bak3"; : > "$C/var/access.log"
CONTESTSDIR="$FIX" bash "$ROOT/score/nutella-gen.sh" nt >/dev/null 2>&1
ck "…sede do glob sem roster nem login (véspera) entra mesmo assim" '[[ "$(jq -r .ok "$C/var/nutella.status.json")" == true && "$(CJ "[.sedes[].id]|sort|join(\",\")")" == "26tsca,26tscb" ]]'
mv "$MOCKD/roster.26tscb.bak3" "$MOCKD/roster.26tscb.json"; mv "$MOCKD/access.bak3" "$C/var/access.log"
CONTESTSDIR="$FIX" bash "$ROOT/score/nutella-gen.sh" nt >/dev/null 2>&1
ck "…e o lote de samples foi pedido com gzip (Accept-Encoding)" 'grep -q "gzip" "$MOCKD/gets.log"'
: > "$MOCKD/posts.log"
call /contest/nutella POST '{"action":"command","op":"mlreboot","image":"all"}'
ck "\"todas\" com chave de serviço (a rota de frota daria 403 console_only)" '[[ "$(J .ok)" == 2 ]]'
CID="$(J '.sedes["26tsca"].command_id')"
call /contest/nutella POST "$(jq -cn --arg c "$CID" '{action:"command-status", image:"26tsca", command_id:$c}')"
ck "command-status: quem executou (1 acked, 1 pending)" '[[ "$(J .status.summary.acked)" == 1 && "$(J .status.summary.pending)" == 1 && "$(J ".status.targets|length")" == 2 ]]'
call /contest/nutella POST "$(jq -cn --arg c "$CID" '{action:"command-status", image:"26tscb", command_id:$c}')" cst
ck "…staff só acompanha ordem da PRÓPRIA sede (Sede B → 403)" '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/nutella POST "$(jq -cn --arg c "$CID" '{action:"command-status", image:"26tsca", command_id:$c}')" stf
ck "…staff SEM escopo não acompanha nada (fail-closed)" '[[ "$OUT" == *"Status: 403"* ]]'
pf(){ OUT="$(PATH_INFO=/contest/admin/preflight REQUEST_METHOD=GET QUERY_STRING="contest=nt" HTTP_AUTHORIZATION="Bearer adm" \
  CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pf; ck "preflight com chave de SERVIÇO: ok pelo /whoami (escopos completos, 2 sedes)" '[[ "$(J ".checks[]|select(.id==\"mlinux\")|.level")" == ok && "$(J ".checks[]|select(.id==\"mlinux\")|.detail")" == *"2 sede"* ]]'
# chave de serviço cujo glob NÃO cobre a imagem listada à mão: recusa clara no comando e `skipped` na coleta
call /contest/nutella POST '{"action":"config","images":"26tsca 26tscb 26zzzz"}'
call /contest/nutella POST '{"action":"command","op":"mlreboot","image":"26zzzz"}'
ck "imagem fora do alcance da chave → 502" '[[ "$OUT" == *"Status: 502"* ]]'
CONTESTSDIR="$FIX" bash "$ROOT/score/nutella-gen.sh" nt >/dev/null 2>&1
ck "coleta: imagem listada à mão que o serviço não devolve vai p/ skipped; as outras 2 seguem" '[[ "$(jq -r .ok "$C/var/nutella.status.json")" == true && "$(CJ ".skipped|join(\",\")")" == 26zzzz && "$(CJ ".sedes|length")" == 2 ]]'
call /contest/nutella POST '{"action":"config","images":"26zzzz"}'
CONTESTSDIR="$FIX" bash "$ROOT/score/nutella-gen.sh" nt >/dev/null 2>&1
ck "coleta: NENHUMA sede ⇒ falha dizendo o porquê (nunca um cache ok:true zerado)" '[[ "$(jq -r .ok "$C/var/nutella.status.json")" == false && "$(CJ ".sedes|length")" == 2 ]]'

echo "== …e o serviço LEGADO (antes de 21/09): chave de serviço sem /whoami nem lista =="
touch "$MOCKD/legacy"
call /contest/nutella POST '{"action":"config","images":""}'
rm -f "$C/var/nutella.cache.json"
CONTESTSDIR="$FIX" bash "$ROOT/score/nutella-gen.sh" nt >/dev/null 2>&1
ck "sem a lista de site-images a coleta PÁRA e diz o porquê" '[[ "$(jq -r .ok "$C/var/nutella.status.json")" == false && "$(jq -r .error "$C/var/nutella.status.json")" == *site-images* ]]'
call /contest/nutella POST '{"action":"config","images":"26tsca 26tscb"}'
ck "lista de site-images gravada"    'call /contest/nutella GET ""; [[ "$(J ".images|join(\",\")")" == "26tsca,26tscb" ]]'
CONTESTSDIR="$FIX" bash "$ROOT/score/nutella-gen.sh" nt >/dev/null 2>&1
ck "com a lista, a coleta funciona"  '[[ "$(jq -r .ok "$C/var/nutella.status.json")" == true && "$(CJ ".sedes|length")" == 2 ]]'
pf; ck "preflight legado com chave de SERVIÇO: ok (prova acesso lendo a 1ª sede)" '[[ "$(J ".checks[]|select(.id==\"mlinux\")|.level")" == ok && "$(J ".checks[]|select(.id==\"mlinux\")|.detail")" == *"lê 26tsca"* ]]'
call /contest/nutella POST '{"action":"config","images":"26tsca 26tscb 26zzzz"}'
CONTESTSDIR="$FIX" bash "$ROOT/score/nutella-gen.sh" nt >/dev/null 2>&1
ck "coleta legada: sede recusada (403) vai p/ skipped; as outras 2 seguem" '[[ "$(jq -r .ok "$C/var/nutella.status.json")" == true && "$(CJ ".skipped|join(\",\")")" == 26zzzz && "$(CJ ".sedes|length")" == 2 ]]'
rm -f "$MOCKD/legacy"
call /contest/nutella POST '{"action":"config","key":"nb3a_mocktest123","images":""}'
pf; ck "preflight com chave de ADMINISTRAÇÃO: ok pelo /whoami" '[[ "$(J ".checks[]|select(.id==\"mlinux\")|.level")" == ok ]]'

echo "== ROSTER VAZIO no serviço (caso real de 21/09/2026: TODAS as imagens estavam assim) =="
# Sem roster, quem diz "este time é desta sede" é o UA do login (`MLinux/<imagem>/…`); e a imagem
# listada à mão em NUTELLABOOT_IMAGES fica mesmo sem time nenhum. Antes: "nenhuma sede casa".
for r in 26tsca 26tscb; do cp "$MOCKD/roster.$r.json" "$MOCKD/roster.$r.bak"; jq -n '{roster:[]}' > "$MOCKD/roster.$r.json"; done
cp "$C/var/access.log" "$MOCKD/access.bak"
printf '%s\tcarol\t10.0.0.3\t%s\n' "$((T0-4000))" "$(ua $MID3 $BOOT3 26tscb)" >> "$C/var/access.log"
CONTESTSDIR="$FIX" bash "$ROOT/score/nutella-gen.sh" nt >/dev/null 2>&1
ck "sem roster e sem lista: as sedes saem do UA dos logins (2 sedes, nome do store)" '[[ "$(jq -r .ok "$C/var/nutella.status.json")" == true && "$(CJ ".sedes|map(.name)|sort|join(\",\")")" == "Sede A,Sede B" ]]'
ck "…times = quem logou da imagem (alice+bob na A, carol na B; dave, que nunca logou, fora)" '[[ "$(CJ ".sedes[]|select(.name==\"Sede A\")|.pop.teams")" == 2 && "$(CJ ".sedes[]|select(.name==\"Sede B\")|.pop.teams")" == 1 && "$(CJ .link.linked)" == 3 ]]'
ck "…conta de papel não vira time da sede (nt.admin logou da 26tsca)" '[[ "$(CJ ".sedes[]|select(.name==\"Sede A\")|[.machines[].team]|index(\"nt.admin\")")" == null ]]'
: > "$C/var/access.log"
call /contest/nutella POST '{"action":"config","images":"26tscb"}'
CONTESTSDIR="$FIX" bash "$ROOT/score/nutella-gen.sh" nt >/dev/null 2>&1
ck "sem roster E sem login: a imagem LISTADA À MÃO fica (nome = fullname da imagem)" '[[ "$(jq -r .ok "$C/var/nutella.status.json")" == true && "$(CJ ".sedes|length")" == 1 && "$(CJ ".sedes[0].id")" == 26tscb ]]'
call /contest/nutella POST '{"action":"config","images":""}'
CONTESTSDIR="$FIX" bash "$ROOT/score/nutella-gen.sh" nt >/dev/null 2>&1
ck "sem roster, sem login e sem lista: aí sim nenhuma sede (erro claro)" '[[ "$(jq -r .ok "$C/var/nutella.status.json")" == false ]]'
cp "$MOCKD/access.bak" "$C/var/access.log"; for r in 26tsca 26tscb; do mv "$MOCKD/roster.$r.bak" "$MOCKD/roster.$r.json"; done

echo "== ELO PELO MAC (agente novo: o UA termina no MAC) e o binding do serviço de reserva =="
# M4 é CLONE de M1 (mesmo machine_id ⇒ o fallback por mid está vetado) e REINICIOU depois do login
# (o boot_id do serviço já é outro ⇒ o par mid/boot não casa). Só o MAC liga erin à máquina.
# M5 nunca teve login com UA do mlinux: vale o `binding` do serviço (fred) — e o binding de um login
# que NÃO é time da sede (M6 → "intruso") é ignorado.
M4=aa-bb-04; M5=aa-bb-05; M6=aa-bb-06
cp "$MOCKD/machines.26tscb.json" "$MOCKD/machines.26tscb.bak"; cp "$MOCKD/roster.26tscb.json" "$MOCKD/roster.26tscb.bak2"; cp "$C/var/access.log" "$MOCKD/access.bak2"
for u in erin fred; do fx_user "$C" $u x "Time $u" >/dev/null; fx_team $u "Sede B"; done
jq -c '.roster += [{user_id:"erin", name:"Time Erin"}, {user_id:"fred", name:"Time Fred"}]' "$MOCKD/roster.26tscb.bak2" > "$MOCKD/roster.26tscb.json"
jq -c --argjson m4 "$(mkmach $M4 "$TE" "Intel(R) Core(TM) i5-8400 CPU @ 2.80GHz" 6 7812 '{}' "$MID1" 4444444499)" \
      --argjson m5 "$(mkmach $M5 "$TE" "Intel(R) Core(TM) i5-8400 CPU @ 2.80GHz" 6 7812 '{}' "55555555555555555555555555555555" 5555555555)" \
      --argjson m6 "$(mkmach $M6 "$TE" "Intel(R) Core(TM) i5-8400 CPU @ 2.80GHz" 6 7812 '{}' "66666666666666666666666666666666" 6666666666)" \
      '.machines += [$m4, ($m5 | .binding = {user_id:"fred", source:"manual", at:1}), ($m6 | .binding = {user_id:"intruso", source:"manual", at:1})]' \
      "$MOCKD/machines.26tscb.bak" > "$MOCKD/machines.26tscb.json"
printf '%s\terin\t10.0.0.4\t%s\n' "$((T0+50))" "$(printf 'Mozilla/5.0 (MLinux/26tscb/%s/4444444411/AA:BB:04) Gecko' "$MID1" | base64 -w0)" >> "$C/var/access.log"
printf '%s\terin\t10.0.0.4\t%s\n' "$((T0+60))" "$(printf 'Mozilla/5.0 (MLinux/26tscb/%s/4444444411/aa-bb-cc-dd-ee-04) Gecko' "$MID1" | base64 -w0)" >> "$C/var/access.log"
# (o MAC da fixture é curto — "aa-bb-04" — e o UA real tem 6 octetos: a máquina M4 ganha o MAC real)
jq -c '(.machines[] | select(.mac == "aa-bb-04") | .mac) = "aa-bb-cc-dd-ee-04"' "$MOCKD/machines.26tscb.json" > "$MOCKD/m.tmp" && mv "$MOCKD/m.tmp" "$MOCKD/machines.26tscb.json"
CONTESTSDIR="$FIX" bash "$ROOT/score/nutella-gen.sh" nt >/dev/null 2>&1
SB(){ CJ ".sedes[]|select(.name==\"Sede B\")|$1"; }
ck "MAC liga erin à M4 apesar do clone de machine_id E do reboot" '[[ "$(SB ".machines[]|select(.mac==\"aa-bb-cc-dd-ee-04\")|.team")" == erin ]]'
ck "…e o clone NÃO rouba o elo de alice (M1 segue dela)" '[[ "$(CJ ".sedes[]|select(.name==\"Sede A\")|.machines[]|select(.mac==\"aa-bb-01\")|.team")" == alice ]]'
ck "sem UA: vale o binding do serviço (fred na M5)" '[[ "$(SB ".machines[]|select(.mac==\"aa-bb-05\")|.team")" == fred ]]'
ck "binding de quem NÃO é time da sede é ignorado (M6 sem time)" '[[ "$(SB ".machines[]|select(.mac==\"aa-bb-06\")|.team")" == null ]]'
ck "o elo conta os dois caminhos novos (erin pelo MAC, fred pelo binding): 5 vinculados" '[[ "$(CJ .link.linked)" == 5 ]]'
ck "MAC continua FORA dos agregados (global/by_node)" '! jq -c "[.global, .by_node]" "$C/var/nutella.cache.json" | grep -q "aa-bb"'
mv "$MOCKD/machines.26tscb.bak" "$MOCKD/machines.26tscb.json"; mv "$MOCKD/roster.26tscb.bak2" "$MOCKD/roster.26tscb.json"; cp "$MOCKD/access.bak2" "$C/var/access.log"

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
