#!/bin/bash
# Rodadas (Evento › Rodadas): problema da rodada segue a permissão do DONO do contest (público,
# dono, colaborador, membro da org — problems_denied_for), cores de balão POR RODADA (`colors`),
# promoção aplica as cores da rodada que entra (sem cores = herda), guarda do freeze
# (descongelar só a partir do fim geral + 1 min, prorrogações incluídas, em todos os caminhos).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; SPOOL="$(mktemp -d)"; RUN="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$SPOOL" "$RUN"' EXIT
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" SPOOLDIR="$SPOOL" SCOREDIR="$ROOT/score" RUNDIR="$RUN"
export JUDGED_ALIVE_FILE="$RUN/judged.alive"
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
T="$FIX/treino"; mkdir -p "$T/var/jsons" "$T/var/jsons-private"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\n' > "$T/conf"
fx_user "$T" regular s "Regular"
fx_user "$T" eve s "Eve"
printf '{"threshold":0,"allow":["regular"],"deny":[]}' > "$T/var/contest-perms.json"
printf 'CONTEST=treino\nLOGIN=regular\nUSERFULLNAME=Regular\nLOGINAT=1\n' > "$SESS/reg"
# org "myorg": regular é membro (não dono do problema)
echo '{"myorg":{"members":["regular"],"admins":["eve"],"created_by":"eve","title":"My Org","public_allowed":false}}' > "$T/var/orgs.json"
for p in bankprob priv#mine priv#collab priv#other myorg#p; do
  printf '{"id":"%s","title":"%s","statement_html_b64":"PHA+czwvcD4="}' "$p" "$p" > "$T/var/jsons-private/$p.json"
done
printf '{"id":"bankprob","title":"Banco","tags":[],"statement_html_b64":"PHA+czwvcD4="}' > "$T/var/jsons/bankprob.json"
printf '%s' '{"problems":[
 {"id":"bankprob","title":"Banco","owner":"someone","collaborators":[],"public":true},
 {"id":"priv#mine","title":"Meu","owner":"regular","collaborators":[],"public":false},
 {"id":"priv#collab","title":"Colab","owner":"eve","collaborators":["regular"],"public":false},
 {"id":"priv#other","title":"Alheio","owner":"eve","collaborators":[],"public":false},
 {"id":"myorg#p","title":"Da org","owner":"eve","collaborators":[],"public":false,"repo":"myorg"}
]}' > "$T/var/problem-owners.json"
NOW="$(date +%s)"; FUT=$(( NOW + 100000 ))
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-reg}" \
    bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
J(){ jq -r "$1" <<<"$BODY" 2>/dev/null; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:240}"; ((fail++)); fi; }

SPEC="{\"id\":\"rd-c\",\"name\":\"Rodadas\",\"mode\":\"icpc\",\"start\":$((NOW-7200)),\"end\":$FUT,\"admin\":{\"login\":\"boss\",\"password\":\"sek\",\"fullname\":\"Boss\"},\"problems\":[{\"bank_id\":\"bankprob\",\"name\":\"P1\",\"letter\":\"A\"}]}"
call /treino/contest-create/create POST "$SPEC" reg
[[ "$(J .admin_login)" == boss.admin ]] || { echo "SETUP FAIL: $BODY"; exit 1; }
C="$FIX/rd-c"
printf 'CONTEST=rd-c\nLOGIN=boss.admin\nUSERFULLNAME=Boss\nLOGINAT=1\n' > "$SESS/cadm"
fx_user "$C" chefe.cjudge x "Chefe"
printf 'CONTEST=rd-c\nLOGIN=chefe.cjudge\nUSERFULLNAME=Chefe\nLOGINAT=1\n' > "$SESS/cjud"
Q='contest=rd-c'
RD(){ call /contest/admin/rounds POST "$1" cadm "$Q"; }

