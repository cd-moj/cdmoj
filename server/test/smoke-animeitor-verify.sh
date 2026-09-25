#!/bin/bash
# smoke-animeitor-verify.sh — CHAVE DO MOJ e CONFERÊNCIA do telão (25/09/2026, pedidos do Emilio Wuerges),
# contra o mock ESTRITO animeitor-mock.py.
#
#   · CHAVE DO MOJ ($ANIMEITOR_CRED_FILE): vale p/ todo contest sem chave própria, no servidor padrão, e nunca
#     volta p/ a tela (nem o usuário); a chave PRÓPRIA do contest vence; apagá-la volta p/ a do MOJ; a do MOJ
#     NUNCA vai a outra URL. Com uma credencial compartilhada, o REGISTRO de posse (run/animeitor/events.json)
#     é quem separa os contests: nome de evento de outro contest = 409 event_taken antes de qualquer request;
#     a chave do MOJ não assume evento de fora (adopt_forbidden) — com chave própria, pode; o reset libera.
#   · CONFERÊNCIA (runs_secret, Bearer = a chave da sede do link de revelação): antes do início not_started;
#     tudo certo = ok; run que o Animeitor perdeu, com resposta errada, que só ele tem, e a removida no MOJ
#     que voltou a contar lá são reenviadas e a 2ª conferência fecha ok; sede com o MESMO regex em dois placares
#     = uma consulta só; com a prova encerrada e nada pendente = FINAL (o "validado"), com pendente não; o
#     alimentador confere sozinho (destacado); o .cstaff vê a conferência SÓ das sedes dele; chave de sede,
#     resposta e credencial nunca vão a disco.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; MOCKD="$(mktemp -d)"; RUN="$(mktemp -d)"; MOCKPID=""
cleanup(){ [[ -n "$MOCKPID" ]] && kill "$MOCKPID" 2>/dev/null; [[ -n "${KEEP:-}" ]] && { echo "KEEP: $FIX $MOCKD $RUN"; return; }; rm -rf "$FIX" "$SESS" "$MOCKD" "$RUN"; }
trap cleanup EXIT
source "$HERE/fixture.sh"
export AN_MOCK_USER="moj" AN_MOCK_TOKEN="chave-do-moj-0123456789"
python3 "$HERE/animeitor-mock.py" "$MOCKD" "$MOCKD/port" & MOCKPID=$!
for _ in $(seq 50); do [[ -s "$MOCKD/port" ]] && break; sleep 0.1; done
[[ -s "$MOCKD/port" ]] || { echo "mock não subiu"; exit 1; }
MURL="http://127.0.0.1:$(cat "$MOCKD/port")"
# o servidor PADRÃO é o mock e a chave do MOJ mora em $RUNDIR/secrets (fora de todo contest)
export CONTESTSDIR="$FIX" RUNDIR="$RUN" SESSIONDIR="$SESS" ANIMEITOR_URL="$MURL"
mkdir -p "$RUN/secrets"; ( umask 077; printf 'moj:%s\n' "$AN_MOCK_TOKEN" > "$RUN/secrets/animeitor.cred" )

