#!/bin/bash
# smoke-animeitor-api.sh — o MOJ EMPURRA o contest p/ a API do Animeitor (lib/animeitor.sh,
# /contest/animeitor/api) contra o mock ESTRITO animeitor-mock.py (escrito do OpenAPI 2.1.0 e
# conferido no serviço real). Prende: proposta de placares/sedes (regex quando reproduz o recorte do
# MOJ, lista exata quando não) · publicar é idempotente, NUNCA usa PUT e PRESERVA os salts (= os
# links de revelação) · evento alheio não é tocado sem `adopt` · runs só no DELTA, correção por id
# estável, CE→X, pendente→?, removida→X, time desconhecido não entra no sent · relógio negativo/teto ·
# credencial fora de argv/log/GET · gates · reset só com confirmação e só do que é nosso.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; MOCKD="$(mktemp -d)"; RUN="$(mktemp -d)"; MOCKPID=""
cleanup(){ [[ -n "$MOCKPID" ]] && kill "$MOCKPID" 2>/dev/null; rm -rf "$FIX" "$SESS" "$MOCKD" "$RUN"; }
trap cleanup EXIT
source "$HERE/fixture.sh"
export CONTESTSDIR="$FIX" RUNDIR="$RUN" SESSIONDIR="$SESS"

NOW="$EPOCHSECONDS"; START=$(( NOW - 7200 )); FREEZE=$(( NOW - 3600 )); END=$(( NOW + 3600 ))
C="$FIX/ap"; mkdir -p "$C/var"
{ printf 'CONTEST_ID=ap\nCONTEST_TYPE=icpc\nCONTEST_NAME=Prova\nCONTEST_START=%s\nCONTEST_END=%s\nFREEZE_TIME=%s\nPENALTY_MINUTES=20\n' "$START" "$END" "$FREEZE"
  printf "PROBS=( x col#pa Alfa A col#pa x col#pb Beta B col#pb )\n"; } > "$C/conf"
mkteam(){ fx_user "$C" "$1" x "$2" >/dev/null
  jq -c --arg n "$2" --arg u "$3" --arg r "$4" '.team = ({name:$n, univ_short:$u, flag:"br"} + (if $r == "" then {} else {region:$r} end))' \
    "$C/users/$1/account.json" > "$C/t" && mv "$C/t" "$C/users/$1/account.json"; : > "$C/users/$1/history"; }
fx_user "$C" ap.admin p Admin >/dev/null; fx_user "$C" telao.animeitor p Telao >/dev/null
fx_user "$C" sede.cstaff p Chefe >/dev/null
mkteam teambr001 "Time Um" UNB "Brasília"; mkteam teambr002 "Time Dois" UFG "Goiânia"; mkteam zeta "Zeta" UNB "Brasília"
mkteam teammx001 "Equipo Uno" UNAM ""; mkteam conv001 "Convidado" CCL "Brasília"
# Brasil: sedes por CAMPO da conta (.team.region) — não há regex que as descreva ⇒ lista exata;
# México: regex ⇒ vai o regex
jq -n '[{name:"Brasil", subregions:[{name:"Brasília"},{name:"Goiânia"}]}, {name:"México", regex:"^teammx", subregions:[{name:"CDMX", regex:"^teammx"}]}]' > "$C/regions.json"
jq -n '{version:1,cohorts:[{id:"oficial",name:"Oficiais",default:true,public:true,ranking:true},{id:"conv",name:"Convidados",regex:"^conv",public:true,unranked:true,ranking:true}]}' > "$C/cohorts.json"
{ printf '10:col#pa:C:Accepted,100p:%s:s1\n' $(( START + 600 ))
  printf '70:col#pb:C:Wrong Answer:%s:s2\n' $(( FREEZE + 60 )); } > "$C/users/teambr001/history"
{ printf '20:col#pa:C:Compilation Error:%s:s3\n' $(( START + 1200 ))
  printf '25:col#pb:C:Not Answered Yet:%s:s4\n' $(( START + 1500 )); } > "$C/users/teambr002/history"
printf '5:col#pa:C:Accepted,100p:%s:s9\n' $(( START + 300 )) > "$C/users/telao.animeitor/history"     # papel: nunca é run
bash "$ROOT/score/build.sh" ap >/dev/null 2>&1
for u in adm:ap.admin ani:telao.animeitor cst:sede.cstaff usr:teambr001; do
  printf 'CONTEST=ap\nLOGIN=%s\nLOGINAT=1\n' "${u#*:}" > "$SESS/${u%%:*}"; done