echo "== rodada planejada: problemas seguem a permissão do DONO do contest =="
RD "{\"action\":\"add\",\"slug\":\"prova\",\"name\":\"Prova\",\"start\":$((NOW+3600)),\"end\":$((NOW+7200))}"
ck "add planejada" '[[ "$(J .saved)" == true ]]'
RD '{"action":"problems","slug":"prova","problems":[{"bank_id":"bankprob","letter":"A"}]}'
ck "público entra"                 '[[ "$(J .n)" == 1 ]]'
RD '{"action":"problems","slug":"prova","problems":[{"bank_id":"priv#mine","letter":"A"}]}'
ck "privado do dono entra"         '[[ "$(J .n)" == 1 ]]'
RD '{"action":"problems","slug":"prova","problems":[{"bank_id":"priv#collab","letter":"A"}]}'
ck "privado com dono colaborador entra" '[[ "$(J .n)" == 1 ]]'
RD '{"action":"problems","slug":"prova","problems":[{"bank_id":"myorg#p","letter":"A"},{"problem_id":"priv/mine","letter":"B"}]}'
ck "privado da ORG do dono entra (id com / também)" '[[ "$(J .n)" == 2 ]]'
RD '{"action":"problems","slug":"prova","problems":[{"bank_id":"bankprob","letter":"A"},{"bank_id":"priv#other","letter":"B"}]}'
ck "privado alheio: 404 problem_denied (existência não vaza)" '[[ "$OUT" == *"Status: 404"* && "$(J .error.code)" == problem_denied ]]'
ck "e NÃO lista o id negado"       '[[ "$(J .error.message)" != *"priv#other"* ]]'
call /contest/admin/rounds GET '' cadm "$Q"
ck "rodada planejada ficou com os 2 (org + dono)" '[[ "$(J ".rounds[] | select(.slug==\"prova\") | .problems | length")" == 2 ]]'
# privado alheio que entrou por OUTRA porta (spec unificado/duplicate/arquivo): a promoção barra,
# e é DURO — o force não passa (é a última porta antes de materializar o enunciado do jsons-private)
jq -c '.rounds |= map(if .slug=="prova" then .problems += [{"bank_id":"priv#other","letter":"Z"}] else . end)' "$C/rounds.json" > "$C/rounds.json.t" && mv -f "$C/rounds.json.t" "$C/rounds.json"
call /contest/admin/rounds GET '' cadm "$Q"
ck "promoção bloqueada por problem_denied" '[[ "$(J ".promote_ready.blockers | map(.code) | index(\"problem_denied\")")" != null ]]'
RD '{"action":"promote","to":"prova","force":true}'
ck "force NÃO passa por cima do problem_denied" '[[ "$OUT" == *"Status: 409"* && "$(J ".blockers | map(.code) | index(\"problem_denied\")")" != null ]]'
ck "e nada foi materializado do privado alheio" '[[ ! -f "$C/enunciados/priv#other.html" ]]'
jq -c '.rounds |= map(if .slug=="prova" then .problems |= map(select(.bank_id != "priv#other")) else . end)' "$C/rounds.json" > "$C/rounds.json.t" && mv -f "$C/rounds.json.t" "$C/rounds.json"

echo "== rodada ATIVA: mesma regra, e vai pro conf =="
call /contest/admin/rounds GET '' cadm "$Q"
ACT="$(J .active)"
ck "ativa é a implícita 'oficial'"  '[[ "$ACT" == oficial ]]'
RD '{"action":"problems","slug":"oficial","problems":[{"bank_id":"myorg#p","name":"Org","letter":"A"},{"bank_id":"bankprob","name":"Pub","letter":"B"}]}'
ck "org entra na ativa"            '[[ "$(J .n)" == 2 ]]'
ck "PROBS do conf tem os dois"     'grep -q "myorg#p" "$C/conf" && grep -q "bankprob" "$C/conf"'
RD '{"action":"problems","slug":"oficial","problems":[{"bank_id":"priv#other","letter":"A"}]}'
ck "alheio na ativa: 404"          '[[ "$OUT" == *"Status: 404"* ]]'
ck "conf intacto"                  'grep -q "myorg#p" "$C/conf"'
cp "$C/owner" "$C/owner.bak"; rm -f "$C/owner"
RD '{"action":"problems","slug":"prova","problems":[{"bank_id":"priv#mine","letter":"A"}]}'
ck "contest sem owner: privado 404" '[[ "$OUT" == *"Status: 404"* ]]'
RD '{"action":"problems","slug":"prova","problems":[{"bank_id":"bankprob","letter":"A"}]}'
ck "contest sem owner: público ok" '[[ "$(J .n)" == 1 ]]'
mv "$C/owner.bak" "$C/owner"

