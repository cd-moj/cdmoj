#!/bin/bash
# smoke-open-training.sh — GET /index/open_training (vitrine ANÔNIMA da home do treino).
#
# XIV Maratona UnB (25/09/2026): a regeneração do cache rodava ~130 jq (título, nome, perfil e objeto POR
# item) e o visitante que chegasse com o cache vencido esperava ~1 s. Agora: o bash seleciona, três jq
# montam; e com cache (mesmo vencido) ninguém espera — a regeneração vai destacada. Prende:
#   · privacidade: problema privado e perfil privado fora das listas; conta GERIDA de MENOR fora mesmo com
#     `public:true` (nas DUAS listas — o top10 antigo olhava só o `public`);
#   · títulos: índice vivo → legado (questoes/<p>/title) → o id com o 1º '#' virando '.'; quebra de linha
#     final comida (como o `$(…)` antigo); url com %23; nome de conta corrompida = "" e o perfil conta público;
#   · top10 pula os privados e corta em 10; recent em 5, dos mais novos;
#   · nº de jq não cresce com o nº de itens (≤ 12; o código antigo rodava 112 aqui);
#   · cache VENCIDO: a resposta sai NA HORA com o cache velho, mesmo com a regeneração lenta (medido pelo
#     `$(…)`, que espera o stdout FECHAR como o fcgiwrap — pega o setsid que herda o socket), e o cache novo
#     chega depois; sem cache nenhum, a 1ª resposta espera e já vem completa.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; RUN="$(mktemp -d)"; SHIM="$(mktemp -d)"; trap 'rm -rf "$FIX" "$RUN" "$SHIM"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
T="$FIX/treino"; mkdir -p "$T/var/jsons" "$T/var/jsons-private" "$T/var/questoes/leg#old"
printf 'CONTEST_ID=treino\nCONTEST_NAME="Treino"\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\n' > "$T/conf"
NOW=$EPOCHSECONDS; OLD=$((NOW - 30*86400))
LASTWEEK="$(TZ="${MOJ_TZ:-America/Sao_Paulo}" date --date='last-sunday' +%s)"; PREV=$((LASTWEEK - 2*86400))   # o fuso da API, não o do shell
for i in 1 3 4 5 6 7 8; do jq -n --arg t "P$i" '{title:$t}' > "$T/var/jsons/col#p$i.json"; done
jq -n '{title:"Segundo\n\n"}' > "$T/var/jsons/col#p2.json"
jq -n '{title:""}' > "$T/var/jsons/col#empty.json"
jq -n '{title:"Prova secreta"}' > "$T/var/jsons-private/col#priv.json"
printf 'Antigo\n' > "$T/var/questoes/leg#old/title"
for u in ana bia caio duda eva u01 u02 u03 u04 u05 u06 u07 u08; do fx_user "$T" "$u" x "Nome $u"; done
acc(){ jq -c "$2" "$T/users/$1/account.json" > "$T/x" && mv "$T/x" "$T/users/$1/account.json"; }
acc ana '.fullname="Ana Souza" | .favorite_editor="vim"'; : > "$T/users/ana/photo.png"
acc bia '.public=false'
acc caio '.public=true | .managed={birthdate:"2015-01-01"}'            # menor de idade, "vazado" p/ público
printf '{"fullname": "Duda", "pub' > "$T/users/duda/account.json"        # corrompida
acc eva '.fullname="Eva\n"'
# history por usuário: relat:prob:lang:resp:sub_epoch:subid
ac(){ printf '%s:%s:C:Accepted:%s:%s\n' "$3" "$2" "$3" "${4:-s$RANDOM$RANDOM}" >> "$T/users/$1/history"; }
bulk(){ local u="$1" n="$2" i; for ((i = 1; i <= n; i++)); do ac "$u" "col#p$i" "$OLD"; done; }
bulk ana 8; bulk bia 7; bulk caio 7; bulk duda 6; bulk eva 6; bulk u01 5; bulk u02 5; bulk u03 4; bulk u04 4
bulk u05 3; bulk u06 3; bulk u07 2; bulk u08 1
ac bia  'col#noidx' $((NOW-10)); ac caio 'leg#old'   $((NOW-20)); ac ana 'col#priv'  $((NOW-30))
ac eva  'leg#old'   $((NOW-40)); ac duda 'col#noidx' $((NOW-50)); ac ana 'col#empty' $((NOW-60))
ac u08  'col#p2'    $((NOW-70)); ac u07  'col#p8'    $((NOW-80))
ac u01 'col#p1' "$PREV" pw1; ac u02 'col#p1' "$((PREV+1))" pw2; ac u01 'col#p1' "$((PREV+2))" pw3; ac u03 'col#p2' "$((PREV+3))" pw4
printf '%s:pw1:u01:vim\n%s:pw2:u02:vim\n%s:pw4:u03:vscode\n' "$PREV" "$PREV" "$PREV" > "$T/var/editor-log"

