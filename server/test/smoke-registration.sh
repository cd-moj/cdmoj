#!/bin/bash
# smoke-registration.sh — INSCRIÇÃO em contest (roster + janela) e TIMES de contas do treino.
# Cobre: janela nos 4 estados, inscrição individual, convite→aceite/recusa, exclusividade,
# a PORTA do contest (login_disabled / login_not_open / not_registered / registration_closed),
# o ALIAS de time (o membro entra com a senha dele e a submissão é do TIME), o log do ator,
# a materialização no store e os placares paralelos (times × individual).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; SPOOL="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$SPOOL"' EXIT
RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$SPOOL" "$RUN"' EXIT
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" SPOOLDIR="$SPOOL" SCOREDIR="$ROOT/score" RUNDIR="$RUN"
NOW="$(date +%s)"

T="$FIX/treino"; mkdir -p "$T/var/jsons"
printf 'CONTEST_ID=treino\nCONTEST_NAME="Treino"\nCONTEST_TYPE=lista-publica\n' > "$T/conf"
for u in ana caio west zeze bob; do fx_user "$T" "$u" s3nha "Fulano $u"; done

C="$FIX/esq"; mkdir -p "$C/var" "$C/users" "$C/enunciados"
conf(){ # <start> <end> [extra…]
  { printf 'CONTEST_ID=esq\nCONTEST_NAME="Esquenta"\nCONTEST_TYPE=icpc\nUSERS_FROM=treino\n'
    printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$1" "$2"
    printf 'PROBS=( cdmoj org#alfa Alfa A org#alfa )\n'
    shift 2; for e in "$@"; do printf '%s\n' "$e"; done; } > "$C/conf"
}
conf "$((NOW+3600))" "$((NOW+10800))" 'REG_LATE_MINUTES=30'
fx_user "$C" esq.admin adm "Admin da Prova"          # conta de PAPEL: nunca é barrada
printf '{"id":"org#alfa","title":"Alfa"}' > "$T/var/jsons/org#alfa.json"