export AN_MOCK_USER="moj" AN_MOCK_TOKEN="tok-super-secreto-123"
python3 "$HERE/animeitor-mock.py" "$MOCKD" "$MOCKD/port" & MOCKPID=$!
for _ in $(seq 50); do [[ -s "$MOCKD/port" ]] && break; sleep 0.1; done
[[ -s "$MOCKD/port" ]] || { echo "mock não subiu"; exit 1; }
MURL="http://127.0.0.1:$(cat "$MOCKD/port")"

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="contest=ap${5:+&$5}" HTTP_AUTHORIZATION="Bearer ${4:-ani}" \
  bash "$ROUTER" <<<"${3:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
J(){ printf '%s' "$BODY" | jq -r "$1" 2>/dev/null; }
ST(){ jq -r "$1" "$MOCKD/state.json" 2>/dev/null; }
REQ(){ grep -c "$1" "$MOCKD/requests.log" 2>/dev/null || true; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:260}"; ((fail++)); fi; }
A=/contest/animeitor/api

echo "== gates =="
call $A GET '' usr;  ck "competidor → 403"       '[[ "$OUT" == *"Status: 403"* ]]'
call $A GET '' cst;  ck ".cstaff → 403 (a tela dele é só a galeria da sede)" '[[ "$OUT" == *"Status: 403"* ]]'
call $A GET '' ani;  ck ".animeitor lê; nada configurado; URL padrão do Emilio" '[[ "$(J .configured)" == false && "$(J .url)" == "https://animeitor.naquadah.com.br" && "$(J .event)" == ap ]]'
call $A GET '' adm;  ck "admin também"           '[[ "$(J .success)" == true ]]'

echo "== conexão (token write-only) =="
call $A POST '{"action":"config","url":"http://evil.example"}'
ck "URL em claro → 422 (Basic em http é credencial na rede)" '[[ "$OUT" == *"Status: 422"* ]]'
call $A POST '{"action":"config","user":"moj","token":"com \"aspas\" e espaço"}'
ck "token com aspas/espaço → 422 (vai p/ o arquivo de config do curl)" '[[ "$OUT" == *"Status: 422"* ]]'
call $A POST "$(jq -cn --arg u "$MURL" '{action:"config", url:$u, user:"moj", token:"errado-errado", moj_base_url:"https://moj.exemplo", event:"ap-2026"}')"
ck "config salva; credencial em secrets/ 600" '[[ "$(J .saved)" == true && "$(stat -c %a "$C/secrets/animeitor.cred")" == 600 && "$(J .user)" == moj ]]'
ck "o token NÃO volta (nem no GET, nem no animeitor.json, nem no audit)" \
   '[[ "$BODY" != *errado-errado* ]] && ! grep -rq "errado-errado" "$C/animeitor.json" "$C/var" 2>/dev/null'
call $A POST '{"action":"test"}'
ck "test com token errado → 502 upstream_unauthorized" '[[ "$(J .error.code)" == upstream_unauthorized ]]'
call $A POST '{"action":"config","user":"moj","token":"tok-super-secreto-123"}'
call $A POST '{"action":"test"}'
ck "test ok: credencial vale, evento ainda não existe" '[[ "$(J .ok)" == true && "$(J .event_exists)" == false ]]'
ck "módulo telao ligado"               'grep -q "CONTEST_MODULES=.*telao" "$C/conf"'

echo "== proposta de placares e sedes =="
call $A GET '' ani 'proposal=1'
P(){ J ".proposal.contests[] | select(.name == \"$1\") | $2"; }
ck "5 times no evento; papel fora"     '[[ "$(J .proposal.teams_total)" == 5 ]]'
ck "placares: Geral + coortes + países (all = public ⇒ não repete)" '[[ "$(J "[.proposal.contests[].name] | join(\",\")")" == "Geral,Oficiais,Convidados,Brasil,México" ]]'
ck "Geral = todo o evento ⇒ regex .*"  '[[ "$(P Geral ".codes[0]")" == ".*" && "$(P Geral .n)" == 5 ]]'
ck "coorte COM regex que reproduz o recorte ⇒ vai o regex" '[[ "$(P Convidados ".codes[0]")" == "^conv" && "$(P Convidados .kind)" == regex ]]'
ck "coorte SEM regex (default) ⇒ lista exata dos 4 oficiais" '[[ "$(P Oficiais .kind)" == list && "$(P Oficiais ".codes[0]")" == "^(teambr001|teambr002|teammx001|zeta)$" ]]'
ck "sede por CAMPO da conta ⇒ lista exata (zeta e o convidado são de Brasília)" '[[ "$(P Brasil ".sites[] | select(.name==\"Brasília\") | .codes[0]")" == "^(conv001|teambr001|zeta)$" ]]'
ck "sede por regex ⇒ o regex"          '[[ "$(P México ".sites[0].codes[0]")" == "^teammx" ]]'
ck "o Geral leva TODAS as sedes-folha (revelação por sede no placar geral)" '[[ "$(P Geral "[.sites[].name] | join(\",\")")" == "Brasília,Goiânia,CDMX" ]]'