echo "== cores de balão POR RODADA =="
RD '{"action":"set","slug":"prova","colors":{"A":"112233","B":"GGGGGG"}}'
ck "hex inválido 422"              '[[ "$OUT" == *"Status: 422"* && "$(J .error.code)" == colors_invalid ]]'
RD '{"action":"set","slug":"prova","colors":{"abc":"112233"}}'
ck "chave inválida 422"            '[[ "$OUT" == *"Status: 422"* ]]'
RD '{"action":"set","slug":"prova","colors":[1]}'
ck "array 422"                     '[[ "$OUT" == *"Status: 422"* ]]'
RD '{"action":"set","slug":"prova","colors":{"A":"112233","enableSonic":true}}'
ck "set colors na planejada"       '[[ "$(J .round.colors.A)" == 112233 && "$(J .round.colors.enableSonic)" == true ]]'
ck "planejada NÃO mexe no balloons.json" '[[ ! -e "$C/balloons.json" ]]'
RD '{"action":"set","slug":"prova","colors":{}}'
ck "{} não mexe"                   '[[ "$(J .round.colors.A)" == 112233 ]]'
call /contest/admin/rounds GET '' cadm "$Q"
ck "GET devolve as cores da planejada" '[[ "$(J ".rounds[] | select(.slug==\"prova\") | .colors.A")" == 112233 ]]'
ck "ativa sem cores próprias (sem balloons.json)" '[[ "$(J ".rounds[] | select(.slug==\"oficial\") | has(\"colors\")")" == false ]]'
call /contest/balloons GET '' cadm "$Q"
ck "/contest/balloons ainda padrão"  '[[ "$(J .balloons.A)" == FFFFFF ]]'
RD '{"action":"set","slug":"oficial","colors":{"A":"ABCDEF","B":"000001"}}'
ck "set colors na ATIVA grava o balloons.json" '[[ "$(jq -r .A "$C/balloons.json")" == ABCDEF ]]'
ck "módulo baloes ligou"           'grep -q "^CONTEST_MODULES=.*baloes" "$C/conf"'
call /contest/balloons GET '' cadm "$Q"
ck "/contest/balloons vê a cor nova (cache derrubado)" '[[ "$(J .balloons.A)" == ABCDEF ]]'
call /contest/admin/rounds GET '' cadm "$Q"
ck "ativa espelha o balloons.json" '[[ "$(J ".rounds[] | select(.slug==\"oficial\") | .colors.A")" == ABCDEF ]]'
call /contest/admin/config POST '{"colors":{"A":"0000FF","B":"000001"}}' cadm "$Q"
call /contest/admin/rounds GET '' cadm "$Q"
ck "Evento › Balões e a rodada ativa são a MESMA coisa" '[[ "$(J ".rounds[] | select(.slug==\"oficial\") | .colors.A")" == 0000FF ]]'
RD '{"action":"set","slug":"prova","colors":null}'
ck "null remove as cores da planejada" '[[ "$(J ".round | has(\"colors\")")" == false ]]'
call /contest/admin/rounds GET '' cjud "$Q"
ck "juiz-chefe lê (readOnly)"      '[[ "$(J .active)" == oficial ]]'
call /contest/admin/rounds POST '{"action":"set","slug":"prova","colors":{"A":"112233"}}' cjud "$Q"
ck "juiz-chefe não escreve (403)"  '[[ "$OUT" == *"Status: 403"* ]]'

