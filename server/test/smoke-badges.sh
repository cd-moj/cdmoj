#!/bin/bash
# ETIQUETAS DE CREDENCIAIS (/contest/badges) — o único endpoint que RELÊ senha guardada.
#
# Nasceu do incidente de 2026-08-18: num contest com `USERS_FROM=treino` a rota varria também o
# store da FONTE e devolvia a senha em claro de ~1150 contas do treino (gente que nem se
# inscreveu), enquanto os inscritos — que têm overlay local SEM senha — saíam com etiqueta em
# branco. A regra que este teste guarda:
#
#   a etiqueta lista quem PERTENCE ao contest e imprime SÓ A SENHA QUE O CONTEST CONTROLA.
#
# Dois fixtures: `bp` (contas próprias — o caso da maratona de verdade, que NÃO pode mudar) e
# `bs` (USERS_FROM=bp + inscrição, o caso do esquenta).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"

NOW="$EPOCHSECONDS"; START=$(( NOW - 3600 )); END=$(( NOW + 3600 ))

# ---- contest P: contas PRÓPRIAS (o caso normal) ------------------------------------------
P="$FIX/bp"; mkdir -p "$P/var"
{ printf 'CONTEST_ID=bp\nCONTEST_NAME=Prova\\ Propria\nCONTEST_TYPE=icpc\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$START" "$END"
  printf "PROBS=( x col#pa Alfa A col#pa )\n"; } > "$P/conf"
fx_user "$P" bp.admin p "Admin Propria"
fx_user "$P" sede1.cstaff cs "Chefe Sede Um"
fx_user "$P" sede1.staff  st "Staff Sede Um"
fx_user "$P" aluno1 senha1 "Aluno Um"
fx_user "$P" aluno2 senha2 "Aluno Dois"
# desabilitada: o `!` do user-disable NÃO guarda a senha antiga — é uma aleatória nova. Revelá-la
# era mostrar segredo que não abre porta (e a de TIME é um !uuid interno).
fx_user "$P" aluno3 x "Aluno Tres"
jq -c '.password="!DesabilitadaXYZ"' "$P/users/aluno3/account.json" > "$P/t" && mv "$P/t" "$P/users/aluno3/account.json"
# fora-do-contest: existe SÓ no store de bp — em `bs` (que usa bp como fonte) ele é o
# "usuário do treino livre" que NUNCA pode aparecer nas etiquetas.
fx_user "$P" forasteiro segredo123 "Nunca Inscrito"

# ---- contest S: contas COMPARTILHADAS de bp + inscrição ----------------------------------
S="$FIX/bs"; mkdir -p "$S/var" "$S/print-requests"
{ printf 'CONTEST_ID=bs\nCONTEST_NAME=Prova\\ Compartilhada\nCONTEST_TYPE=icpc\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\nUSERS_FROM=bp\n' "$START" "$END"
  printf "PROBS=( x col#pa Alfa A col#pa )\n"; } > "$S/conf"
fx_user "$S" bs.admin p "Admin Compartilhada"
fx_user "$S" sede2.cstaff cs2 "Chefe Sede Dois"
# roster: aluno1 e aluno2 inscritos. O overlay local é SEM SENHA (é o que reg_materialize_login
# grava — a credencial continua sendo a da fonte).
printf '%s' '{"version":1,"teams":{"time-alfa":{"name":"Time Alfa","captain":"aluno1","members":["aluno1","aluno2"],"created_at":1}},"entries":{"aluno1":{"kind":"team","team":"time-alfa","cohort":"times","at":1},"aluno2":{"kind":"team","team":"time-alfa","cohort":"times","at":1}}}' > "$S/registrations.json"
for u in aluno1 aluno2; do
  mkdir -p "$S/users/$u"
  printf '{"login":"%s","fullname":"Aluno %s","status":"active","registered_at":%s,"team":{"cohort":"individual","region":"Norte"}}\n' \
    "$u" "$u" "$NOW" > "$S/users/$u/account.json"
done
# conta de TIME como o reg_materialize_team grava: senha "!<uuid>" (ninguém loga nela)
mkdir -p "$S/users/time-alfa"
printf '{"login":"time-alfa","fullname":"Time Alfa","password":"!11111111-2222-3333-4444-555555555555","team":{"name":"Time Alfa","cohort":"times","region":"Norte","members":["aluno1","aluno2"]}}\n' \
  > "$S/users/time-alfa/account.json"