echo "== publicar =="
call $A POST '{"action":"publish"}'
ck "publica: evento criado + 5 placares + sedes" '[[ "$(J .result.ok)" == true && "$(J .result.event.action)" == created && "$(J "[.result.contests[] | select(.action == \"created\")] | length")" == 5 ]]'
ck "evento lá: nome editado, letras, roster {login, escola, nome}, freeze e penalidade em SEGUNDOS" \
   '[[ "$(ST ".events[\"ap-2026\"].state | [(.problems|join(\"\")), (.teams|length), .score_freeze_time_seconds, .penalty_seconds] | join(\",\")")" == "AB,5,3600,1200" && "$(ST ".events[\"ap-2026\"].state.teams[] | select(.login==\"teambr001\") | [.escola,.nome] | join(\"|\")")" == "UNB|Time Um" ]]'
ck "relógio inicial ~7200 s (a prova começou há 2 h)" '(( $(ST ".events[\"ap-2026\"].state.time_seconds") >= 7200 && $(ST ".events[\"ap-2026\"].state.time_seconds") <= 7300 ))'
ck "mídia: template com a URL pública do MOJ e {team_login}" '[[ "$(ST ".events[\"ap-2026\"].contests.Geral.config.photo_url_format")" == "https://moj.exemplo/api/v1/contest/team-photo?contest=ap&user={team_login}" && "$(ST ".events[\"ap-2026\"].contests.Geral.config.sound_url_format")" == *"/team-music?contest=ap&user={team_login}" ]]'
ck "nome com acento/espaço vai percent-encoded e chega inteiro" '[[ "$(ST ".events[\"ap-2026\"].contests.Brasil.sites | keys | join(\",\")")" == "Brasília,Goiânia" ]]'
n0="$(wc -l < "$MOCKD/requests.log")"
call $A POST '{"action":"publish"}'
ck "publicar de novo: NADA mudou ⇒ ZERO requests" '[[ "$(J .result.ok)" == true && "$(wc -l < "$MOCKD/requests.log")" == "$n0" && "$(J "[.result.contests[].action] | unique | join(\",\")")" == unchanged ]]'
ck "NUNCA PUT (substituição total zera o salt ⇒ troca os links de revelação)" '[[ "$(REQ "\"m\": \"PUT\"")" == 0 ]]'
# o operador do Animeitor gira o salt de uma sede; o MOJ muda as medalhas e republica — o salt FICA
curl -s -u "moj:tok-super-secreto-123" -X POST "$MURL/internal/sites/ap-2026/Brasil/Goi%C3%A2nia/salt" >/dev/null
call $A GET '' ani 'proposal=1'; PROP="$(J '.proposal.contests')"
call $A POST "$(jq -cn --argjson p "$PROP" '{action:"save", contests: [ $p[] | select(.name != "Convidados") | {name, source, codes:null, ouro:(if .name=="Brasil" then 4 else 1 end), prata:8, bronze:12, sites:[.sites[] | {name, source, codes:null}]} ]}')"
ck "save: placares revisados (Convidados removido, medalhas 4/8/12 no Brasil)" '[[ "$(J .saved)" == true && "$(J ".contests | length")" == 4 ]]'
call $A POST '{"action":"publish"}'
ck "republica: Brasil atualizado por PATCH, Convidados APAGADO lá, o resto intocado" \
   '[[ "$(J ".result.contests[] | select(.name==\"Brasil\") | .action")" == updated && "$(J ".result.deleted | join(\",\")")" == Convidados && "$(ST ".events[\"ap-2026\"].contests.Brasil.config.ouro")" == 4 && "$(ST ".events[\"ap-2026\"].contests | has(\"Convidados\")")" == false ]]'
