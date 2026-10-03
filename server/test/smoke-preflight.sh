#!/bin/bash
# smoke-preflight.sh — CHECKLIST PRÉ-PROVA (/contest/admin/preflight).
#
# É a tela que o organizador olha antes de largar (e a Central do painel de admin renderiza item
# por item, com botão p/ o painel que resolve cada um). Aqui se garante que cada situação
# conhecida vira o item com o LEVEL certo — inclusive as que já custaram susto em prova:
#   - `.cstaff` NÃO é competidor (era contado como conta de aluno);
#   - staff/chefe de sede SEM escopo enxerga as etiquetas COM SENHA de todos os times;
#   - mais de 15 problemas sem balloons.json ⇒ balão cinza da letra P em diante;
#   - coorte privada, gate de UA armado sem casar ninguém, rodada seguinte pendente, documentos.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"   # .../server
ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; SPOOL="$(mktemp -d)"; REG="$(mktemp -d)"; RUN="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$SPOOL" "$REG" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"

CONTEST=prova; ADMIN=chefe.admin
C="$FIX/$CONTEST"; mkdir -p "$C/var" "$C/enunciados" "$C/print-requests"
NOW="$EPOCHSECONDS"

probs=""
for i in $(seq 0 17); do            # 18 problemas => letras passam de O (balões cinza)
  L="$(printf "\\$(printf '%03o' $((65+i)))")"
  probs+="f$i col/p$i 'Prob $L' $L 'col#p$i' "
done
{ printf 'CONTEST_ID=%s\nCONTEST_NAME="Prova"\nCONTEST_TYPE=icpc\n' "$CONTEST"
  printf 'CONTEST_START=%s\nCONTEST_END=%s\nFREEZE_TIME=%s\nUSER_STORE=v2\nLANGUAGES="c"\n' \
    "$((NOW-3600))" "$((NOW+3600))" "$((NOW+1800))"
  # MÓDULOS (lib/modules.sh): as checagens de evento abaixo só rodam com o módulo ligado
  printf 'CONTEST_MODULES=sedes,maquinas,rodadas,documentos,baloes,coortes,inscricoes,telao,classificacao\n'
  printf 'PROBS=(%s)\n' "$probs"; } > "$C/conf"

fx_user "$C" "$ADMIN" adm "Chefe"
fx_user "$C" teambrspso001 x "Sorocaba Alfa"
fx_user "$C" teambrspso002 x "Sorocaba Beta"
fx_user "$C" cclconv01     x "Convidado"
fx_user "$C" sala1.staff   x "Staff 1"
fx_user "$C" sede.cstaff   x "Chefe de Sede"
printf '[{"name":"Sorocaba","regex":"^teambrspso"}]' > "$C/regions.json"

# coorte privada de convidados (não liberada) + gate por sede + rodada seguinte planejada
cat > "$C/cohorts.json" <<'EOF'
{ "cohorts":[{"id":"oficial","name":"Oficiais","default":true,"public":true,"sees":[]},
             {"id":"ccl","name":"CCL","regex":"^ccl","public":false,"unranked":true,"sees":["oficial","ccl"]}],
  "results_released": false }
EOF
cat > "$C/ua-gate.json" <<'EOF'
{ "mode":"enforce", "from_login":{"regex":"^team([a-z]{6})[0-9]{3}$","expect":"\\1"}, "exempt":["^ccl"] }
EOF
cat > "$C/rounds.json" <<EOF
{ "active":"aquecimento",
  "rounds":[{"slug":"aquecimento","name":"Aquecimento","kind":"warmup","state":"active"},
            {"slug":"final","name":"Prova oficial","kind":"official","state":"pending",
             "start":$((NOW+7200)),"end":$((NOW+14400))}] }
EOF

TOKEN="11111111-2222-3333-4444-555555555555"
cat > "$SESS/$TOKEN" <<EOF
CONTEST="$CONTEST"
LOGIN="$ADMIN"
USERFULLNAME="Chefe"
LOGINAT=$EPOCHSECONDS
EOF

