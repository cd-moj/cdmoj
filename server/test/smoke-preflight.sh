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
run(){ OUT="$(PATH_INFO="/contest/admin/preflight" REQUEST_METHOD=GET QUERY_STRING="contest=$CONTEST" \
  HTTP_AUTHORIZATION="Bearer $TOKEN" \
  CONTESTSDIR="$FIX" SESSIONDIR="$SESS" SPOOLDIR="$SPOOL" REGISTRYDIR="$REG" RUNDIR="$RUN" \
  bash "$ROUTER" <<<'' 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
lvl(){ printf '%s' "$BODY" | jq -r --arg i "$1" 'first(.checks[]|select(.id==$i)|.level) // "(ausente)"'; }
det(){ printf '%s' "$BODY" | jq -r --arg i "$1" 'first(.checks[]|select(.id==$i)|.detail) // ""'; }

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

echo "== gate sem NENHUMA configuração = desligado (não é fail falso) =="
mv "$C/ua-gate.json" "$C/ua-gate.json.bak"; run
check "sem ua-gate.json => ok"           '[[ "$(lvl ua_gate)" == ok ]]'
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

echo ""; echo "RESULT: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