mkses(){ printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=1\n' "$2" "$3" "$3" > "$SESS/$1"; }
for u in ana caio west zeze bob; do mkses "tok-$u" treino "$u"; done
mkses tok-adm esq esq.admin

# call <path> <method> [body] [token] [query]
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" \
    HTTP_AUTHORIZATION="Bearer ${4:-tok-ana}" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
reg(){ call /treino/contest-registration POST "$1" "${2:-tok-ana}" ''; }   # contest vai no CORPO
adm(){ call /contest/admin/registrations POST "$1" tok-adm 'contest=esq'; }
login(){ call /auth/login POST "{\"username\":\"$1\",\"password\":\"${2:-s3nha}\"}" '' 'contest=esq'; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:170}"; ((fail++)); fi; }
J(){ jq -r "$1" <<<"$BODY" 2>/dev/null; }

echo "== sem roster: contest aberto como sempre =="
call /treino/contest-registration GET '' tok-ana 'contest=esq'
ck "GET diz enabled:false"      '[[ "$(J .enabled)" == false ]]'
reg '{"contest":"esq","action":"register"}'
ck "inscrever sem roster -> 409" '[[ "$OUT" == *"Status: 409"* && "$(J .error.code)" == registration_off ]]'
login bob
ck "bob entra (sem roster, porta aberta)" '[[ "$(J .logged_in)" == true ]]'

echo "== admin liga a inscrição =="
adm '{"action":"enable"}'
ck "enabled:true"               '[[ "$(J .enabled)" == true ]]'
ck "coortes semeadas"           '[[ "$(jq -r "[.cohorts[].id]|sort|join(\",\")" "$C/cohorts.json")" == "individual,individual-atrasado,times,times-atrasado" ]]'
ck "roster criado"              '[[ -f "$C/registrations.json" ]]'

echo "== inscrição individual =="
reg '{"contest":"esq","action":"register"}' tok-zeze
ck "zeze inscrito"              '[[ "$(J .me.kind)" == individual ]]'
ck "coorte individual"          '[[ "$(J .me.cohort)" == individual ]]'
ck "overlay SEM senha no store" '[[ -f "$C/users/zeze/account.json" && -z "$(jq -r ".password // empty" "$C/users/zeze/account.json")" ]]'
ck "nome veio do treino"        '[[ "$(jq -r .fullname "$C/users/zeze/account.json")" == "Fulano zeze" ]]'
reg '{"contest":"esq","action":"register"}' tok-zeze
ck "inscrever 2x -> 409"        '[[ "$OUT" == *"Status: 409"* && "$(J .error.code)" == already_registered ]]'

echo "== time: criar, convidar, aceitar, recusar =="
reg '{"contest":"esq","action":"team-create","name":"Os Três Ponteiros"}' tok-ana
ck "time criado"                '[[ "$(J .team.login)" == "time-os-tres-ponteiros" ]]'
ck "ana é capitã"               '[[ "$(J .team.captain)" == ana && "$(J .me.kind)" == team ]]'
ck "conta do time no store"     '[[ "$(jq -r .fullname "$C/users/time-os-tres-ponteiros/account.json")" == "Os Três Ponteiros" ]]'
ck "senha do time desativada"   '[[ "$(jq -r .password "$C/users/time-os-tres-ponteiros/account.json")" == \!* ]]'
ck "coorte times"               '[[ "$(jq -r .team.cohort "$C/users/time-os-tres-ponteiros/account.json")" == times ]]'
reg '{"contest":"esq","action":"team-create","name":"Os Tres Ponteiros"}' tok-bob
ck "nome repetido -> 409"       '[[ "$(J .error.code)" == name_taken ]]'
reg '{"contest":"esq","action":"team-invite","login":"caio"}' tok-ana
ck "convite p/ caio"            '[[ "$(J ".team.invited|join(\",\")")" == *caio* ]]'
reg '{"contest":"esq","action":"team-invite","login":"naoexiste"}' tok-ana
ck "convidar quem não existe -> 404" '[[ "$(J .error.code)" == user_notfound ]]'
reg '{"contest":"esq","action":"team-invite","login":"west"}' tok-ana
ck "convite p/ west"            '[[ "$(J .error.code)" != team_full ]]'
reg '{"contest":"esq","action":"team-invite","login":"bob"}' tok-ana
ck "4º integrante -> team_full"  '[[ "$(J .error.code)" == team_full ]]'
call /treino/contest-registration GET '' tok-caio 'contest=esq'
ck "caio vê o convite"          '[[ "$(J ".invites[0].login")" == time-os-tres-ponteiros ]]'
reg '{"contest":"esq","action":"team-accept","team":"time-os-tres-ponteiros"}' tok-caio
ck "caio no time"               '[[ "$(J .me.kind)" == team && "$(J ".team.members|join(\",\")")" == *caio* ]]'
reg '{"contest":"esq","action":"team-decline","team":"time-os-tres-ponteiros"}' tok-west
ck "west recusou"               '[[ "$(J ".invites|length")" == 0 ]]'
reg '{"contest":"esq","action":"team-invite","login":"caio"}' tok-caio
ck "convite de quem não é capitão -> 403" '[[ "$OUT" == *"Status: 403"* ]]'

echo "== a PORTA do contest =="
conf "$((NOW-600))" "$((NOW+10800))" 'REG_LATE_MINUTES=30' "REG_CLOSE=$((NOW+3600))"
login bob
ck "não inscrito -> 403 not_registered" '[[ "$OUT" == *"Status: 403"* && "$(J .error.code)" == not_registered ]]'
login zeze
ck "inscrito individual entra"  '[[ "$(J .logged_in)" == true && "$(J .username)" == zeze ]]'
login caio
ck "MEMBRO entra como o TIME"   '[[ "$(J .username)" == time-os-tres-ponteiros ]]'
ck "…e a resposta traz o ator"  '[[ "$(J .actor)" == caio && "$(J .is_team)" == true ]]'
TOKTEAM="$(J .token)"
call /auth/status GET '' "$TOKTEAM" 'contest=esq'
ck "status: login=time, actor=caio" '[[ "$(J .login)" == time-os-tres-ponteiros && "$(J .actor)" == caio ]]'
ck "access.log marcou o ator"   'grep -q "	caio$" "$C/var/access.log"'

echo "== submissão do membro é do TIME =="
call /submit POST '{"problem_id":"org#alfa","filename":"s.c","code_b64":"aQ=="}' "$TOKTEAM" 'contest=esq'
ck "submit aceito"              '[[ "$(J .status)" == queued ]]'
ck "history do TIME"            '[[ "$(wc -l < "$C/users/time-os-tres-ponteiros/history")" == 1 ]]'
ck "caio não tem history próprio" '[[ ! -s "$C/users/caio/history" ]]'
ck "actor-log: quem estava no teclado" 'grep -q ":time-os-tres-ponteiros:caio$" "$C/var/actor-log"'

echo "== janela: atrasado e fechado =="
conf "$((NOW-600))" "$((NOW+10800))" 'REG_LATE_MINUTES=30'   # REG_CLOSE volta ao início (passado)
call /treino/contest-registration GET '' tok-bob 'contest=esq'
ck "janela = late"              '[[ "$(J .window.state)" == late ]]'
reg '{"contest":"esq","action":"register"}' tok-bob
ck "bob entra atrasado"         '[[ "$(J .me.cohort)" == individual-atrasado ]]'
login bob
ck "atrasado consegue entrar"   '[[ "$(J .logged_in)" == true ]]'
conf "$((NOW-7200))" "$((NOW+10800))" 'REG_LATE_MINUTES=30'  # início há 2h: atraso vencido
call /treino/contest-registration GET '' tok-west 'contest=esq'
ck "janela = closed"            '[[ "$(J .window.state)" == closed ]]'
reg '{"contest":"esq","action":"register"}' tok-west
ck "inscrição fechada -> 403"   '[[ "$OUT" == *"Status: 403"* && "$(J .error.code)" == registration_closed ]]'
login west
ck "quem não entrou fica fora"  '[[ "$(J .error.code)" == registration_closed ]]'

echo "== janela de login (era só fachada no front) =="
conf "$((NOW-7200))" "$((NOW+10800))" 'REG_LATE_MINUTES=30' "LOGIN_START_TIME=$((NOW+3600))"
login zeze
ck "antes da abertura -> 403"   '[[ "$(J .error.code)" == login_not_open ]]'
login esq.admin adm
ck "admin entra mesmo assim"    '[[ "$(J .logged_in)" == true ]]'
conf "$((NOW-7200))" "$((NOW+10800))" 'REG_LATE_MINUTES=30' 'LOGIN_ENABLED=n'
login zeze
ck "login desligado -> 403"     '[[ "$(J .error.code)" == login_disabled ]]'
login esq.admin adm
ck "admin entra mesmo assim"    '[[ "$(J .logged_in)" == true ]]'
conf "$((NOW-7200))" "$((NOW+10800))" 'REG_LATE_MINUTES=30'

echo "== placares paralelos (times × individual) =="
source "$ROOT/api/v1/lib/verdict.sh"; source "$ROOT/api/v1/lib/users.sh"
printf '10:org#alfa:c:Accepted:%s:s1\n' "$((NOW-500))" > "$C/users/time-os-tres-ponteiros/history"
printf '20:org#alfa:c:Accepted:%s:s2\n' "$((NOW-400))" > "$C/users/zeze/history"
for u in time-os-tres-ponteiros zeze bob; do metrics_recompute esq "$u" >/dev/null 2>&1; done
bash "$SCOREDIR/build.sh" esq >/dev/null 2>&1
ck "placar geral tem os dois"   'grep -q ":time-os-tres-ponteiros:" "$C/var/placar.txt" && grep -q ":zeze:" "$C/var/placar.txt"'
ck "placar dos TIMES só o time" '[[ -f "$C/var/placar-view-times.txt" ]] && grep -q ":time-os-tres-ponteiros:" "$C/var/placar-view-times.txt" && ! grep -q ":zeze:" "$C/var/placar-view-times.txt"'
ck "placar INDIVIDUAL sem time" 'grep -q ":zeze:" "$C/var/placar-view-individual.txt" && ! grep -q ":time-os-tres-ponteiros:" "$C/var/placar-view-individual.txt"'
ck "atrasado aparece no individual" 'grep -q ":bob:" "$C/var/placar-view-individual.txt"'
call /contest/score GET '' '' 'contest=esq&view=times'
ck "GET score?view=times sem sessão" '[[ "$OUT" == *"time-os-tres-ponteiros"* && "$OUT" != *":zeze:"* ]]'

echo "== troca de handle arrasta a inscrição =="
call /treino/profile/username POST '{"new_username":"caio2"}' tok-caio
ck "rename ok"                  '[[ "$(J .updated)" == true ]]'
ck "roster seguiu"              'jq -e ".teams[\"time-os-tres-ponteiros\"].members|index(\"caio2\")" "$C/registrations.json" >/dev/null'
ck "entries seguiram"           'jq -e ".entries|has(\"caio2\")" "$C/registrations.json" >/dev/null'


echo "== RODADAS: aquecimento aberto por dias, prova fechada =="
# history no TREINO p/ provar depois que a promoção NÃO mexe no store da fonte
printf '5:org#alfa:c:Accepted,100p:5:tt1\n' > "$T/users/west/history"
OFF_START=$((NOW + 7200)); OFF_END=$((NOW + 18000))
conf "$((NOW-1800))" "$((NOW+1800))" 'REG_LATE_MINUTES=30' 'ROUND=aquecimento' 'ROUND_KIND=warmup'
jq -cn --argjson s "$OFF_START" --argjson e "$OFF_END" \
  '{version:1, active:"aquecimento",
    rounds:[{slug:"aquecimento", name:"Aquecimento", kind:"warmup", state:"active", start:0, end:0, problems:[]},
            {slug:"prova", name:"Prova oficial", kind:"official", state:"pending",
             start:$s, end:$e, freeze:0, problems:[]}]}' > "$C/rounds.json"