ck "o status guarda a hora da publicação (e é o que a tela mostra)" '[[ "$(jq -r ".published_at // 0" "$C/var/animeitor.status.json")" -ge "$NOW" ]]'
ck "…e o salt girado pelo operador SOBREVIVEU" '[[ "$(ST ".events[\"ap-2026\"].contests.Brasil.sites[\"Goiânia\"].salt")" == gerado-pelo-mock ]]'
call $A POST '{"action":"save","contests":[{"name":"Manual","source":{"kind":"manual"},"sites":[]}]}'
ck "placar manual sem regex → 422"     '[[ "$(J .error.code)" == codes_missing ]]'
call $A POST '{"action":"save","contests":[{"name":"Ruim","source":{"kind":"manual"},"codes":["^(?=x)"],"sites":[]}]}'
call $A POST '{"action":"publish"}'
ck "regex que o serviço recusa (look-ahead): o erro DELE aparece por placar, o resto não quebra" '[[ "$(J .result.ok)" == false && "$(J ".result.contests[] | select(.name==\"Ruim\") | .error")" == *invalid_regex* ]]'
call $A POST "$(jq -cn --argjson p "$PROP" '{action:"save", contests: [ $p[] | select(.name != "Convidados") | {name, source, codes:null, sites:[.sites[] | {name, source, codes:null}]} ]}')"
call $A POST '{"action":"publish"}'

echo "== evento que JÁ existe lá e não é nosso =="
curl -s -u "moj:tok-super-secreto-123" -H 'Content-Type: application/json' -X POST "$MURL/internal/events/regional-2026" \
  -d '{"name":"regional-2026","problems":["A"],"teams":[{"login":"x","escola":"e","nome":"n"}],"score_freeze_time_seconds":1,"penalty_seconds":1}' >/dev/null
call $A POST '{"action":"stop"}'; call $A POST '{"action":"config","event":"regional-2026"}'
call $A POST '{"action":"publish"}'
ck "publicar num evento alheio → 409 event_exists, e ele fica INTOCADO" '[[ "$(J .error.code)" == event_exists && "$(ST ".events[\"regional-2026\"].state.teams | length")" == 1 ]]'
call $A POST '{"action":"reset","confirm":"regional-2026"}'
ck "reset de evento alheio → 409 not_managed (nunca apaga o que não criou)" '[[ "$(J .error.code)" == not_managed && "$(ST ".events | has(\"regional-2026\")")" == true ]]'
call $A POST '{"action":"config","event":"ap-2026"}'; call $A POST '{"action":"publish"}'

echo "== runs: só o delta, correção por id estável =="
call $A POST '{"action":"push-runs"}'
ck "1ª carga: 4 runs (a de conta de PAPEL não existe)" '[[ "$(J .runs.sent)" == 4 && "$(J .runs.added)" == 4 && "$(ST ".events[\"ap-2026\"].runs | length")" == 4 ]]'
R(){ ST ".events[\"ap-2026\"].runs | to_entries[] | select(.value.team_login == \"$1\" and .value.prob == \"$2\") | .value | $3"; }
ck "AC→Y · WA→N · CE→X (não penaliza) · pendente→?" '[[ "$(R teambr001 A .answer)$(R teambr001 B .answer)$(R teambr002 A .answer)$(R teambr002 B .answer)" == "YNX?" ]]'
ck "tempo em SEGUNDOS desde o início (600 s, não 10 min)" '[[ "$(R teambr001 A .time_seconds)" == 600 ]]'
ck "resposta REAL pós-freeze vai (quem congela é o Animeitor)" '[[ "$(R teambr001 B .time_seconds)" == 3660 && "$(R teambr001 B .answer)" == N ]]'
n0="$(REQ '/runs')"; call $A POST '{"action":"push-runs"}'
ck "sem novidade: NENHUM request de runs" '[[ "$(J .runs.sent)" == 0 && "$(REQ "/runs")" == "$n0" ]]'
# o juiz responde a pendente (vira AC) e chega uma submissão OFFLINE com carimbo ANTIGO
sed -i 's/Not Answered Yet/Accepted,100p/' "$C/users/teambr002/history"
printf '2:col#pa:C:Wrong Answer:%s:s-offline\n' $(( START + 120 )) >> "$C/users/zeta/history"
ID4="$(R teambr002 B .id)"
call $A POST '{"action":"push-runs"}'
ck "delta: 1 corrigida + 1 nova, e só essas 2 viajam" '[[ "$(J .runs.sent)" == 2 && "$(J .runs.updated)" == 1 && "$(J .runs.added)" == 1 ]]'
ck "a corrigida MANTÉM o id (o sequencial do BOCA teria mudado com a offline)" '[[ "$(R teambr002 B .id)" == "$ID4" && "$(R teambr002 B .answer)" == Y && "$(R zeta A .id)" == 5 ]]'
# o admin REMOVE uma submissão: a API não tem DELETE por run ⇒ corrige p/ X
sed -i '/:s2$/d' "$C/users/teambr001/history"
call $A POST '{"action":"push-runs"}'
ck "submissão removida no MOJ vira X lá (não conta)" '[[ "$(J .runs.removed)" == 1 && "$(R teambr001 B .answer)" == X ]]'
# time que o serviço não conhece (roster ainda não republicado): a run volta num warning e NÃO entra no sent
mkteam novo001 "Time Novo" UFPR "Goiânia"; printf '30:col#pa:C:Accepted,100p:%s:s-novo\n' $(( START + 1800 )) > "$C/users/novo001/history"
bash "$ROOT/score/build.sh" ap >/dev/null 2>&1
call $A POST '{"action":"push-runs"}'
ck "run de time desconhecido: ignorada pelo serviço e FORA do sent" '[[ "$(J .runs.ignored)" == 1 ]] && ! grep -q "novo001" "$C/var/animeitor-sent.tsv"'
call $A POST '{"action":"publish"}'
ck "republicar leva o time novo (PATCH do roster com keep_runs) e a sede dele cresce" \
   '[[ "$(J .result.event.action)" == updated && "$(ST ".events[\"ap-2026\"].state.teams | length")" == 6 && "$(ST ".events[\"ap-2026\"].contests.Brasil.sites[\"Goiânia\"].codes[0]")" == "^(novo001|teambr002)$" ]] && grep -q "keep_runs=true" "$MOCKD/requests.log"'