NOW="$EPOCHSECONDS"; START=$(( NOW - 7200 )); FREEZE=$(( NOW - 3600 )); END=$(( NOW + 3600 ))
mkc(){ # <id> — contest com 3 times, sem regions (sede única "Geral"), 2 problemas
  local C="$FIX/$1"; mkdir -p "$C/var"
  { printf 'CONTEST_ID=%s\nCONTEST_TYPE=icpc\nCONTEST_NAME=Prova\nCONTEST_START=%s\nCONTEST_END=%s\nFREEZE_TIME=%s\nPENALTY_MINUTES=20\n' "$1" "$START" "$END" "$FREEZE"
    printf "PROBS=( x col#pa Alfa A col#pa x col#pb Beta B col#pb )\n"; } > "$C/conf"
  fx_user "$C" "$1.admin" p Admin >/dev/null; fx_user "$C" telao.animeitor p Telao >/dev/null; fx_user "$C" sede.cstaff p Chefe >/dev/null
  for t in time1:Um time2:Dois time3:Tres; do fx_user "$C" "${t%%:*}" x "Time ${t#*:}" >/dev/null; : > "$C/users/${t%%:*}/history"; done
  for u in adm:"$1.admin" ani:telao.animeitor cst:sede.cstaff; do printf 'CONTEST=%s\nLOGIN=%s\nLOGINAT=1\n' "$1" "${u#*:}" > "$SESS/$1-${u%%:*}"; done
}
mkc va; mkc vb
C="$FIX/va"
{ printf '10:col#pa:C:Accepted,100p:%s:s1\n' $(( START + 600 ))
  printf '70:col#pb:C:Wrong Answer:%s:s2\n' $(( FREEZE + 60 )); } > "$C/users/time1/history"
{ printf '20:col#pa:C:Compilation Error:%s:s3\n' $(( START + 1200 ))
  printf '25:col#pb:C:Accepted,100p:%s:s4\n' $(( START + 1500 )); } > "$C/users/time2/history"
printf '30:col#pa:C:Wrong Answer:%s:s5\n' $(( START + 1800 )) > "$C/users/time3/history"
bash "$ROOT/score/build.sh" va >/dev/null 2>&1; bash "$ROOT/score/build.sh" vb >/dev/null 2>&1