mktok(){ printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' "$1" "$2" "$2" "$NOW" > "$SESS/$3"; }
mktok bp bp.admin      padm
mktok bp sede1.cstaff  pcst
mktok bs bs.admin      sadm
mktok bs sede2.cstaff  scst

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="${2:-GET}" QUERY_STRING="${4:-}" \
    HTTP_AUTHORIZATION="${3:+Bearer $3}" REMOTE_ADDR=127.0.0.9 \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" SCOREDIR="$ROOT/score" bash "$ROUTER" <<<"${5:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }
pw(){ jq -r --arg l "$1" '(.users[]|select(.login==$l)|.password) // "<ausente>"' <<<"$BODY"; }

echo "== contas PRÓPRIAS: a senha continua saindo (a razão de a tela existir) =="
call /contest/badges GET padm 'contest=bp'
ck "admin lista os alunos"        '[[ "$(jq -r "[.users[]|select(.login|startswith(\"aluno\"))]|length" <<<"$BODY")" == 2 ]]'
ck "senha do aluno sai"           '[[ "$(pw aluno1)" == senha1 ]] && [[ "$(pw aluno2)" == senha2 ]]'
ck "conta de papel traz a dela"   '[[ "$(pw sede1.cstaff)" == cs ]] && [[ "$(pw sede1.staff)" == st ]]'
ck "nada de shared_credential"    '[[ "$(jq -r "[.users[]|select(.shared_credential)]|length" <<<"$BODY")" == 0 ]]'
ck "envelope sem fonte"           '[[ "$(jq -r .shared <<<"$BODY")" == "" ]]'
ck "desabilitado fica fora por padrão" '! grep -q "aluno3" <<<"$BODY"'
call /contest/badges GET padm 'contest=bp&include_disabled=1'
ck "include_disabled traz o desabilitado" '[[ "$(jq -r "[.users[]|select(.login==\"aluno3\")]|length" <<<"$BODY")" == 1 ]]'
ck "…mas SEM a senha (o ! é aleatório)"  '[[ "$(pw aluno3)" == "" ]] && ! grep -q "DesabilitadaXYZ" <<<"$BODY"'
ck "…marcado disabled p/ a etiqueta"     '[[ "$(jq -r "(.users[]|select(.login==\"aluno3\")|.disabled)" <<<"$BODY")" == true ]]'
ck "quem está ativo mantém a senha"      '[[ "$(pw aluno1)" == senha1 ]]'
call /contest/badges GET pcst 'contest=bp'
ck "cstaff SEM escopo vê o contest" '[[ "$(jq -r "[.users[]|select(.login==\"aluno1\")]|length" <<<"$BODY")" == 1 ]]'

echo "== contas COMPARTILHADAS: nunca a senha da fonte, nunca quem não é do contest =="
call /contest/badges GET sadm 'contest=bs'
ck "só os inscritos entram"       '[[ "$(jq -r "[.users[]|select(.login|startswith(\"aluno\"))]|length" <<<"$BODY")" == 2 ]]'
ck "FORASTEIRO fora da lista"     '! grep -q "forasteiro" <<<"$BODY"'
ck "e a senha dele NÃO vaza"      '! grep -q "segredo123" <<<"$BODY"'
ck "senha do treino não sai"      '[[ "$(pw aluno1)" == "" ]] && ! grep -q "senha1" <<<"$BODY"'
ck "marcado shared_credential"    '[[ "$(jq -r "(.users[]|select(.login==\"aluno1\")|.shared_credential)" <<<"$BODY")" == true ]]'
ck "envelope diz a fonte"         '[[ "$(jq -r .shared <<<"$BODY")" == bp ]]'
ck "papel LOCAL mantém a senha"   '[[ "$(pw sede2.cstaff)" == cs2 ]] && [[ "$(jq -r "(.users[]|select(.login==\"sede2.cstaff\")|.shared_credential)" <<<"$BODY")" == false ]]'
call /contest/badges GET sadm 'contest=bs&include_disabled=1'
ck "include_disabled não ressuscita a fonte" '! grep -q "forasteiro" <<<"$BODY" && ! grep -q "segredo123" <<<"$BODY"'
ck "conta de TIME entra sem segredo" '[[ "$(pw time-alfa)" == "" ]] && ! grep -q "11111111-2222" <<<"$BODY"'
ck "e vem marcada desabilitada"      '[[ "$(jq -r "(.users[]|select(.login==\"time-alfa\")|.disabled)" <<<"$BODY")" == true ]]'
call /contest/badges GET scst 'contest=bs'
ck "cstaff sem escopo: só o contest" '! grep -q "forasteiro" <<<"$BODY" && [[ "$(jq -r "[.users[]|select(.login|startswith(\"aluno\"))]|length" <<<"$BODY")" == 2 ]]'
# escopo por região continua funcionando sobre o que sobrou
printf '%s' '{"sede2.cstaff":["region:Norte"]}' > "$S/print-requests/staff-filters.json"
call /contest/badges GET scst 'contest=bs'
ck "escopo region: ainda recorta" '[[ "$(jq -r "[.users[]|select(.login|startswith(\"aluno\"))]|length" <<<"$BODY")" == 2 ]] && ! grep -q "forasteiro" <<<"$BODY"'

echo "== auditoria: o tamanho da leitura fica registrado =="
ck "badges-view com n= e senhas=" 'grep -q "badges-view" "$S/var/admin-audit.log" && grep -qE "n=[0-9]+ senhas=[0-9]+" "$S/var/admin-audit.log"'
ck "1 senha só (a de papel local)" 'grep "badges-view" "$S/var/admin-audit.log" | tail -1 | grep -q "senhas=1"'
ck "e a fonte aparece no log"     'grep "badges-view" "$S/var/admin-audit.log" | tail -1 | grep -q "shared=bp"'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