call $A POST '{"action":"push-runs"}'
ck "…e a run dele entra na passada seguinte" '[[ "$(J .runs.added)" == 1 && "$(R novo001 A .answer)" == Y ]]'
call $A POST '{"action":"push-runs","full":true}'
ck "status das runs gravado (contagens p/ a tela)" '[[ "$(jq -r ".runs.total" "$C/var/animeitor.status.json")" == 5 ]]'
ck "full: reenvia as 5 vivas, o serviço não duplica (added 0)" '[[ "$(J .runs.sent)" == 5 && "$(J .runs.added)" == 0 ]]'

echo "== relógio =="
( source "$ROOT/api/v1/lib/common.sh" 2>/dev/null; source "$ROOT/api/v1/lib/cohorts.sh"; source "$ROOT/api/v1/lib/animeitor.sh"
  an_push_time ap >/dev/null
  sed -i "s/^CONTEST_START=.*/CONTEST_START=$(( NOW + 600 ))/; s/^CONTEST_END=.*/CONTEST_END=$(( NOW + 11400 ))/" "$C/conf"; echo "pre=$(an_time_now ap)"
  sed -i "s/^CONTEST_START=.*/CONTEST_START=$(( NOW - 20000 ))/; s/^CONTEST_END=.*/CONTEST_END=$(( NOW - 2000 ))/" "$C/conf"; echo "pos=$(an_time_now ap)"
  sed -i "s/^CONTEST_START=.*/CONTEST_START=$START/; s/^CONTEST_END=.*/CONTEST_END=$END/" "$C/conf" ) > "$MOCKD/clock.out" 2>&1
ck "PATCH /time com os segundos decorridos; var/animeitor.clock gravado" '(( $(ST ".events[\"ap-2026\"].state.time_seconds") >= 7200 )) && [[ "$(cut -d" " -f3 "$C/var/animeitor.clock")" == 200 ]]'
ck "antes do início o relógio é NEGATIVO; depois do fim pára na duração" 'grep -qE "^pre=-(5[0-9][0-9]|600)$" "$MOCKD/clock.out" && grep -qx "pos=18000" "$MOCKD/clock.out"'

echo "== alimentador: liga/desliga =="
call $A POST '{"action":"start"}'
ck "start: marcador em run/animeitor/active + enabled" '[[ -e "$RUN/animeitor/active/ap" && "$(J .enabled)" == true ]]'
call $A POST '{"action":"config","event":"outro"}'
ck "trocar o evento com o alimentador ligado → 409" '[[ "$(J .error.code)" == feeding ]]'
call $A POST '{"action":"stop"}'
ck "stop: marcador some"               '[[ ! -e "$RUN/animeitor/active/ap" && "$(J .enabled)" == false ]]'

