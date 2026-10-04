#!/bin/bash
# NOME DO PROBLEMA NO IDIOMA DA PROVA (03/10/2026). TCP 2026 (`LOCALE=es`): os nomes nasciam com o título
# PT do banco e a sanfona mostrava "Problema em português" sobre o enunciado em espanhol. Hoje:
#   - o nome PADRÃO (spec/inclusão/rodada sem `name`) é o título do banco no idioma em que a sanfona abre
#     (cs_default sobre STATEMENT_LANGS/LOCALE), senão o PT — cc_prob_title/cc_prob_lang;
#   - as listas de busca/sorteio trazem `titles` {pt,en,es} quando há tradução (as opções da tela);
#   - GET /contest/admin/problems traz `titles` + `name_lang`;
#   - a Central acusa nome = título do banco em OUTRO idioma (prob_names) e o botão o troca
#     (apply_titles) — nunca nome personalizado nem o escolhido no Renomear.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$HERE/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" MOJ_JOBS_SYNC=1; mkdir -p "$RUN/tl"
NOW="$EPOCHSECONDS"; FUT=$((NOW + 100000)); T="$FIX/treino"; mkdir -p "$T/var/jsons" "$T/var/jsons-private"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\n' > "$T/conf"
fx_user "$T" boss.admin p "Boss"
printf 'CONTEST=treino\nLOGIN=boss.admin\nUSERFULLNAME=Boss\nLOGINAT=1\n' > "$SESS/tadm"
b64(){ printf '%s' "$1" | base64 -w0; }
# org#tri: PT/EN/ES · org#bi: PT/EN (sem ES) · org#mono: só PT · org#same: tradução com o MESMO título
jq -cn --arg h "$(b64 '<p>pt</p>')" --arg he "$(b64 '<p>en</p>')" --arg hs "$(b64 '<p>es</p>')" \
  '{id:"org#tri", title:"Corrida de Robôs", public:true, tags:["#x"], statement_html_b64:$h,
    statement_langs:["pt","en","es"],
    statements:{en:{title:"Robot Race", html_b64:$he}, es:{title:"Carrera de Robots", html_b64:$hs}}}' > "$T/var/jsons/org#tri.json"
jq -cn --arg h "$(b64 '<p>pt</p>')" --arg he "$(b64 '<p>en</p>')" \
  '{id:"org#bi", title:"Pontes", public:true, tags:["#x"], statement_html_b64:$h, statement_langs:["pt","en"],
    statements:{en:{title:"Bridges", html_b64:$he}}}' > "$T/var/jsons/org#bi.json"
jq -cn --arg h "$(b64 '<p>pt</p>')" '{id:"org#mono", title:"Soma", public:true, tags:["#x"], statement_html_b64:$h}' > "$T/var/jsons/org#mono.json"
jq -cn --arg h "$(b64 '<p>pt</p>')" --arg he "$(b64 '<p>en</p>')" \
  '{id:"org#same", title:"Pizza", public:true, tags:["#x"], statement_html_b64:$h, statements:{en:{title:"Pizza", html_b64:$he}}}' > "$T/var/jsons/org#same.json"
# privado do dono, com tradução (a busca do admin o lista com o selo; títulos vêm do jsons-private)
jq -cn --arg h "$(b64 '<p>pt</p>')" --arg hs "$(b64 '<p>es</p>')" \
  '{id:"boss#priv", title:"Segredo", public:false, tags:["#y"], statement_html_b64:$h, statements:{es:{title:"Secreto", html_b64:$hs}}}' > "$T/var/jsons-private/boss#priv.json"
printf '%s' '{"generated_at":9999999999,"problems":[
 {"id":"org#tri","title":"Corrida de Robôs","owner":"x","collaborators":[],"public":true},
 {"id":"org#bi","title":"Pontes","owner":"x","collaborators":[],"public":true},
 {"id":"org#mono","title":"Soma","owner":"x","collaborators":[],"public":true},
 {"id":"org#same","title":"Pizza","owner":"x","collaborators":[],"public":true},
 {"id":"boss#priv","title":"Segredo","owner":"boss.admin","collaborators":[],"public":false}
]}' > "$T/var/problem-owners.json"

call(){ # <path> <method> <body> <token> <query>
  OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-tadm}" bash "$ROUTER" <<<"${3:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:300}"; ((fail++)); fi; }