echo "== promoção: rodada COM cores troca o balloons.json; SEM cores herda =="
# rodada ativa encerrada, fila vazia, daemon vivo
sed -i "s/^CONTEST_END=.*/CONTEST_END=$((NOW-7200))/" "$C/conf"
grep -q '^CONTEST_END=' "$C/conf" || printf 'CONTEST_END=%s\n' "$((NOW-7200))" >> "$C/conf"
: > "$RUN/judged.alive"
RD '{"action":"set","slug":"prova","colors":{"A":"AA0000","enableSonic":false}}'
mkdir -p "$C/docs"; printf '%%PDF-enviado' > "$C/docs/info-sheet.pt.uploaded.pdf"; printf '%%PDF-gerado' > "$C/docs/info-sheet.pt.pdf"
RD '{"action":"promote","to":"prova"}'
ck "promoveu"                      '[[ "$(J .promoted)" == true ]]'
ck "PDF ENVIADO (config à mão) volta após a promoção; o gerado fica só no arquivo" '[[ -f "$C/docs/info-sheet.pt.uploaded.pdf" && ! -f "$C/docs/info-sheet.pt.pdf" && -f "$C/rounds/oficial/docs/info-sheet.pt.pdf" ]]'
ck "balloons.json = cores da rodada que entrou" '[[ "$(jq -r .A "$C/balloons.json")" == AA0000 ]]'
ck "arquivo da rodada que saiu guardou as cores dela" '[[ "$(jq -r .A "$C/rounds/oficial/balloons.json")" == 0000FF ]]'
call /contest/balloons GET '' cadm "$Q"
ck "/contest/balloons serve a cor nova" '[[ "$(J .balloons.A)" == AA0000 && "$(J .balloons.enableSonic)" == false ]]'
# terceira rodada, sem cores: herda
RD "{\"action\":\"add\",\"slug\":\"extra\",\"name\":\"Extra\",\"kind\":\"extra\",\"start\":$((NOW+3600)),\"end\":$((NOW+7200))}"
sed -i "s/^CONTEST_END=.*/CONTEST_END=$((NOW-7200))/" "$C/conf"
RD '{"action":"promote","to":"extra"}'
ck "promoveu p/ a extra"           '[[ "$(J .promoted)" == true ]]'
ck "sem cores próprias: herdou"    '[[ "$(jq -r .A "$C/balloons.json")" == AA0000 ]]'
call /contest/admin/rounds GET '' cadm "$Q"
ck "ativa (extra) espelha as herdadas" '[[ "$(J ".rounds[] | select(.slug==\"extra\") | .colors.A")" == AA0000 ]]'
ck "arquivada 'prova' mantém as cores no plano (auditoria)" '[[ "$(J ".rounds[] | select(.slug==\"prova\") | .colors.A")" == AA0000 ]]'

echo "== export/create round-trip leva colors =="
RD "{\"action\":\"add\",\"slug\":\"final\",\"name\":\"Final\",\"start\":$((NOW+9000)),\"end\":$((NOW+12000))}"
RD '{"action":"set","slug":"final","colors":{"A":"123456"}}'
call /treino/contest-create/export GET '' reg 'id=rd-c'
ck "export tem colors da planejada" '[[ "$(J ".modules.rodadas.rounds[] | select(.slug==\"final\") | .colors.A")" == 123456 ]]'
EXP="$(jq -c '. + {id:"rd-d", name:"Copia", admin:{login:"boss2",password:"sek",fullname:"B"}} | del(.success)' <<<"$BODY")"
call /treino/contest-create/create POST "$EXP" reg
ck "create a partir do export"     '[[ "$(J .admin_login)" == boss2.admin ]]'
ck "rounds.json da cópia tem colors" '[[ "$(jq -r ".rounds[] | select(.slug==\"final\") | .colors.A" "$FIX/rd-d/rounds.json")" == 123456 ]]'