echo "== o ALIMENTADOR (daemons/animeitor-feed.sh --once): relógio + runs + roster, fora do julgamento =="
FEED(){ bash "$ROOT/daemons/animeitor-feed.sh" --once >/dev/null 2>&1; }
call $A POST '{"action":"start"}'
: > "$MOCKD/requests.log"; FEED
ck "1ª passada: manda o relógio (PATCH /time) e bate o ponto" '[[ "$(REQ "/time")" == 1 && -s "$RUN/animeitor/feed.alive" && "$(cut -d" " -f3 "$C/var/animeitor.clock")" == 200 ]]'
ck "…e as runs: nada novo desde o push manual ⇒ o serviço não cria nem corrige nada" '[[ "$(ST ".events[\"ap-2026\"].runs | length")" == 6 ]]'
: > "$MOCKD/requests.log"; sleep 1; FEED
ck "2ª passada sem novidade: só o relógio viaja (nenhum history mudou ⇒ zero request de runs)" '[[ "$(REQ "/time")" == 1 && "$(REQ "/runs")" == 0 ]]'
sleep 1; printf '40:col#pb:C:Accepted,100p:%s:s-feed\n' $(( START + 2400 )) >> "$C/users/zeta/history"
: > "$MOCKD/requests.log"; FEED
ck "veredicto novo: a passada seguinte leva SÓ essa run" '[[ "$(REQ "/runs")" == 1 && "$(R zeta B .answer)" == Y ]] && grep "/runs" "$MOCKD/requests.log" | grep -q "\"len\": [0-9]\{2,3\}[,}]"'
# time novo com run ANTES de o roster ir: a run volta por unknown_team ⇒ a passada seguinte republica e reenvia
mkteam tardio01 "Time Tardio" UNB "Brasília"; printf '50:col#pa:C:Accepted,100p:%s:s-tardio\n' $(( START + 3000 )) > "$C/users/tardio01/history"
bash "$ROOT/score/build.sh" ap >/dev/null 2>&1
sleep 1; FEED; sleep 1; FEED
ck "time inscrito no meio da prova: roster republicado sozinho e a run dele chega" '[[ "$(ST ".events[\"ap-2026\"].state.teams | length")" == 7 && "$(R tardio01 A .answer)" == Y ]]'
# o Animeitor cai: o alimentador não morre, anota o erro e recua
kill "$MOCKPID" 2>/dev/null; wait "$MOCKPID" 2>/dev/null; MOCKPID=""
sleep 1; FEED; rc=$?
ck "serviço fora do ar: o alimentador sai limpo, anota o erro e o relógio local mostra a falha" '[[ $rc -eq 0 && "$(jq -r .last_error.where "$C/var/animeitor.status.json")" == relogio && "$(cut -d" " -f3 "$C/var/animeitor.clock")" != 200 ]]'
( exec 9>"$RUN/animeitor/feed.lock"; flock -n 9; bash "$ROOT/daemons/animeitor-feed.sh" --once 2>"$MOCKD/dup.err"; echo "rc=$?" >> "$MOCKD/dup.err" )
ck "instância única: com o lock tomado o 2º alimentador sai sem fazer nada" 'grep -q "já há um alimentador" "$MOCKD/dup.err" && grep -q "rc=0" "$MOCKD/dup.err"'
sed -i "s/^CONTEST_START=.*/CONTEST_START=$(( NOW - 200000 ))/; s/^CONTEST_END=.*/CONTEST_END=$(( NOW - 100000 ))/" "$C/conf"
FEED
ck "24 h depois do fim: desliga sozinho (marcador some, enabled=false)" '[[ ! -e "$RUN/animeitor/active/ap" && "$(jq -r .enabled "$C/animeitor.json")" == false ]]'
sed -i "s/^CONTEST_START=.*/CONTEST_START=$START/; s/^CONTEST_END=.*/CONTEST_END=$END/" "$C/conf"
python3 "$HERE/animeitor-mock.py" "$MOCKD" "$MOCKD/port2" & MOCKPID=$!
for _ in $(seq 50); do [[ -s "$MOCKD/port2" ]] && break; sleep 0.1; done
# (o mock novo nasce vazio: republica tudo nele p/ as seções seguintes)
call $A POST "$(jq -cn --arg u "http://127.0.0.1:$(cat "$MOCKD/port2")" '{action:"config", url:$u}')"
rm -f "$C/var/animeitor-managed.json" "$C/var/animeitor-sent.tsv"; MURL="http://127.0.0.1:$(cat "$MOCKD/port2")"
call $A POST '{"action":"publish"}'; call $A POST '{"action":"push-runs"}'