names(){ ( PROBS=(); source "$FIX/$1/conf"; for ((i=0; i+4<${#PROBS[@]}; i+=5)); do printf '%s=%s|' "${PROBS[i+3]}" "${PROBS[i+2]}"; done ); }
SPEC_P='[{"bank_id":"org#tri"},{"bank_id":"org#bi"},{"bank_id":"org#mono"},{"bank_id":"org#tri","name":"Meu Nome","letter":"Z"}]'

echo "== criação: o nome padrão segue o LOCALE =="
call /treino/contest-create/create POST "{\"id\":\"c-es\",\"name\":\"ES\",\"mode\":\"icpc\",\"locale\":\"es\",\"priority\":\"prova\",\"end\":$FUT,\"problems\":$SPEC_P}"
ck "create es: sucesso" '[[ "$(jq -r .success <<<"$BODY")" == true ]]'
ck "es: título ES; sem ES cai no PT; nome dado fica" '[[ "$(names c-es)" == "A=Carrera de Robots|B=Pontes|C=Soma|Z=Meu Nome|" ]]'
call /treino/contest-create/create POST "{\"id\":\"c-en\",\"name\":\"EN\",\"mode\":\"icpc\",\"locale\":\"en\",\"priority\":\"prova\",\"end\":$FUT,\"problems\":$SPEC_P}"
ck "en: Robot Race / Bridges / Soma" '[[ "$(names c-en)" == "A=Robot Race|B=Bridges|C=Soma|Z=Meu Nome|" ]]'
call /treino/contest-create/create POST "{\"id\":\"c-pt\",\"name\":\"PT\",\"mode\":\"icpc\",\"priority\":\"prova\",\"end\":$FUT,\"problems\":$SPEC_P}"
ck "sem locale = PT (como antes)" '[[ "$(names c-pt)" == "A=Corrida de Robôs|B=Pontes|C=Soma|Z=Meu Nome|" ]]'

# sessões de admin dos contests (o login de admin é local de cada contest)
for c in c-es c-en c-pt; do fx_user "$FIX/$c" "boss.admin" p Boss; printf 'CONTEST=%s\nLOGIN=boss.admin\nUSERFULLNAME=Boss\nLOGINAT=1\n' "$c" > "$SESS/a-$c"; done

echo "== inclusão (Prova › Problemas) sem nome =="
call /contest/admin/problems POST '{"action":"add","problem":{"bank_id":"org#bi"}}' a-c-en contest=c-en
ck "add em contest en: Bridges" '[[ "$(names c-en)" == *"D=Bridges|" ]]'
# STATEMENT_LANGS=pt com LOCALE=es: a sanfona abre em PT ⇒ o nome padrão é o PT
printf 'STATEMENT_LANGS=pt\n' >> "$FIX/c-es/conf"
call /contest/admin/problems POST '{"action":"add","problem":{"bank_id":"org#tri"}}' a-c-es contest=c-es
ck "STATEMENT_LANGS=pt + LOCALE=es: o nome padrão é PT" '[[ "$(names c-es)" == *"D=Corrida de Robôs|" ]]'
sed -i '/^STATEMENT_LANGS=/d' "$FIX/c-es/conf"
call /contest/admin/problems POST '{"action":"add","problem":{"bank_id":"org#mono","name":"Escolhido"}}' a-c-es contest=c-es
ck "nome dado na inclusão vale" '[[ "$(names c-es)" == *"E=Escolhido|" ]]'

echo "== GET: titles (só com mais de um) + name_lang =="
call /contest/admin/problems GET '' a-c-es contest=c-es
ck "name_lang = es" '[[ "$(jq -r .name_lang <<<"$BODY")" == es ]]'
ck "A traz titles pt/en/es" '[[ "$(jq -c ".problems[] | select(.letter==\"A\") | .titles" <<<"$BODY")" == "{\"pt\":\"Corrida de Robôs\",\"en\":\"Robot Race\",\"es\":\"Carrera de Robots\"}" ]]'
ck "C (só PT) sem titles" '[[ "$(jq -c ".problems[] | select(.letter==\"C\") | has(\"titles\")" <<<"$BODY")" == false ]]'

echo "== Central (prob_names) + apply_titles =="
# c-es com D = PT (inserido com STATEMENT_LANGS=pt) e LOCALE=es agora: D deve ser acusado; Z/E (personalizados) não
call /contest/admin/preflight GET '' a-c-es contest=c-es
ck "prob_names warn com action apply_titles" '[[ "$(jq -r ".checks[] | select(.id==\"prob_names\") | .level + \" \" + .action" <<<"$BODY")" == "warn apply_titles" ]]'
ck "…cita só o D (Z e E são personalizados)" '[[ "$(jq -r ".checks[] | select(.id==\"prob_names\") | .detail" <<<"$BODY")" == *"D Corrida de Robôs → Carrera de Robots"* && "$(jq -r ".checks[] | select(.id==\"prob_names\") | .detail" <<<"$BODY")" != *"Meu Nome"* ]]'
ck "…trilíngue" '[[ "$(jq -r ".checks[] | select(.id==\"prob_names\") | (.label_en|length>0) and (.detail_es|length>0)" <<<"$BODY")" == true ]]'
call /contest/admin/problems POST '{"action":"apply_titles"}' a-c-es contest=c-es
ck "apply_titles: D → Carrera de Robots" '[[ "$(jq -c "[.changed[] | .letter + \"=\" + .to]" <<<"$BODY")" == "[\"D=Carrera de Robots\"]" && "$(names c-es)" == *"D=Carrera de Robots|"* ]]'
ck "…personalizados intactos" '[[ "$(names c-es)" == *"Z=Meu Nome|"* && "$(names c-es)" == *"E=Escolhido|"* ]]'
call /contest/admin/problems POST '{"action":"apply_titles"}' a-c-es contest=c-es
ck "2º clique: nada a trocar (200, changed vazio)" '[[ "$OUT" != *"Status: 4"* && "$(jq -c .changed <<<"$BODY")" == "[]" ]]'
call /contest/admin/preflight GET '' a-c-es contest=c-es
ck "Central sem prob_names depois" '[[ -z "$(jq -r ".checks[] | select(.id==\"prob_names\") | .id" <<<"$BODY")" ]]'
# contest que TROCOU de idioma: c-pt vira es — os nomes PT do banco são acusados
sed -i 's/^LOCALE=.*//' "$FIX/c-pt/conf"; printf 'LOCALE=es\n' >> "$FIX/c-pt/conf"
call /contest/admin/preflight GET '' a-c-pt contest=c-pt
ck "LOCALE trocado p/ es: A acusado, B/C não (sem ES)" '[[ "$(jq -r ".checks[] | select(.id==\"prob_names\") | .detail" <<<"$BODY")" == "1 problema(s)"*"A Corrida de Robôs → Carrera de Robots"* ]]'
# nome escolhido no Renomear (mesmo sendo o PT do banco) não volta a ser acusado
call /contest/admin/problems POST '{"action":"rename","letter":"A","name":"Corrida de Robôs"}' a-c-pt contest=c-pt
call /contest/admin/preflight GET '' a-c-pt contest=c-pt
ck "renomeado de propósito: sem aviso" '[[ -z "$(jq -r ".checks[] | select(.id==\"prob_names\") | .id" <<<"$BODY")" ]]'
call /contest/admin/problems POST '{"action":"apply_titles"}' a-c-pt contest=c-pt
ck "…e o apply_titles não o toca" '[[ "$(names c-pt)" == "A=Corrida de Robôs|"* ]]'

echo "== reescrever a lista NÃO apaga o enunciado enviado à mão (CC_KEEP_STATEMENTS; auditoria 03/10) =="
call /contest/admin/problems POST "{\"action\":\"statement\",\"letter\":\"B\",\"html_b64\":\"$(b64 '<p>MEU PT</p>')\"}" a-c-pt contest=c-pt
call /contest/admin/problems POST "{\"action\":\"statement\",\"letter\":\"A\",\"lang\":\"es\",\"html_b64\":\"$(b64 '<p>MI ES</p>')\"}" a-c-pt contest=c-pt
call /contest/admin/problems POST '{"action":"rename","letter":"C","name":"Outro"}' a-c-pt contest=c-pt
call /contest/admin/problems POST '{"action":"apply_titles"}' a-c-pt contest=c-pt
call /contest/admin/problems POST '{"action":"add","problem":{"bank_id":"org#same"}}' a-c-pt contest=c-pt
ck "rename/apply_titles/add mantêm o HTML PT enviado" 'grep -q "MEU PT" "$FIX/c-pt/enunciados/org#bi.html"'
ck "…e a tradução enviada" 'grep -q "MI ES" "$FIX/c-pt/enunciados/org#tri.es.html"'
ck "…e o problema novo baixa o enunciado do banco" '[[ -s "$FIX/c-pt/enunciados/org#same.html" ]]'
# trocar SÓ a letra (a tela manda o nome junto) não registra o nome como escolhido
sed -i 's/^LOCALE=.*//' "$FIX/c-en/conf"; printf 'LOCALE=es\n' >> "$FIX/c-en/conf"
call /contest/admin/problems POST '{"action":"rename","letter":"D","name":"Bridges","new_letter":"Q"}' a-c-en contest=c-en
call /contest/admin/preflight GET '' a-c-en contest=c-en
ck "trocar só a letra não silencia o aviso (Bridges ≠ título ES? sem ES ⇒ fica sem aviso)" '[[ -z "$(jq -r ".checks[] | select(.id==\"prob_names\") | .detail" <<<"$BODY" | grep -o "Q Bridges")" ]]'
call /contest/admin/problems POST '{"action":"rename","letter":"A","name":"Robot Race","new_letter":"R"}' a-c-en contest=c-en
call /contest/admin/preflight GET '' a-c-en contest=c-en
ck "renomear só a letra de um nome EN em prova ES: segue acusado" '[[ "$(jq -r ".checks[] | select(.id==\"prob_names\") | .detail" <<<"$BODY")" == *"R Robot Race → Carrera de Robots"* ]]'
call /contest/admin/problems POST '{"action":"rename","letter":"R","name":"Robot Race","new_letter":"A"}' a-c-en contest=c-en
sed -i '/^LOCALE=es$/d' "$FIX/c-en/conf"; printf 'LOCALE=en\n' >> "$FIX/c-en/conf"

echo "== reparo do /contest/problems (nome == id) no idioma da sanfona =="
fx_user "$FIX/c-en" time1 s T1; printf 'CONTEST=c-en\nLOGIN=time1\nUSERFULLNAME=T\nLOGINAT=1\n' > "$SESS/t-en"
sed -i 's/^CONTEST_START=.*//' "$FIX/c-en/conf"; printf 'CONTEST_START=%s\n' "$((NOW-60))" >> "$FIX/c-en/conf"
python3 - "$FIX/c-en/conf" <<'EOF'
import sys,re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r"Robot\\? Race", "org\\#tri", s, count=1)
open(p,'w').write(s)
EOF
call /contest/problems GET '' t-en contest=c-en
ck "nome == id ⇒ título EN (LOCALE=en)" '[[ "$(jq -r ".problems[] | select(.short_name==\"A\") | .full_name" <<<"$BODY")" == "Robot Race" ]]'

echo "== listas de busca/sorteio: titles nos itens com tradução =="
call /contest/admin/bank GET '' a-c-es "contest=c-es&q=&limit=30"
ck "busca do admin: org#tri com titles; org#mono sem" '[[ "$(jq -r ".problems[] | select(.id==\"org#tri\") | .titles.es" <<<"$BODY")" == "Carrera de Robots" && "$(jq -r ".problems[] | select(.id==\"org#mono\") | has(\"titles\")" <<<"$BODY")" == false ]]'
ck "…mesmo título nos dois idiomas = sem escolha (sem titles)" '[[ "$(jq -r ".problems[] | select(.id==\"org#same\") | has(\"titles\")" <<<"$BODY")" == false ]]'
ck "…privado do dono com os títulos do jsons-private" '[[ "$(jq -r ".problems[] | select(.id==\"boss#priv\") | .titles.es" <<<"$BODY")" == "Secreto" ]]'
call /contest/admin/draw GET '' a-c-es "contest=c-es&tags=%23x&count=10"
ck "sorteio do admin: titles no org#tri" '[[ "$(jq -r ".problems[] | select(.id==\"org#tri\") | .titles.en" <<<"$BODY")" == "Robot Race" ]]'
call /treino/contest-create/problems GET '' tadm "q=&limit=30"
ck "busca do assistente: titles no org#bi" '[[ "$(jq -r ".problems[] | select(.id==\"org#bi\") | .titles.en" <<<"$BODY")" == "Bridges" && "$(jq -r .success <<<"$BODY")" == true ]]'
call /treino/contest-create/draw GET '' tadm "tags=%23x&count=10"
ck "sorteio do assistente: titles no org#tri" '[[ "$(jq -r ".problems[] | select(.id==\"org#tri\") | .titles.es" <<<"$BODY")" == "Carrera de Robots" ]]'

echo "== rodada: lista sem nome entra no ar com o nome no idioma da prova =="
( source "$ROOT/api/v1/lib/common.sh" >/dev/null 2>&1; source "$ROOT/api/v1/lib/contest-create.sh"
  cc_set_probs c-en '[{"bank_id":"org#tri","letter":"W1"},{"bank_id":"org#bi","letter":"W2"}]' )
ck "cc_set_probs (troca de rodada) em en: Robot Race / Bridges" '[[ "$(names c-en)" == "W1=Robot Race|W2=Bridges|" ]]'

echo; echo "RESULT: $pass passed, $fail failed"; (( fail == 0 ))