call(){ local c="$1"; shift
  OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="contest=$c${5:+&$5}" HTTP_AUTHORIZATION="Bearer $c-${4:-ani}" \
    bash "$ROUTER" <<<"${3:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
J(){ printf '%s' "$BODY" | jq -r "$1" 2>/dev/null; }
ST(){ jq -r "$1" "$MOCKD/state.json" 2>/dev/null; }
mock(){ curl -s -o /dev/null -w '%{http_code}' -X "$1" -H 'Content-Type: application/json' ${3:+-d "$3"} "$MURL/mock/runs/$2"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:300}"; ((fail++)); fi; }
A=/contest/animeitor/api

echo "== a chave do MOJ: padrão de todo contest, invisível =="
call va $A GET
ck "sem gravar nada: configurado com a chave do MOJ (cred_source moj)" '[[ "$(J .configured)" == true && "$(J .cred_source)" == moj && "$(J .moj_cred)" == true && "$(J .url)" == "$MURL" ]]'
ck "…e nem o usuário da chave do MOJ aparece" '[[ "$(J .user)" == "" && "$BODY" != *"$AN_MOCK_TOKEN"* ]]'
call va $A POST '{"action":"test"}'
ck "test: a chave do MOJ vale no servidor padrão" '[[ "$(J .ok)" == true && "$(J .cred_source)" == moj ]]'
call va $A POST '{"action":"config","user":"proprio","token":"token-proprio-errado"}'
call va $A GET
ck "chave PRÓPRIA gravada: vence a do MOJ (o usuário dela aparece; o token não)" '[[ "$(J .cred_source)" == contest && "$(J .user)" == proprio && "$BODY" != *token-proprio-errado* ]]'
call va $A POST '{"action":"test"}'
ck "…e é ELA que vai ao servidor (o mock a recusa: 401 ⇒ 502)" '[[ "$(J .error.code)" == upstream_unauthorized ]]'
call va $A POST '{"action":"config","user":"","token":""}'
call va $A GET
ck "apagar a própria: volta p/ a chave do MOJ" '[[ "$(J .cred_source)" == moj && ! -e "$C/secrets/animeitor.cred" ]]'
call va $A POST '{"action":"config","url":"http://127.0.0.1:1"}'
call va $A GET
ck "URL digitada pelo operador: a chave do MOJ NÃO vale lá (configured false, cred none)" '[[ "$(J .configured)" == false && "$(J .cred_source)" == none && "$(J .moj_cred)" == true ]]'
call va $A POST '{"action":"publish"}'
ck "…e nada é enviado (409 not_configured)" '[[ "$(J .error.code)" == not_configured ]]'
call va $A POST "$(jq -cn --arg u "$MURL" '{action:"config", url:$u}')"

echo "== registro de posse (a credencial é compartilhada) =="
call va $A POST '{"action":"publish"}'
ck "va publica com a chave do MOJ; o registro diz que o evento é dele" '[[ "$(J .result.ok)" == true && "$(jq -r --arg u "$MURL" ".[\$u].va" "$RUN/animeitor/events.json")" == va ]]'
n0="$(wc -l < "$MOCKD/requests.log")"
call vb $A POST '{"action":"config","event":"va"}'; call vb $A POST '{"action":"publish","adopt":true}'
ck "vb com o nome do evento de va → 409 event_taken, SEM request nenhum (nem com adopt)" '[[ "$(J .error.code)" == event_taken && "$(wc -l < "$MOCKD/requests.log")" == "$n0" ]]'
ck "…e o erro não diz de QUAL contest é" '[[ "$(J .error.message)" != *va* ]]'
curl -s -u "moj:$AN_MOCK_TOKEN" -H 'Content-Type: application/json' -X POST "$MURL/internal/events/regional-2026" \
  -d '{"name":"regional-2026","problems":["A"],"teams":[{"login":"x","escola":"e","nome":"n"}],"score_freeze_time_seconds":1,"penalty_seconds":1}' >/dev/null
call vb $A POST '{"action":"config","event":"regional-2026"}'; call vb $A POST '{"action":"publish"}'
ck "evento de FORA: 409 event_exists (como sempre)" '[[ "$(J .error.code)" == event_exists ]]'
call vb $A POST '{"action":"publish","adopt":true}'
ck "com a chave do MOJ não dá p/ assumir evento de fora (adopt_forbidden) — e ele fica intocado" '[[ "$(J .error.code)" == adopt_forbidden && "$(ST ".events[\"regional-2026\"].state.teams | length")" == 1 ]]'
call vb $A POST "$(jq -cn --arg t "$AN_MOCK_TOKEN" '{action:"config", user:"moj", token:$t}')"
call vb $A POST '{"action":"publish","adopt":true}'
ck "com chave PRÓPRIA pode (é a credencial do operador); o registro passa a dizer vb" '[[ "$(J .result.ok)" == true && "$(jq -r --arg u "$MURL" ".[\$u][\"regional-2026\"]" "$RUN/animeitor/events.json")" == vb ]]'
call vb $A POST '{"action":"reset","confirm":"regional-2026"}'
ck "reset libera o nome no registro" '[[ "$(J .reset)" == true && "$(jq -r --arg u "$MURL" ".[\$u] | has(\"regional-2026\")" "$RUN/animeitor/events.json")" == false ]]'
call vb $A POST '{"action":"config","user":"","token":"","event":""}'

echo "== conferência: antes do início =="
sed -i "s/^CONTEST_START=.*/CONTEST_START=$(( NOW + 600 ))/; s/^CONTEST_END=.*/CONTEST_END=$(( NOW + 11400 ))/" "$FIX/vb/conf"
call vb $A POST '{"action":"publish"}'; call vb $A POST '{"action":"verify"}'
ck "antes do início o serviço não confere (not_started), sem erro p/ o operador" '[[ "$(J .success)" == true && "$(J .verify.state)" == not_started && "$(J .verify.final)" == false ]]'
sed -i "s/^CONTEST_START=.*/CONTEST_START=$START/; s/^CONTEST_END=.*/CONTEST_END=$END/" "$FIX/vb/conf"

echo "== conferência: tudo certo =="
call va $A POST '{"action":"push-runs"}'
: > "$MOCKD/requests.log"
call va $A POST '{"action":"verify"}'
ck "o Animeitor tem as 5 runs: ok, nada a reenviar, prova ainda rolando ⇒ não é final" \
   '[[ "$(J .verify.state)" == ok && "$(J .verify.runs)" == 5 && "$(J .verify.checked)" == 5 && "$(J .verify.missing)" == 0 && "$(J .verify.uncovered)" == 0 && "$(J .verify.final)" == false && "$(J .before)" == null ]]'
ck "a consulta é a rota PÚBLICA com Bearer (a chave da sede), nunca Basic" \
   'grep "runs_secret" "$MOCKD/requests.log" | grep -q "\"auth\": \"Bearer\"" && ! grep "runs_secret" "$MOCKD/requests.log" | grep -q "\"auth\": \"Basic\""'
ck "o resultado fica gravado (a tela e o reveleitor leem)" '[[ "$(jq -r .state "$C/var/animeitor-verify.json")" == ok ]]'

echo "== conferência: o Animeitor perdeu/estragou runs ⇒ reenvia e confere de novo =="
id_of(){ ST ".events.va.runs | to_entries[] | select(.value.team_login == \"$1\" and .value.prob == \"$2\") | .key"; }
I1="$(id_of time1 A)"; I2="$(id_of time2 B)"
mock DELETE "va/$I1" >/dev/null; mock PATCH "va/$I2" '{"answer":"N"}' >/dev/null
curl -s -u "moj:$AN_MOCK_TOKEN" -H 'Content-Type: application/json' -X POST "$MURL/internal/events/va/runs" \
  -d '{"runs":[{"id":9999,"team_login":"time3","prob":"B","time_seconds":100,"answer":"Y"}]}' >/dev/null
call va $A POST '{"action":"verify"}'
ck "achou: 1 faltando, 1 divergente e 1 que só o Animeitor tem (o telão mostraria um AC que não existe)" \
   '[[ "$(J .before.missing)" == 1 && "$(J .before.wrong)" == 1 && "$(J .before.extra)" == 1 ]]'
ck "…reenviou e a 2ª conferência fecha ok" '[[ "$(J .verify.state)" == ok && "$(J .verify.missing)" == 0 && "$(J .verify.wrong)" == 0 && "$(J .verify.extra)" == 0 ]]'
ck "lá: a perdida voltou, a resposta certa voltou, a fantasma virou X" \
   '[[ "$(ST ".events.va.runs[\"$I1\"].answer")" == Y && "$(ST ".events.va.runs[\"$I2\"].answer")" == Y && "$(ST ".events.va.runs[\"9999\"].answer")" == X ]]'
# submissão REMOVIDA no MOJ (lá é X); o Animeitor "esquece" o X ⇒ a conferência manda o X de novo
sed -i '/:s5$/d' "$C/users/time3/history"; call va $A POST '{"action":"push-runs"}'
I5="$(ST '.events.va.runs | to_entries[] | select(.value.team_login == "time3" and .value.prob == "A") | .key')"
mock PATCH "va/$I5" '{"answer":"N"}' >/dev/null
call va $A POST '{"action":"verify"}'
ck "removida no MOJ que voltou a contar lá: detectada e corrigida p/ X" '[[ "$(J .before.wrong)" == 1 && "$(J .verify.state)" == ok && "$(ST ".events.va.runs[\"$I5\"].answer")" == X ]]'

echo "== sede com o MESMO regex em dois placares = uma consulta =="
call va $A POST '{"action":"save","contests":[{"name":"Geral","source":{"kind":"view","id":"public"},"codes":null,"sites":[{"name":"Geral","source":{"kind":"whole","id":"public"},"codes":null}]},{"name":"Telão 2","source":{"kind":"manual","id":""},"codes":[".*"],"sites":[{"name":"Toda","source":{"kind":"manual","id":""},"codes":[".*"]}]}]}'
call va $A POST '{"action":"publish"}'
: > "$MOCKD/requests.log"; call va $A POST '{"action":"verify"}'
ck "2 sedes na conferência, 1 GET de runs_secret" '[[ "$(J ".verify.sites | length")" == 2 && "$(grep -c runs_secret "$MOCKD/requests.log")" == 1 && "$(J .verify.state)" == ok ]]'

echo "== conferência FINAL (o \"validado\") =="
printf '40:col#pb:C:Not Answered Yet:%s:s6\n' $(( START + 2400 )) >> "$C/users/time3/history"
sed -i "s/^CONTEST_START=.*/CONTEST_START=$(( NOW - 20000 ))/; s/^CONTEST_END=.*/CONTEST_END=$(( NOW - 600 ))/; s/^FREEZE_TIME=.*/FREEZE_TIME=$(( NOW - 4000 ))/" "$C/conf"
call va $A POST '{"action":"push-runs"}'; call va $A POST '{"action":"verify"}'
ck "prova encerrada mas com run PENDENTE: bate, mas não é final" '[[ "$(J .verify.state)" == ok && "$(J .verify.pending)" == 1 && "$(J .verify.final)" == false ]]'
sed -i 's/Not Answered Yet/Wrong Answer/' "$C/users/time3/history"
call va $A POST '{"action":"push-runs"}'; call va $A POST '{"action":"verify"}'
ck "encerrada, nada pendente, tudo bate: FINAL, com a hora" '[[ "$(J .verify.final)" == true && "$(J .verify.final_at)" -ge "$NOW" && "$(J .verify.over)" == true ]]'
FA="$(J .verify.final_at)"; sleep 1; call va $A POST '{"action":"verify"}'
ck "conferir de novo mantém a hora da 1ª validação" '[[ "$(J .verify.final_at)" == "$FA" ]]'
call va $A GET
ck "o GET da mesa traz o resumo (sem ids)" '[[ "$(J .verify.final)" == true && "$(J .verify.sample)" == null ]]'

echo "== reveleitor: a sede vê a conferência DELA =="
mkdir -p "$C/print-requests"; jq -n '{"sede.cstaff":["region:Geral"]}' > "$C/print-requests/staff-filters.json"
call va $A POST '{"action":"reveal-release"}'
call va /contest/animeitor/reveal GET '' cst
ck ".cstaff: os links da sede + validado (final) só das sedes dele" '[[ "$(J .verify.final)" == true && "$(J .verify.ok)" == true && "$(J "[.verify.sites[].site] | join(\",\")")" == Geral && "$(J .verify.runs)" == null ]]'
call va /contest/animeitor/reveal GET '' ani
ck ".animeitor: o resumo do evento (7: as 6 do MOJ + a fantasma, que lá ficou como X)" '[[ "$(J .verify.final)" == true && "$(J .verify.runs)" == 7 ]]'
mock PATCH "va/$I1" '{"answer":"N"}' >/dev/null
( source "$ROOT/api/v1/lib/common.sh" 2>/dev/null; source "$ROOT/api/v1/lib/cohorts.sh"; source "$ROOT/api/v1/lib/animeitor.sh"
  an_verify va "$MOCKD/v.json" 0 >/dev/null ) >/dev/null 2>&1
call va /contest/animeitor/reveal GET '' cst
ck "divergência (sem reparo) derruba o validado na tela da sede" '[[ "$(J .verify.final)" == false && "$(J .verify.ok)" == false ]]'
call va $A POST '{"action":"verify"}'

echo "== o alimentador confere sozinho =="
call va $A POST '{"action":"start"}'
rm -f "$C/var/animeitor-verify.json"; mock PATCH "va/$I1" '{"answer":"N"}' >/dev/null
bash "$ROOT/daemons/animeitor-feed.sh" --once >/dev/null 2>&1
for _ in $(seq 100); do [[ -s "$C/var/animeitor-verify.json" ]] && break; sleep 0.1; done
ck "1ª passada depois do fim: conferência destacada acha a divergência e marca p/ reenvio" '[[ "$(jq -r .state "$C/var/animeitor-verify.json")" == diverge && "$(jq -r .repair "$C/var/animeitor-verify.json")" -ge 1 ]]'
for _ in $(seq 100); do [[ -e "$C/var/.animeitor-verify.lock" ]] && flock -n "$C/var/.animeitor-verify.lock" true && break; sleep 0.1; done
bash "$ROOT/daemons/animeitor-feed.sh" --once >/dev/null 2>&1
ck "a passada seguinte reenvia (o delta voltou)" '[[ "$(ST ".events.va.runs[\"$I1\"].answer")" == Y ]]'
grep -q "conferência" "$RUN/animeitor/feed.log" && ck "o alimentador anota no log" 'true' || ck "o alimentador anota no log" 'false'
call va $A POST '{"action":"stop"}'

echo "== sedes por CAMPO da conta, login com hífen (regex em LISTA, com escape) =="
# (o @tsv do jq escapava a barra invertida: `^(time\-a)$` chegava `\\-` e a sede não casava ninguém)
mkc vc; D="$FIX/vc"
for t in time-a:Brasília time-b:Goiânia; do l="${t%%:*}"; fx_user "$D" "$l" x "Time $l" >/dev/null
  jq -c --arg r "${t#*:}" '.team = {name:"x", region:$r}' "$D/users/$l/account.json" > "$D/t" && mv "$D/t" "$D/users/$l/account.json"
  printf '10:col#pa:C:Accepted,100p:%s:s-%s\n' $(( START + 600 )) "$l" > "$D/users/$l/history"; done
jq -c '.team = {name:"x", region:"Brasília"}' "$D/users/time1/account.json" > "$D/t" && mv "$D/t" "$D/users/time1/account.json"
jq -n '[{name:"Brasil", subregions:[{name:"Brasília"},{name:"Goiânia"}]}]' > "$D/regions.json"
bash "$ROOT/score/build.sh" vc >/dev/null 2>&1
call vc $A POST '{"action":"publish"}'; call vc $A POST '{"action":"push-runs"}'; call vc $A POST '{"action":"verify"}'
ck "as sedes casam os times pelo regex escapado: as 2 runs conferidas (e o time1, sem run, não conta)" '[[ "$(J .verify.state)" == ok && "$(J .verify.runs)" == 2 && "$(J .verify.checked)" == 2 && "$(J .verify.uncovered)" == 0 ]]'
ck "…e o regex de lista com escape foi o publicado" '[[ "$(ST ".events.vc.contests.Geral.sites[\"Brasília\"].codes[0]")" == *"time\\-a"* ]]'
call vc $A POST '{"action":"save","contests":[{"name":"Geral","source":{"kind":"manual","id":""},"codes":[".*"],"sites":[{"name":"Vazia","source":{"kind":"manual","id":""},"codes":["^ninguem$"]}]}]}'
call vc $A POST '{"action":"publish"}'; call vc $A POST '{"action":"verify"}'
ck "sede que não cobre time nenhum: no_sites (não um \"ok\" com 0 conferidas)" '[[ "$(J .verify.state)" == no_sites && "$(J .verify.ok)" == false ]]'

echo "== segredo =="
ck "a chave do MOJ só mora em \$RUNDIR/secrets (nada no contest)" '! grep -rq "$AN_MOCK_TOKEN" "$FIX" 2>/dev/null'
ck "chave de sede nunca vai a disco (nem no resultado da conferência)" '! grep -rq "secret=" "$FIX" "$RUN/animeitor" 2>/dev/null && ! grep -rqE "\"key\"|Bearer" "$C/var" 2>/dev/null'
ck "o resultado da conferência não guarda resposta de run (só contagens e ids)" '! grep -qE "\"answer\"|\"team_login\"" "$C/var/animeitor-verify.json"'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