echo "== rodada nova = EVENTO novo (a API não limpa o histórico do stream) =="
call $A POST '{"action":"config","event":""}'                       # volta ao nome-padrão
printf '{"version":1,"active":"prova","rounds":[{"slug":"aquecimento","state":"archived"},{"slug":"prova","state":"active"}]}' > "$C/rounds.json"
call $A GET ''
ck "com rodadas o nome-padrão do evento leva a rodada ativa" '[[ "$(J .event)" == "ap-prova" ]]'
cp "$C/users/teambr001/history" "$MOCKD/h1.bak"; : > "$C/users/teambr001/history"    # a promoção zerou o history deste time
call $A POST '{"action":"publish"}'; call $A POST '{"action":"push-runs"}'
ck "evento novo recebe só as runs VIVAS — as que sumiram não viram X fantasma nele" \
   '[[ "$(ST ".events[\"ap-prova\"].runs | length")" == "$(J .runs.total)" && "$(J .runs.removed)" == 0 && "$(ST "[.events[\"ap-prova\"].runs[] | select(.team_login == \"teambr001\")] | length")" == 0 ]]'
cp "$MOCKD/h1.bak" "$C/users/teambr001/history"; rm -f "$C/rounds.json"
call $A POST '{"action":"config","event":"ap-2026"}'; call $A POST '{"action":"publish"}'
ck "voltar p/ um evento que o MOJ já não acompanha pede adoção (409), mesmo tendo sido criado por ele" '[[ "$(J .error.code)" == event_exists ]]'
call $A POST '{"action":"publish","adopt":true}'; call $A POST '{"action":"push-runs"}'

echo "== links e segredo =="
call $A GET '' ani 'links=1'
ck "links públicos por placar + de revelação por sede" '[[ "$(J ".links.public | length")" == 4 && "$(J ".links.revelation | length")" -ge 5 && "$(J ".links.revelation[0].url")" == *"secret="* ]]'
ck "link público = origem do front + /animeitor/<evento>/<placar>/ (percent-encoded)" '[[ "$(J ".links.public[] | select(.contest == \"México\") | .url")" == "https://telao.exemplo/animeitor/ap-2026/M%C3%A9xico/" ]]'
ck "a credencial nunca foi a argv nem a arquivo do var/ (só secrets/)" '! grep -rq "tok-super-secreto-123" "$C/var" "$C/animeitor.json" "$C/conf" 2>/dev/null'
ck "…nem o link de revelação fica gravado" '! grep -rq "secret=" "$C/var" "$C/animeitor.json" 2>/dev/null'

curl -s -u "moj:tok-super-secreto-123" -H 'Content-Type: application/json' -X POST "$MURL/internal/events/regional-2026" \
  -d '{"name":"regional-2026","problems":["A"],"teams":[{"login":"x","escola":"e","nome":"n"}],"score_freeze_time_seconds":1,"penalty_seconds":1}' >/dev/null