pass=0; fail=0
check(){ if eval "$2"; then printf '  ok: %s\n' "$1"; ((pass++)); else printf '  FAIL: %s\n' "$1"; ((fail++)); fi; }
# TRILÍNGUE (pt/en/es): TODO item de TODA execução leva label_en/detail_en/label_es/detail_es (string;
# label não-vazio; detail vazio só se vazio nos três) e nada de português no en/es. Acumula por
# execução — muitos itens (pool/langs fail, judges_warm, telao…) só existem em estados intermediários.
I18N_BAD=""; I18N_SEEN=""
i18n_scan(){
  printf '%s' "$BODY" | jq -e '.checks' >/dev/null 2>&1 || return 0
  local bad seen
  bad="$(printf '%s' "$BODY" | jq -r '.checks[]
      | select(([.label_en, .detail_en, .label_es, .detail_es] | map(type == "string") | all | not)
               or ((.label_en // "") == "") or ((.label_es // "") == "")
               or (((.detail // "") == "") != ((.detail_en // "") == ""))
               or (((.detail // "") == "") != ((.detail_es // "") == ""))
               or ([.label_en, .detail_en, .label_es, .detail_es] | map(tostring) | join(" ")
                   | test("[ãõç]|ção|ções|não|você|também"; "i")))
      | .id' 2>/dev/null)"
  seen="$(printf '%s' "$BODY" | jq -r '.checks[].id' 2>/dev/null)"
  [[ -n "$bad" ]] && I18N_BAD+=" $(printf '%s' "$bad" | tr '\n' ' ')"
  I18N_SEEN+=" $(printf '%s' "$seen" | tr '\n' ' ')"
}
run(){ OUT="$(PATH_INFO="/contest/admin/preflight" REQUEST_METHOD=GET QUERY_STRING="contest=$CONTEST" \
  HTTP_AUTHORIZATION="Bearer $TOKEN" \
  CONTESTSDIR="$FIX" SESSIONDIR="$SESS" SPOOLDIR="$SPOOL" REGISTRYDIR="$REG" RUNDIR="$RUN" \
  bash "$ROUTER" <<<'' 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; i18n_scan; }
lvl(){ printf '%s' "$BODY" | jq -r --arg i "$1" 'first(.checks[]|select(.id==$i)|.level) // "(ausente)"'; }
det(){ printf '%s' "$BODY" | jq -r --arg i "$1" 'first(.checks[]|select(.id==$i)|.detail) // ""'; }
lbl(){ printf '%s' "$BODY" | jq -r --arg i "$1" 'first(.checks[]|select(.id==$i)|.label) // ""'; }

run
echo "== resposta =="
check "200 + JSON válido"        '[[ "$OUT" == *"Status: 200"* ]] && printf "%s" "$BODY" | jq -e . >/dev/null'
check "summary bate com checks"  'printf "%s" "$BODY" | jq -e ".summary.ok+.summary.warn+.summary.fail == (.checks|length)" >/dev/null'

echo "== contas: .cstaff NÃO é competidor (bug antigo: contava como aluno) =="
check "3 competidores (2 times + 1 convidado)" '[[ "$(det users)" == 3\ conta* ]]'

echo "== escopo do staff (etiquetas COM SENHA) =="
check "staff sem escopo => warn" '[[ "$(lvl staff_filters)" == warn ]]'
printf '{"sala1.staff":["region:Sorocaba"],"sede.cstaff":["^teambrspso"]}' > "$C/print-requests/staff-filters.json"
run
check "com escopo nos dois => ok" '[[ "$(lvl staff_filters)" == ok ]]'

echo "== balões: 18 problemas sem balloons.json =="
check "warn de letra sem cor"       '[[ "$(lvl balloons)" == warn ]]'
check "detalhe cita a letra P"      '[[ "$(det balloons)" == *"letra P em diante"* ]]'
printf '{"A":"FF0000"}' > "$C/balloons.json"; run
check "com balloons.json => ok"     '[[ "$(lvl balloons)" == ok ]]'

echo "== coortes =="
check "coorte privada não liberada => ok" '[[ "$(lvl cohorts)" == ok ]]'
check "detalhe conta a privada"           '[[ "$(det cohorts)" == *"1 privada"* ]]'
jq -c '.results_released=true' "$C/cohorts.json" > "$C/x" && mv "$C/x" "$C/cohorts.json"; run
check "resultados liberados => warn"      '[[ "$(lvl cohorts)" == warn ]]'

echo "== gate de navegador por sede =="
check "gate cobrindo os 2 times => ok" '[[ "$(lvl ua_gate)" == ok ]]'
check "detalhe conta 2 times"          '[[ "$(det ua_gate)" == 2\ time* ]]'
# regex que não casa NINGUÉM: gate armado e inútil (fail — é buraco, não aviso)
jq -c '.from_login.regex="^naoexiste([a-z]+)$"' "$C/ua-gate.json" > "$C/x" && mv "$C/x" "$C/ua-gate.json"; run
check "gate sem casar ninguém => fail" '[[ "$(lvl ua_gate)" == fail ]]'
# um time de fora do padrão: warn com a contagem
jq -c '.from_login.regex="^teambrspso001$" | .from_login.expect="brspso"' "$C/ua-gate.json" > "$C/x" && mv "$C/x" "$C/ua-gate.json"; run
check "1 time sem regra => warn"       '[[ "$(lvl ua_gate)" == warn ]]'
check "detalhe conta quem ficou fora"  '[[ "$(det ua_gate)" == *"1 sem regra"* ]]'
jq -c '.mode="off"' "$C/ua-gate.json" > "$C/x" && mv "$C/x" "$C/ua-gate.json"; run
check "mode:off => ok"                 '[[ "$(lvl ua_gate)" == ok ]]'
check "mode:off => sessão única nem aparece" '[[ "$(lvl session_single)" == "(ausente)" ]]'
jq -c '.mode="observe" | .from_login.regex="^team([a-z]{6})[0-9]{3}$" | .from_login.expect="\\1"' "$C/ua-gate.json" > "$C/x" && mv "$C/x" "$C/ua-gate.json"; run
check "mode:observe => ok com linha própria"  '[[ "$(lvl ua_gate)" == ok && "$(lbl ua_gate)" == *OBSERVAR* && "$(det ua_gate)" == *"ninguém é barrado"* ]]'
check "observe: sessão única diz que não vale" '[[ "$(lbl session_single)" == *"só no modo Barrar"* ]]'

echo "== sessão única por time (com gate ligado) =="
jq -c '.mode="enforce" | .from_login.regex="^team([a-z]{6})[0-9]{3}$" | .from_login.expect="\\1"' "$C/ua-gate.json" > "$C/x" && mv "$C/x" "$C/ua-gate.json"; run
check "gate ok + sessão única (default) => ok" '[[ "$(lvl session_single)" == ok ]]'
check "gate ok SEM trava de sede => warn"      '[[ "$(lvl site_lock)" == warn ]]'
printf 'SITE_LOCK=1\n' >> "$C/conf"; run
check "trava ligada => ok (0 IPs presos)"      '[[ "$(lvl site_lock)" == ok && "$(det site_lock)" == *"0 IP(s)"* ]]'
sed -i '/^SITE_LOCK=/d' "$C/conf"; run
jq -c '.single_session=false' "$C/ua-gate.json" > "$C/x" && mv "$C/x" "$C/ua-gate.json"; run
check "single_session:false => warn"   '[[ "$(lvl session_single)" == warn ]]'
check "detalhe aponta o painel"        '[[ "$(det session_single)" == *"Sessões & anomalias"* ]]'
jq -c 'del(.single_session)' "$C/ua-gate.json" > "$C/x" && mv "$C/x" "$C/ua-gate.json"; run

echo "== sede com menos máquinas que times (nutellaboot) =="
check "sem integração => item ausente" '[[ "$(lvl site_short)" == "(ausente)" ]]'
mkdir -p "$C/secrets"; printf 'nb3a_fakekeyfortest\n' > "$C/secrets/nutellaboot.key"; chmod 600 "$C/secrets/nutellaboot.key"
printf 'NUTELLABOOT_URL=http://127.0.0.1:9/\n' >> "$C/conf"
jq -n '{sedes:[{name:"Sorocaba", machines_total:1, seen:1, teams:["teambrspso001","teambrspso002"], pop:{teams:2, present:2}}]}' > "$C/var/nutella.cache.json"; run
check "1 máquina p/ 2 times => warn"   '[[ "$(lvl site_short)" == warn ]]'
check "detalhe cita a sede"            '[[ "$(det site_short)" == *"Sorocaba"* ]]'
jq -c '.sedes[0].machines_total=3 | .sedes[0].seen=3' "$C/var/nutella.cache.json" > "$C/x" && mv "$C/x" "$C/var/nutella.cache.json"; run
check "3 máquinas p/ 2 times => ok"    '[[ "$(lvl site_short)" == ok ]]'
rm -f "$C/var/nutella.cache.json" "$C/secrets/nutellaboot.key"; sed -i '/^NUTELLABOOT_URL=/d' "$C/conf"; run

echo "== rodada seguinte =="
check "rodada pendente aparece"        '[[ "$(lvl next_round)" == warn || "$(lvl next_round)" == ok ]]'
check "cita o slug da próxima"         'printf "%s" "$BODY" | jq -e "first(.checks[]|select(.id==\"next_round\")|.label) | test(\"final\")" >/dev/null'
jq -c '.rounds = [.rounds[] | select(.state != "pending")]' "$C/rounds.json" > "$C/x" && mv "$C/x" "$C/rounds.json"; run
check "sem pendente => ok"             '[[ "$(lvl next_round)" == ok ]]'

echo "== documentos =="
check "nenhum documento => warn"       '[[ "$(lvl docs)" == warn ]]'
mkdir -p "$C/docs"
printf '[{"type":"times","lang":"pt","html_bytes":10,"pdf_bytes":0,"generated_at":1,"by":"x"}]' > "$C/docs/index.json"
run
check "gerado mas não publicado => warn" '[[ "$(lvl docs)" == warn ]]'
check "detalhe diz 'só visíveis'"        '[[ "$(det docs)" == *"só visíveis"* ]]'
printf '{"published":["times.pt"]}' > "$C/docs/config.json"; run
check "publicado => ok"                  '[[ "$(lvl docs)" == ok ]]'

echo "== prorrogação × freeze =="
printf '[{"regex":"^teambrspso","end":%s,"reason":"queda de energia"}]' "$((NOW+7200))" > "$C/time-overrides.json"; run
check "prorrogação ativa => warn"          '[[ "$(lvl tov)" == warn ]]'
check "avisa que passa do freeze"          '[[ "$(det tov)" == *"passa do freeze"* ]]'

echo "== balão × freeze =="
check "com freeze, retém por padrão"       '[[ "$(lvl balloons_freeze)" == ok ]]'
check "diz a partir de que hora"           '[[ "$(det balloons_freeze)" == *"não vira tarefa de entrega"* ]]'
printf 'BALLOONS_DURING_FREEZE=1\n' >> "$C/conf"; run
check "permissão ligada => warn"           '[[ "$(lvl balloons_freeze)" == warn ]]'
sed -i '/^BALLOONS_DURING_FREEZE=/d' "$C/conf"; run

echo "== gate sem NENHUMA configuração: aviso (nada decidido), nunca fail falso =="
mv "$C/ua-gate.json" "$C/ua-gate.json.bak"; run
# TCP 2026: módulo maquinas ligado e nenhuma regra gravada = AVISO (o painel dizia "ativo"); Desligado gravado = ok
check "sem ua-gate.json (maquinas ligado) => warn" '[[ "$(lvl ua_gate)" == warn && "$(det ua_gate)" == *"Observar"* ]]'
printf '{"mode":"off"}' > "$C/ua-gate.json"; run
check "Desligado GRAVADO => ok (escolha)"  '[[ "$(lvl ua_gate)" == ok ]]'
rm -f "$C/ua-gate.json"
mv "$C/ua-gate.json.bak" "$C/ua-gate.json"; run

echo "== inscrição (roster + janela) =="
check "sem roster => item ausente"       '[[ "$(lvl registration)" == "(ausente)" ]]'
printf '{"version":1,"teams":{},"entries":{}}' > "$C/registrations.json"; run
check "roster vazio => warn"             '[[ "$(lvl registration)" == warn ]]'
check "diz onde as pessoas se inscrevem" '[[ "$(det registration)" == *"/contests/inscricao/"* ]]'
check "contas próprias => avisa fonte"   '[[ "$(lvl reg_source)" == warn ]]'
check "sem coortes de inscrição => warn" '[[ "$(lvl reg_cohorts)" == warn ]]'
printf '{"version":1,"teams":{"time-x":{"name":"X","captain":"a","members":["a"],"invited":["b","c"]}},"entries":{"a":{"kind":"team","team":"time-x"}}}' \
  > "$C/registrations.json"; run
check "com inscrito => ok"               '[[ "$(lvl registration)" == ok ]]'
check "convites pendentes => warn"       '[[ "$(lvl reg_invites)" == warn && "$(det reg_invites)" == *"NÃO entra"* ]]'
rm -f "$C/registrations.json"

echo "== módulos (lib/modules.sh): checagem só com o módulo ligado =="
run
check "todos ligados => modules ok lista os ids" '[[ "$(lvl modules)" == ok && "$(det modules)" == *"coortes"* ]]'
sed -i 's/^CONTEST_MODULES=.*/CONTEST_MODULES=sedes,maquinas,rodadas,documentos,baloes,inscricoes,telao,classificacao/' "$C/conf"; run
check "coortes DESLIGADO com cohorts.json => modules warn cita coortes" '[[ "$(lvl modules)" == warn && "$(det modules)" == *"coortes (cohorts.json)"* ]]'
check "coortes desligado => checagem cohorts OMITIDA"                   '[[ "$(lvl cohorts)" == "(ausente)" ]]'
check "os outros módulos seguem checados (ua_gate presente)"            '[[ -n "$(lvl ua_gate)" ]]'
sed -i '/^CONTEST_MODULES=/d' "$C/conf"; run
check "nenhum módulo => só o básico: sem ua_gate/docs/next_round/balloons/tov" '[[ "$(lvl ua_gate)$(lvl docs)$(lvl next_round)$(lvl balloons)$(lvl tov)$(lvl staff_filters)" == "(ausente)(ausente)(ausente)(ausente)(ausente)(ausente)" ]]'
check "nenhum módulo => mode não cobra icpc (ok) e modules avisa os dados existentes" '[[ "$(lvl mode)" == ok && "$(lvl modules)" == warn ]]'
sed -i '1a CONTEST_MODULES=sedes,maquinas,rodadas,documentos,baloes,coortes,inscricoes,telao,classificacao' "$C/conf"

echo "== problema PARALELO (CPUNEEDED>1) × largura dos juízes (judges_cpus) =="
# o json servível do banco leva cpu_needed/same_numa (gen-problem-json.sh); o juiz NOVO manda slot_cpus
mkdir -p "$FIX/treino/var/jsons"
printf '{"id":"col#p0","title":"P0","cpu_needed":4,"same_numa":false,"public":true}' > "$FIX/treino/var/jsons/col#p0.json"
jq -cn --argjson now "$NOW" '{host:"j1",last_seen:$now,langs:["c"],problems:{},total_slots:2,free_slots:2,slot_cpus:1,slots_by_node:{"0":2}}' > "$REG/j1.json"
run
check "juiz com 2 slots×1 cpu p/ um problema de 4 CPUs => warn" '[[ "$(lvl judges_cpus)" == warn && "$(det judges_cpus)" == *"A(4 CPUs)"* ]]'
jq -cn --argjson now "$NOW" '{host:"j1",last_seen:$now,langs:["c"],problems:{},total_slots:8,free_slots:8,slot_cpus:1,slots_by_node:{"0":3,"1":5}}' > "$REG/j1.json"
run
check "juiz com 8 slots => ok"                                     '[[ "$(lvl judges_cpus)" == ok && "$(det judges_cpus)" == *"A"* ]]'
printf '{"id":"col#p0","title":"P0","cpu_needed":4,"same_numa":true,"public":true}' > "$FIX/treino/var/jsons/col#p0.json"
jq -cn --argjson now "$NOW" '{host:"j1",last_seen:$now,langs:["c"],problems:{},total_slots:6,free_slots:6,slot_cpus:1,slots_by_node:{"0":3,"1":3}}' > "$REG/j1.json"
run
check "SAMENUMA com nós de 3: warn cita NUMA"                       '[[ "$(lvl judges_cpus)" == warn && "$(det judges_cpus)" == *"NUMA"* ]]'
jq -cn --argjson now "$NOW" '{host:"j1",last_seen:$now,langs:["c"],problems:{},total_slots:8,free_slots:8}' > "$REG/j1.json"
run
check "juiz ANTIGO (sem slot_cpus) não conta => warn"               '[[ "$(lvl judges_cpus)" == warn ]]'
printf 'CONTEST_JUDGES=j2\n' >> "$C/conf"
jq -cn --argjson now "$NOW" '{host:"j1",last_seen:$now,langs:["c"],problems:{},total_slots:8,free_slots:8,slot_cpus:1,slots_by_node:{"0":8}}' > "$REG/j1.json"
run
check "pool do contest (j2) sem o juiz capaz (j1) => warn"          '[[ "$(lvl judges_cpus)" == warn ]]'
sed -i '/^CONTEST_JUDGES=/d' "$C/conf"; rm -f "$FIX/treino/var/jsons/col#p0.json"
run
check "sem problema paralelo => checagem ausente (sem ruído)"       '[[ "$(lvl judges_cpus)" == "(ausente)" ]]'

echo "== telão (Animeitor): chave e conferência =="
run
check "módulo telao sem chave nenhuma => warn"                      '[[ "$(lvl telao)" == warn && "$(det telao)" == *"usuário e token"* ]]'
mkdir -p "$RUN/secrets"; ( umask 077; printf 'moj:chave-de-teste-123\n' > "$RUN/secrets/animeitor.cred" )
run
check "com a chave do MOJ no servidor => ok \"com chave do MOJ\""  '[[ "$(lvl telao)" == ok && "$(printf "%s" "$BODY" | jq -r "first(.checks[]|select(.id==\"telao\")|.label)")" == *"do MOJ"* ]]'
check "…e a chave não aparece em lugar nenhum da resposta"          '[[ "$BODY" != *chave-de-teste-123* ]]'
printf '{"url":"https://outro.exemplo"}' > "$C/animeitor.json"; run
check "URL fora do padrão: a chave do MOJ não vale lá => warn"       '[[ "$(lvl telao)" == warn && "$(det telao)" == *"só vale no servidor padrão"* ]]'
rm -f "$C/animeitor.json"
jq -cn --argjson t "$NOW" '{at:$t, state:"diverge", ok:false, final:false, missing:2, wrong:0, extra:1, sample:{missing:[1,2]}}' > "$C/var/animeitor-verify.json"; run
check "última conferência com divergência => warn com as contagens" '[[ "$(lvl telao)" == warn && "$(det telao)" == *"2 faltando, 0 diferentes, 1 a mais"* ]]'
jq -cn --argjson t "$NOW" '{at:$t, state:"ok", ok:true, final:true, final_at:$t}' > "$C/var/animeitor-verify.json"; run
check "conferência final => ok \"Telão validado\""                 '[[ "$(lvl telao)" == ok && "$(printf "%s" "$BODY" | jq -r "first(.checks[]|select(.id==\"telao\")|.label)")" == "Telão validado" ]]'
jq -cn --argjson t "$NOW" '{at:$t, state:"no_sites", ok:false, final:false}' > "$C/var/animeitor-verify.json"; run
check "conferência sem sede nenhuma => warn (era verde)"            '[[ "$(lvl telao)" == warn && "$(det telao)" == *"não achou sede"* ]]'
check "…com o atalho p/ a mesa do telão"                            '[[ "$(printf "%s" "$BODY" | jq -r "first(.checks[]|select(.id==\"telao\")|.action)")" == open_telao ]]'
rm -f "$C/var/animeitor-verify.json"
echo "== reveleitor: placares e sedes (telao_sites; TCP 2026 — esqueceram a sede Geral) =="
run
check "proposta (sem config) e nada publicado => ok, configurado com resultado geral" '[[ "$(lvl telao_sites)" == ok && "$(det telao_sites)" == *"ainda não publicado"* ]]'
GB='{"name":"Geral","source":{"kind":"view","id":"public"},"codes":null'
printf '{"contests":[%s,"sites":[{"name":"Sede A","source":{"kind":"region","id":"Sede A"},"codes":null}]}]}' "$GB" > "$C/animeitor.json"; run
check "config gravada sem a sede de todos os times => warn com o placar" '[[ "$(lvl telao_sites)" == warn && "$(det telao_sites)" == *"placar Geral"* && "$(det telao_sites)" == *"+ sede Geral"* ]]'
printf '{"contests":[%s,"sites":[{"name":"Geral","source":{"kind":"whole","id":"public"},"codes":null},{"name":"Sede A","source":{"kind":"region","id":"Sede A"},"codes":null}]}]}' "$GB" > "$C/animeitor.json"
jq -cn '{event:"ev", event_hash:"h", contests:{Geral:{hash:"x", sites:{"Sede A":"y"}}}}' > "$C/var/animeitor-managed.json"; run
check "config certa mas o publicado (managed) é antigo, sem a Geral => warn publique de novo" '[[ "$(lvl telao_sites)" == warn && "$(det telao_sites)" == *"publique de novo"* ]]'
jq -cn '{event:"ev", event_hash:"h", contests:{Geral:{hash:"x", sites:{"Geral":"z","Sede A":"y"}}}}' > "$C/var/animeitor-managed.json"; run
check "publicado com a Geral => ok com as contagens do reveleitor" '[[ "$(lvl telao_sites)" == ok && "$(det telao_sites)" == *"1 placar(es) e 2 sede(s)"* ]]'
printf '{"contests":[%s,"sites":[{"name":"Geral","source":{"kind":"whole","id":"public"},"codes":null},{"name":"Vazia","source":{"kind":"manual","id":""},"codes":[]}]}]}' "$GB" > "$C/animeitor.json"; run
check "sede com regex vazia na config antiga => warn sem times" '[[ "$(lvl telao_sites)" == warn && "$(det telao_sites)" == *"Geral › Vazia"* ]]'
rm -f "$C/animeitor.json" "$C/var/animeitor-managed.json"
sed -i 's/,telao,/,/' "$C/conf"; run
check "módulo telao desligado => checagem ausente"                   '[[ "$(lvl telao)" == "(ausente)" && "$(lvl telao_sites)" == "(ausente)" ]]'

echo "== abertura do login × janela da rodada ativa (login_open; TCP 2026) =="
run
check "sem abertura própria => ok (entra no início)"           '[[ "$(lvl login_open)" == ok && "$(det login_open)" == *"a partir do início"* ]]'
printf 'LOGIN_START_TIME=%s\n' "$((NOW-4200))" >> "$C/conf"; run
check "abre 10 min antes do início => ok com os minutos"       '[[ "$(lvl login_open)" == ok && "$(det login_open)" == *"10 min antes do início"* ]]'
sed -i '/^LOGIN_START_TIME=/d' "$C/conf"; printf 'LOGIN_START_TIME=%s\n' "$((NOW-1800))" >> "$C/conf"; run
check "abre DEPOIS do início => warn (perdem o começo)"         '[[ "$(lvl login_open)" == warn && "$(det login_open)" == *"30 min depois do início"* && "$(det login_open)" == *"Trocar de rodada"* ]]'
sed -i '/^LOGIN_START_TIME=/d' "$C/conf"; printf 'LOGIN_START_TIME=%s\n' "$((NOW+4200))" >> "$C/conf"; run
check "abre DEPOIS do fim (o caso do warmup) => fail"           '[[ "$(lvl login_open)" == fail && "$(det login_open)" == *"NENHUM time entra"* ]]'
printf 'LOGIN_ENABLED=n\n' >> "$C/conf"; run
check "login desligado em Regras => warn (vence a abertura)"   '[[ "$(lvl login_open)" == warn && "$(det login_open)" == *"nenhum time entra"* ]]'
sed -i '/^LOGIN_START_TIME=/d; /^LOGIN_ENABLED=/d' "$C/conf"
cp "$C/conf" "$FIX/conf.bak"; sed -i "s/^CONTEST_START=.*/CONTEST_START=$((NOW-7200))/; s/^CONTEST_END=.*/CONTEST_END=$((NOW-3600))/" "$C/conf"
printf 'LOGIN_START_TIME=%s\n' "$((NOW+4200))" >> "$C/conf"; run
check "rodada já encerrada => sem o item (nada a avisar)"      '[[ "$(lvl login_open)" == "(ausente)" ]]'
cp "$FIX/conf.bak" "$C/conf"

echo "== envios na fila: a PRIORIDADE decide o teto (submit_cap) =="
run
check "icpc SEM prioridade (nunca escolhida) => warn com o teto 3"  '[[ "$(lvl submit_cap)" == warn && "$(det submit_cap)" == *"no máximo 3 envios"* && "$(det submit_cap)" == *"prioridade Prova em Regras"* ]]'
printf 'CONTEST_PRIORITY=lista-publica\n' >> "$C/conf"; run
check "lista-publica explícita => ok (configuração deliberada)"   '[[ "$(lvl submit_cap)" == ok && "$(det submit_cap)" == *"no máximo 3 envios"* ]]'
printf 'SUBMIT_MAX_INFLIGHT=0\n' >> "$C/conf"; run
check "SUBMIT_MAX_INFLIGHT=0 => ok sem teto"                       '[[ "$(lvl submit_cap)" == ok && "$(det submit_cap)" == *"SUBMIT_MAX_INFLIGHT=0"* ]]'
sed -i '/^CONTEST_PRIORITY=/d; /^SUBMIT_MAX_INFLIGHT=/d' "$C/conf"; printf 'CONTEST_PRIORITY=prova\n' >> "$C/conf"; run
check "prova => ok sem teto, menos prioridade a partir do 6º"      '[[ "$(lvl submit_cap)" == ok && "$(det submit_cap)" == *"6º"* ]]'
sed -i '/^CONTEST_PRIORITY=/d' "$C/conf"

echo "== trilíngue: todo item de toda execução acima leva en + es (sem português) =="
I18N_NSEEN="$(tr ' ' '\n' <<<"$I18N_SEEN" | sed '/^$/d' | sort -u | wc -l)"
check "varredura cobriu muitos ids (>= 25 distintos; viu $I18N_NSEEN)" '(( I18N_NSEEN >= 25 ))'
check "nenhum item sem label_en/detail_en/label_es/detail_es ou com PT no en/es" '[[ -z "${I18N_BAD// /}" ]] || { echo "      ids: $(tr " " "\n" <<<"$I18N_BAD" | sed "/^$/d" | sort | uniq -c | tr "\n" " ")"; false; }'

echo ""; echo "RESULT: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