REALJQ="$(command -v jq)"
# jq falso: conta as chamadas; com $SHIM/slow presente, o 1º jq da REGENERAÇÃO destacada (MOJ_OT_REGEN) dorme 3 s
printf '#!/bin/bash\necho x >> "%s/n"\n[[ -n "${MOJ_OT_REGEN:-}" ]] && rm "%s/slow" 2>/dev/null && sleep 3\nexec "%s" "$@"\n' "$SHIM" "$SHIM" "$REALJQ" > "$SHIM/jq"; chmod +x "$SHIM/jq"
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:-${BODY:0:400}}"; ((fail++)); fi; }
call(){ : > "$SHIM/n"; local s=$EPOCHREALTIME
  OUT="$(PATH="$SHIM:$PATH" PATH_INFO=/index/open_training REQUEST_METHOD=GET QUERY_STRING= CONTESTSDIR="$FIX" RUNDIR="$RUN" \
         bash "$ROUTER" </dev/null 2>/dev/null)"
  MS=$(( (${EPOCHREALTIME/./} - ${s/./}) / 1000 )); NJ=$(wc -l < "$SHIM/n")
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
J(){ printf '%s' "$BODY" | "$REALJQ" -r "$1" 2>/dev/null; }

echo "== sem cache: gera na hora =="
call; DBG=""
ck "200 com as 5 listas" '[[ "$(J .success)" == true && "$(J "[.top_users,.recent_solved,.most_solved_week,.most_solved_prev_week]|map(type)|unique|.[0]")" == array ]]'
ck "recent: os 5 mais novos, sem problema privado nem perfil privado/menor" '[[ "$(J "[.recent_solved[]|.user.username+\"@\"+.problem_id]|join(\",\")")" == "eva@leg#old,duda@col#noidx,ana@col#empty,u08@col#p2,u07@col#p8" ]]'
ck "títulos: legado, id com ponto, vazio→id, quebra final comida" '[[ "$(J "[.recent_solved[].problem_title]|join(\"|\")")" == "Antigo|col.noidx|col.empty|Segundo|P8" ]]'
ck "url com %23 e has_photo/nome da ana" '[[ "$(J ".recent_solved[]|select(.user.username==\"ana\")|[.url,.user.name,(.user.has_photo|tostring)]|join(\" \")")" == "/treino/problema/?id=col%23empty Ana Souza true" ]]'
ck "conta corrompida: nome vazio, perfil público" '[[ "$(J ".recent_solved[]|select(.user.username==\"duda\")|.user.name")" == "" ]]'
TOP="$(J "[.top_users[].username]|sort|join(\",\")")"; DBG="$TOP"
ck "top10: pula bia (privada) e caio (menor gerida), corta em 10" '[[ "$TOP" == "ana,duda,eva,u01,u02,u03,u04,u05,u06,u07" && "$(J ".top_users[0]|[.username,.favorite_editor,(.solved_count|tostring),(.has_photo|tostring)]|join(\" \")")" == "ana vim 10 true" ]]'
ck "nome com quebra final comida (eva)" '[[ "$(J ".top_users[]|select(.username==\"eva\")|.name")" == "Eva" ]]'
DBG=""
ck "semana: privado fora; noidx e leg#old com 2" '[[ "$(J "[.most_solved_week[].problem_id]|index(\"col#priv\")")" == null && "$(J ".most_solved_week[]|select(.problem_id==\"col#noidx\")|.solved_count")" == 2 && "$(J ".most_solved_week[]|select(.problem_id==\"leg#old\")|.solved_count")" == 2 ]]'
ck "semana passada: resolvedores DISTINTOS (p1 = 2) e o editor (vim 2 de 3)" '[[ "$(J ".most_solved_prev_week[]|select(.problem_id==\"col#p1\")|.solved_count")" == 2 && "$(J ".most_used_editor_prev_week|[.top.editor,(.top.count|tostring),(.total|tostring)]|join(\" \")")" == "vim 2 3" ]]'
echo "== nº de jq (contas legíveis) =="
printf '{"fullname":"Duda"}' > "$T/users/duda/account.json"; rm -f "$T/var/open-training.json"
call; DBG="$NJ jq"
ck "não cresce por item: ≤ 12 (o código antigo rodava 112 aqui)" '(( NJ <= 12 ))'; DBG=""
ck "…e com a conta consertada o nome volta" '[[ "$(J ".recent_solved[]|select(.user.username==\"duda\")|.user.name")" == Duda ]]'
cp "$T/var/open-training.json" "$RUN/v1.json"

echo "== cache vencido: serve o velho NA HORA e regenera destacado =="
ac u08 'col#p3' "$NOW" novo; ac u08 'col#p4' "$NOW" novo2         # u08 sobe (e entra no recent)
touch -d '10 minutes ago' "$T/var/open-training.json"; touch "$T/var/.score-dirty"; : > "$SHIM/slow"
call; DBG="${MS} ms"
ck "resposta em < 1,5 s com a regeneração levando 3 s+" '(( MS < 1500 ))'
ck "…e é o cache velho" '[[ "$BODY" == "$(cat "$RUN/v1.json")" ]]'
for _ in $(seq 1 100); do [[ "$T/var/open-training.json" -nt "$T/var/.score-dirty" ]] && ! cmp -s "$T/var/open-training.json" "$RUN/v1.json" && break; sleep 0.1; done
rm -f "$SHIM/slow"
ck "o cache novo chega depois (u08 no recent)" '"$REALJQ" -e "[.recent_solved[].user.username]|index(\"u08\") == 0" "$T/var/open-training.json" >/dev/null'
call; DBG=""
ck "e a próxima chamada já serve o novo" '[[ "$(J ".recent_solved[0].user.username")" == u08 ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