echo "== REVELEITOR nas sedes: o .animeitor libera, .cstaff/.staff recebem SÓ os da sede deles =="
RV=/contest/animeitor/reveal
fx_user "$C" goiania.staff p "Staff de Goiânia" >/dev/null; fx_user "$C" solto.staff p "Staff sem sede" >/dev/null; fx_user "$C" mx.cstaff p "Chefe México" >/dev/null
mkdir -p "$C/print-requests"
# sede.cstaff por token region: · goiania.staff idem (caixa diferente de propósito) · mx.cstaff por REGEX de login · solto.staff sem filtro
jq -n '{"sede.cstaff":["region:Brasília"], "goiania.staff":["region:goiânia"], "mx.cstaff":["^teammx"]}' > "$C/print-requests/staff-filters.json"
jq -c '.team.region = "CDMX"' "$C/users/teammx001/account.json" > "$C/t" && mv "$C/t" "$C/users/teammx001/account.json"
for u in gst:goiania.staff sol:solto.staff mxc:mx.cstaff; do printf 'CONTEST=ap\nLOGIN=%s\nLOGINAT=1\n' "${u#*:}" > "$SESS/${u%%:*}"; done
nav(){ OUT="$(PATH_INFO=/contest/navbuttons REQUEST_METHOD=GET QUERY_STRING="contest=ap" HTTP_AUTHORIZATION="Bearer $1" NAV_CACHE_TTL=0 bash "$ROUTER" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
call $RV GET '' usr; ck "competidor → 403"  '[[ "$OUT" == *"Status: 403"* ]]'
n0="$(wc -l < "$MOCKD/requests.log")"
call $RV GET '' cst
ck "ANTES de liberar: released=false, zero links — e o servidor do telão nem é consultado" '[[ "$(J .released)" == false && "$(J ".links|length")" == 0 && "$(wc -l < "$MOCKD/requests.log")" == "$n0" ]]'
nav cst; ck "…e a barra do .cstaff não tem o botão" '[[ "$BODY" != *Reveleitor* ]]'
call $A POST '{"action":"reveal-release"}' cst
ck "só o .animeitor/admin libera (.cstaff → 403)" '[[ "$OUT" == *"Status: 403"* ]]'
call $A POST '{"action":"reveal-release"}'
ck "libera: estado no animeitor.json (quem e quando) + marcador p/ a barra" '[[ "$(J .reveal.released)" == true && "$(J .reveal.by)" == telao.animeitor && -e "$C/var/animeitor-reveal.released" ]]'
call $RV GET '' cst
ck ".cstaff de Brasília: os links da sede dele em TODOS os placares em que ela aparece (Geral e Brasil)" \
   '[[ "$(J "[.links[] | .contest + \"/\" + .site] | sort | join(\",\")")" == "Brasil/Brasília,Geral/Brasília" && "$(J ".links[0].url")" == *"secret="* && "$(J .scoped)" == true ]]'
ck "…e NENHUM de outra sede" '[[ "$BODY" != *Goi* && "$BODY" != *CDMX* ]]'
call $RV GET '' gst
ck ".staff de Goiânia (region: em outra caixa): só Goiânia" '[[ "$(J "[.links[].site] | unique | join(\",\")")" == "Goiânia" && "$(J ".links|length")" == 2 ]]'
call $RV GET '' mxc
ck ".cstaff com escopo por REGEX de login: a sede sai dos times que ele enxerga (CDMX)" '[[ "$(J "[.links[] | .contest + \"/\" + .site] | sort | join(\",\")")" == "Geral/CDMX,México/CDMX" ]]'
call $RV GET '' sol
ck "staff SEM sede definida: fail-closed — liberado, mas zero links (scoped:false)" '[[ "$(J .released)" == true && "$(J .scoped)" == false && "$(J ".links|length")" == 0 ]]'
call $RV GET '' ani
ck ".animeitor vê todos"                 '[[ "$(J .all)" == true && "$(J ".links|length")" -ge 5 ]]'
nav cst; ck "barra do .cstaff ganha o botão Reveleitor (leva à mesa do telão)" '[[ "$(J ".buttons[] | select(.label == \"Reveleitor\") | .url")" == "/contest/animeitor/?reveleitor=1" ]]'
nav gst; ck "…e a do .staff também"      '[[ "$BODY" == *Reveleitor* ]]'
nav usr; ck "…a do competidor NÃO"       '[[ "$BODY" != *Reveleitor* ]]'
# sede RENOMEADA no telão pelo operador: o casamento é pela região de origem, não pelo nome exibido
call $A GET '' ani 'proposal=1'; PR2="$(J '.proposal.contests')"
call $A POST "$(jq -cn --argjson p "$PR2" '{action:"save", contests: [ $p[] | select(.name != "Convidados") | {name, source, codes:null, sites:[.sites[] | {name: (if .name == "Brasília" then "Sede DF" else .name end), source, codes:null}]} ]}')"
call $A POST '{"action":"publish"}'
call $RV GET '' cst
ck "sede renomeada p/ \"Sede DF\" no telão: o .cstaff de Brasília continua recebendo (casa pela região de origem)" '[[ "$(J "[.links[].site] | unique | join(\",\")")" == "Sede DF" && "$(J ".links|length")" == 2 ]]'
ck "a leitura do staff fica no audit (link é credencial)" 'grep -q "animeitor-reveal-read" "$C/var/admin-audit.log" 2>/dev/null || grep -rq "animeitor-reveal-read" "$C" 2>/dev/null'
call $A POST '{"action":"reveal-recall"}'
call $RV GET '' cst
ck "recolher: some tudo de novo (links e botão)" '[[ "$(J .released)" == false && "$(J ".links|length")" == 0 && ! -e "$C/var/animeitor-reveal.released" ]] && { nav cst; [[ "$BODY" != *Reveleitor* ]]; }'
call $A POST '{"action":"reveal-release"}'

echo "== reset =="
call $A POST '{"action":"reset"}'
ck "reset sem confirmação → 422"       '[[ "$(J .error.code)" == confirm_required ]]'
call $A POST '{"action":"reset","confirm":"ap-2026"}'
ck "reset confirmado: evento apagado LÁ, estado local limpo, o alheio continua" \
   '[[ "$(J .reset)" == true && ! -e "$C/var/animeitor-reveal.released" && "$(ST ".events | has(\"ap-2026\")")" == false && "$(ST ".events | has(\"regional-2026\")")" == true && ! -e "$C/var/animeitor-sent.tsv" ]]'
ck "o mapa de ids FICA (id é da submissão, não do evento)" '[[ -s "$C/var/animeitor-ids.tsv" ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