call /treino/contest-registration GET '' tok-west 'contest=esq'
ck "janela ancora na PROVA, não no aquecimento" '[[ "$(J .window.closes_at)" == '"$OFF_START"' ]]'
ck "estado = aberta (aquecimento no ar)"        '[[ "$(J .window.state)" == open ]]'
ck "diz qual rodada ancora"                     '[[ "$(J .window.official_round)" == prova ]]'
ck "atraso conta a partir da PROVA"             '[[ "$(J .window.late_until)" == '"$((OFF_START+1800))"' ]]'
ck "gate DESLIGADO no aquecimento"              '[[ "$(J .gate_active)" == false ]]'
login west
ck "NÃO inscrito entra no aquecimento"          '[[ "$(J .logged_in)" == true ]]'
TOKW="$(J .token)"
call /submit POST '{"problem_id":"org#alfa","filename":"s.c","code_b64":"aQ=="}' "$TOKW" 'contest=esq'
ck "e submete no aquecimento"                   '[[ "$(J .status)" == queued ]]'
ck "ganhou dir local (sem conta)"               '[[ -d "$C/users/west" && ! -e "$C/users/west/account.json" ]]'

# pronto p/ promover: aquecimento encerrado, fila vazia, sem veredicto pendente, daemon vivo
conf "$((NOW-1800))" "$((NOW-60))" 'REG_LATE_MINUTES=30' 'ROUND=aquecimento' 'ROUND_KIND=warmup'
rm -f "$SPOOL"/* 2>/dev/null
printf '10:org#alfa:c:Accepted,100p:%s:w1\n' "$((NOW-100))" > "$C/users/west/history"
printf '10:org#alfa:c:Accepted,100p:%s:s1\n' "$((NOW-200))" > "$C/users/time-os-tres-ponteiros/history"
mkdir -p "$RUNDIR"; : > "$RUNDIR/judged.alive"
bash "$SCOREDIR/build.sh" esq >/dev/null 2>&1
call /contest/admin/rounds POST '{"action":"promote","to":"prova"}' tok-adm 'contest=esq'
ck "promoção de contest COMPARTILHADO passa"    '[[ "$(J .promoted)" == true ]]'
ck "varreu a sessão do turista"                 '[[ "$(J .swept.sessions)" -ge 1 ]]'
ck "e o diretório vazio dele"                   '[[ "$(J .swept.dirs)" -ge 1 && ! -e "$C/users/west" ]]'
ck "TREINO intacto (a fonte não é tocada)"      '[[ "$(wc -l < "$T/users/west/history")" == 1 ]]'
ck "arquivo levou os placares por coorte"       '[[ -f "$C/rounds/aquecimento/placar-view-times.txt" ]]'
login west
ck "turista não entra na PROVA"                 '[[ "$(J .error.code)" == not_registered ]]'
call /auth/status GET '' "$TOKW" 'contest=esq'
ck "sessão velha do turista morreu"             '[[ "$(J .logged_in)" == false ]]'
ck "roster sobreviveu à promoção"               'jq -e ".teams[\"time-os-tres-ponteiros\"]" "$C/registrations.json" >/dev/null'
ck "conta do time sobreviveu"                   '[[ -f "$C/users/time-os-tres-ponteiros/account.json" ]]'
ck "history do time foi arquivado e zerado"     '[[ ! -s "$C/users/time-os-tres-ponteiros/history" && -s "$C/rounds/aquecimento/users/time-os-tres-ponteiros/history" ]]'
login caio2
ck "membro entra na prova COMO O TIME"          '[[ "$(J .username)" == time-os-tres-ponteiros && "$(J .actor)" == caio2 ]]'
call /treino/contest-registration GET '' tok-zeze 'contest=esq'
ck "gate LIGADO agora (prova no ar)"            '[[ "$(J .gate_active)" == true ]]'
ck "janela segue ancorada no início da prova"   '[[ "$(J .window.closes_at)" == '"$OFF_START"' ]]'

echo "== admin: listar, inscrever à mão, dissolver =="
call /contest/admin/registrations GET '' tok-adm 'contest=esq'
ck "admin vê 1 time"            '[[ "$(J .totals.teams)" == 1 ]]'
ck "admin vê os individuais"    '[[ "$(J .totals.individuals)" == 2 ]]'
adm '{"action":"add","login":"west"}'
ck "admin inscreveu west"       '[[ "$(J .totals.individuals)" == 3 ]]'
adm '{"action":"rm","login":"west"}'
ck "admin removeu west"         '[[ "$(J .totals.individuals)" == 2 ]]'
adm '{"action":"team-rm","team":"time-os-tres-ponteiros"}'
ck "admin dissolveu o time"     '[[ "$(J .totals.teams)" == 0 ]]'
call /contest/admin/registrations GET '' tok-zeze 'contest=esq'
ck "não-admin 403"              '[[ "$OUT" == *"Status: 403"* ]]'

echo ""
echo "RESULT: $pass passed, $fail failed"
exit $(( fail>0 ? 1 : 0 ))