echo "== guarda do freeze: descongelar só a partir do fim geral + 1 min =="
# nova rodada planejada + ativa (extra) congelada, terminando em 30 s; sede prorrogada até +20 min
RD "{\"action\":\"add\",\"slug\":\"prox\",\"name\":\"Prox\",\"start\":$((NOW+9000)),\"end\":$((NOW+12000))}"
sed -i "s/^CONTEST_START=.*/CONTEST_START=$((NOW-7200))/; s/^CONTEST_END=.*/CONTEST_END=$((NOW-30))/" "$C/conf"
grep -q '^FREEZE_TIME=' "$C/conf" && sed -i "s/^FREEZE_TIME=.*/FREEZE_TIME=$((NOW-3600))/" "$C/conf" || printf 'FREEZE_TIME=%s\n' "$((NOW-3600))" >> "$C/conf"
call /contest/admin/settings POST '{"freeze":0}' cadm "$Q"
ck "fim há 30 s: settings freeze:0 -> 409 freeze_locked" '[[ "$OUT" == *"Status: 409"* && "$(J .error.code)" == freeze_locked ]]'
ck "conf segue congelado"          'grep -q "^FREEZE_TIME=$((NOW-3600))$" "$C/conf"'
call /contest/admin/settings POST "{\"freeze\":$((NOW-1800))}" cadm "$Q"
ck "mudar o freeze p/ outro >0 passa" '[[ "$(J .saved)" == true ]] && grep -q "^FREEZE_TIME=$((NOW-1800))$" "$C/conf"'
call /contest/admin/config POST '{"basic":{"freeze":0}}' cadm "$Q"
ck "config basic.freeze:0 -> 409"  '[[ "$OUT" == *"Status: 409"* && "$(J .error.code)" == freeze_locked ]]'
# 5º caminho: editar a rodada ATIVA com freeze:0 (ou "00", ou empurrar o freeze em vigor p/ o
# futuro) é descongelar também — mesma guarda
call /contest/admin/rounds GET '' cadm "$Q"; ACTS="$(J .active)"
RD "{\"action\":\"set\",\"slug\":\"$ACTS\",\"freeze\":0}"
ck "rounds set freeze:0 na ativa -> 409 freeze_locked" '[[ "$OUT" == *"Status: 409"* && "$(J .error.code)" == freeze_locked ]]'
call /contest/admin/settings POST '{"freeze":"00"}' cadm "$Q"
ck "settings freeze:\"00\" -> 409 (comparação numérica)" '[[ "$OUT" == *"Status: 409"* && "$(J .error.code)" == freeze_locked ]]'
call /contest/admin/settings POST "{\"freeze\":$((NOW+600))}" cadm "$Q"
ck "freeze em vigor empurrado p/ o futuro -> 409" '[[ "$OUT" == *"Status: 409"* && "$(J .error.code)" == freeze_locked ]]'
ck "FREEZE_TIME intacto"           'grep -q "^FREEZE_TIME=$((NOW-1800))$" "$C/conf"'
call /contest/admin/finish POST '{"action":"finish"}' cadm "$Q"
ck "Encerrar evento -> 409 freeze_locked" '[[ "$OUT" == *"Status: 409"* && "$(J .error.code)" == freeze_locked ]]'
call /contest/admin/finish GET '' cadm "$Q"
ck "checklist: can_finish false + freeze_release_at = fim+60" '[[ "$(J .can_finish)" == false && "$(J .freeze_release_at)" == '"$((NOW-30+60))"' ]]'
call /contest/admin/settings GET '' cadm "$Q"
ck "settings expõe freeze_release_at" '[[ "$(J .freeze_release_at)" == '"$((NOW+30))"' ]]'
call /contest/admin/rounds GET '' cadm "$Q"
ck "promoção bloqueada por freeze_locked" '[[ "$(J ".promote_ready.blockers | map(.code) | index(\"freeze_locked\")")" != null ]]'
RD '{"action":"promote","to":"prox","force":true}'
ck "force NÃO passa por cima"      '[[ "$OUT" == *"Status: 409"* && "$(J ".blockers | map(.code) | join(\",\")")" == freeze_locked ]]'
# sede prorrogada empurra o mínimo: fim geral = +20 min
printf '[{"regex":"^sede1-","end":%s}]' "$((NOW+1200))" > "$C/time-overrides.json"
sed -i "s/^CONTEST_END=.*/CONTEST_END=$((NOW-7200))/" "$C/conf"
call /contest/admin/settings GET '' cadm "$Q"
ck "prorrogação empurra o mínimo (fim da sede + 60)" '[[ "$(J .freeze_release_at)" == '"$((NOW+1260))"' ]]'
call /contest/admin/settings POST '{"freeze":0}' cadm "$Q"
ck "com sede prorrogada: 409"      '[[ "$OUT" == *"Status: 409"* ]]'
rm -f "$C/time-overrides.json"
# agora sim: fim há 2 h
call /contest/admin/settings POST '{"freeze":0}' cadm "$Q"
ck "fim há 2 h: descongela"        '[[ "$(J .saved)" == true ]] && grep -q "^FREEZE_TIME=0$" "$C/conf"'
call /contest/admin/settings POST '{"freeze":0}' cadm "$Q"
ck "sem freeze em vigor: 0 de novo passa (idempotente)" '[[ "$(J .saved)" == true ]]'
sed -i "s/^FREEZE_TIME=.*/FREEZE_TIME=$((NOW-3600))/" "$C/conf"
call /contest/admin/rounds GET '' cadm "$Q"
ck "promoção liberada (freeze ok)" '[[ "$(J ".promote_ready.blockers | map(.code) | index(\"freeze_locked\")")" == null ]]'
call /contest/admin/finish POST '{"action":"finish"}' cadm "$Q"
ck "Encerrar evento passa"         '[[ "$OUT" == *"Status: 200"* ]] && grep -q "^FREEZE_TIME=0$" "$C/conf"'

echo "RESULT: $pass passed, $fail failed"; [[ $fail -eq 0 ]]
