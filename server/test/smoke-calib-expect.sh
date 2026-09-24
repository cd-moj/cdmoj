#!/bin/bash
# CALIB-EXPECT — o que cada categoria de solução tem de fazer na calibração (lib/calib-expect.sh).
# Relato do Arthur Botelho (22/09/2026): "TLE recebe WA ou o contrário e marca ok", e o problema seguia
# "validado" com solução de veredicto errado. O juízo agora é do SERVIDOR e olha o código de CADA teste:
#   1. a tabela (categoria × códigos): TLE+WA, pontuado `Wrong,Np`, CE/UE/linguagem, good acima de um
#      TLOVERRIDE, ALLOWTLEDURINGCALIBRATION;
#   2. ponta a ponta: /judge/calib-report grava o sumário, /problems/calib serve `expect` + `summary`
#      (+ o validador de entrada em `hosts[].validator`), /problems/status mostra soluções/entradas/
#      `ready`/`pending` (e `?id=`), e o problem_commit marca o sumário como velho SÓ quando mexe no que
#      a calibração exercita.
# ⚠ O jq mora em variável (o jq-portability.sh não o vê): rode também com o jq 1.7 da imagem —
#   PATH=<dir-do-jq-1.7>:$PATH bash server/test/smoke-calib-expect.sh
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; PROBS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN" "$PROBS"' EXIT
source "$HERE/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" MOJ_PROBLEMS_DIR="$PROBS" TL_STORE_DIR="$RUN/tl" \
       CALIB_DIR="$RUN/calib" WORKER_TOKEN_FILE="$RUN/secrets/worker.token" MOJ_JOBS_SYNC=1
mkdir -p "$RUN/tl" "$RUN/calib" "$RUN/secrets" "$FIX/treino/var"; printf 'mojw_segredo' > "$WORKER_TOKEN_FILE"
_LIBDIR="$ROOT/api/v1/lib"; source "$_LIBDIR/calib-expect.sh"

pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:-}" | head -c 400; echo; ((fail++)); fi; }
echo "jq: $(jq --version)"

# ---------------------------------------------------------------------------------------------------
echo "== 1. a tabela (categoria × códigos por teste) =="
# ex <categoria> <códigos separados por espaço> [verdict] [tempos] [eff-json] [allowtle] [drift-json] -> "state/why"
ex(){ local cat="$1" codes="$2" v="${3:-x}" times="${4:-}" eff="${5:-{\}}" allow="${6:-false}" drift="${7:-{\}}"
  jq -nr --arg cat "$cat" --arg codes "$codes" --arg v "$v" --arg times "$times" --argjson eff "$eff" \
     --argjson allow "$allow" --argjson drift "$drift" "$CALX_JQ"'
     ($codes | split(" ") | map(select(length > 0))) as $cs
     | ($times | split(" ") | map(select(length > 0) | tonumber)) as $tt
     | {category:$cat, lang:"cpp", verdict:$v,
        tests:[ range(0; $cs|length) as $i | {name:("t\($i)"), code:$cs[$i], time:($tt[$i] // 0.1)} ]}
     | calx($eff; $allow; $drift) | "\(.state)/\(.why)"' 2>&1; }
BODY=""
ck "good: todos AC = ok"                         '[[ "$(ex good "AC AC,PE AC")" == ok/all_ac ]]'
ck "good: um WA = bad"                           '[[ "$(ex good "AC WA")" == bad/failed ]]'
ck "good: TLE sem ALLOWTLE = bad"                '[[ "$(ex good "AC TLE")" == bad/failed ]]'
ck "good: TLE com ALLOWTLE = note"               '[[ "$(ex good "AC TLE" x "" "{}" true)" == note/tle_allowed ]]'
ck "good: TLE+WA com ALLOWTLE = bad"             '[[ "$(ex good "TLE WA" x "" "{}" true)" == bad/failed ]]'
ck "good acima do TLOVERRIDE = bad/over_tl (o AC que estoura o TL)" \
   '[[ "$(ex good "AC AC" x "0.3 0.9" "{\"cpp\":\"0.5\"}")" == bad/over_tl ]]'
ck "good abaixo do TL efetivo = ok"              '[[ "$(ex good "AC AC" x "0.3 0.4" "{\"cpp\":\"0.5\"}")" == ok/all_ac ]]'
ck "tolerância default: 0,86 s com TL 0,82 s + 0,1 = ok" '[[ "$(ex good "AC" x "0.86" "{\"cpp\":\"0.82\"}" false "{\"default\":0.1}")" == ok/all_ac ]]'
ck "sem tolerância: o mesmo tempo é over_tl"        '[[ "$(ex good "AC" x "0.86" "{\"cpp\":\"0.82\"}")" == bad/over_tl ]]'
ck "no limite exato de TL + tolerância: ok (o juiz usa >)" '[[ "$(ex good "AC" x "0.98" "{\"cpp\":\"0.82\"}" false "{\"cpp\":0.16}")" == ok/all_ac ]]'
ck "java.drift não vale p/ cpp"                     '[[ "$(ex good "AC" x "0.86" "{\"cpp\":\"0.82\"}" false "{\"java\":0.1}")" == bad/over_tl ]]'
ck "a da linguagem vence a default"                 '[[ "$(ex good "AC" x "0.86" "{\"cpp\":\"0.82\"}" false "{\"cpp\":0.01,\"default\":0.5}")" == bad/over_tl ]]'
ck "TL efetivo cai no default sem a linguagem"   '[[ "$(ex pass "AC" x "0.9" "{\"default\":\"0.5\"}")" == bad/over_tl ]]'
ck "pass: todos AC = ok"                         '[[ "$(ex pass "AC AC")" == ok/all_ac ]]'
ck "pass: TLE = bad (mesmo com ALLOWTLE)"        '[[ "$(ex pass "AC TLE" x "" "{}" true)" == bad/failed ]]'
ck "slow: TLE + AC = ok"                         '[[ "$(ex slow "AC TLE AC")" == ok/tle ]]'
ck "slow: TLE + WA = note (antes o TLE escondia o WA)" '[[ "$(ex slow "WA TLE" "Time Limit Exceeded,0p")" == note/tle_and_wrong ]]'
ck "slow: só WA = bad"                           '[[ "$(ex slow "AC WA")" == bad/wrong_no_tle ]]'
ck "slow: todos AC = bad"                        '[[ "$(ex slow "AC AC")" == bad/no_tle ]]'
ck "slow pontuado (Wrong,Np) com TLE = ok (antes: revisar)" '[[ "$(ex slow "AC TLE" "Wrong,50p. quantitativos TLE(1)")" == ok/tle ]]'
ck "wrong: WA = ok"                              '[[ "$(ex wrong "AC WA")" == ok/wa ]]'
ck "wrong: WA + TLE (string diz TLE) = ok"       '[[ "$(ex wrong "WA TLE" "Time Limit Exceeded,0p")" == ok/wa ]]'
ck "wrong: só TLE = note (falhou por outro motivo)" '[[ "$(ex wrong "AC TLE")" == note/failed_other ]]'
ck "wrong: só RE_NZEC/MLE = note"                '[[ "$(ex wrong "RE_NZEC MLE")" == note/failed_other ]]'
ck "wrong: todos AC = bad"                       '[[ "$(ex wrong "AC AC")" == bad/accepted ]]'
ck "wrong com CE = norun (não prova nada)"       '[[ "$(ex wrong "" "Compilation Error")" == norun/ce ]]'
ck "linguagem indisponível = norun"              '[[ "$(ex wrong "" "Language '"'"'x'"'"' not availale")" == norun/lang ]]'
ck "UE num teste = norun"                        '[[ "$(ex wrong "WA UE")" == norun/ue ]]'
ck "sem teste nem veredicto = norun"             '[[ "$(ex good "" "")" == norun/noverdict ]]'
ck "categoria desconhecida = skip"               '[[ "$(ex upcoming "AC")" == skip/category ]]'
CNT="$(jq -nc "$CALX_JQ"'{category:"slow",lang:"c",verdict:"x",tests:[{code:"TLE",time:1},{code:"WA",time:0.1},{code:"AC",time:0.2}]} | calx({}; false; {}) | .counts')"
ck "counts por classe (sem zeros)"               '[[ "$CNT" == "{\"AC\":1,\"WA\":1,\"TLE\":1}" ]]'
SUM="$(jq -nc "$CALX_JQ"'
  [ {host:"j1", sols:[ {category:"good",file:"a.cpp",expect:{state:"ok"}}, {category:"wrong",file:"w.py",expect:{state:"note"}},
                       {category:"validator",file:"scripts/validator.cpp",verdict:"invalid",tests:[{code:"OK"},{code:"INVALID"}]} ]},
    {host:"j2", sols:[ {category:"good",file:"a.cpp",expect:{state:"bad"}}, {category:"wrong",file:"w.py",expect:{state:"ok"}} ]} ]
  | calx_sum(.; ["good/a.cpp","wrong/w.py","slow/s.cpp"])')"
BODY="$SUM"
ck "sumário: bad em QUALQUER host conta"         '[[ "$(jq -c .bad_files <<<"$SUM")" == "[\"good/a.cpp\"]" ]]'
ck "sumário: note só se não for bad em nenhum"   '[[ "$(jq -c .note_files <<<"$SUM")" == "[\"wrong/w.py\"]" ]]'
ck "sumário: solução do pacote sem resultado = missing" '[[ "$(jq -c .missing <<<"$SUM")" == "[\"slow/s.cpp\"]" ]]'
ck "sumário: validador inválido (1 de 2)"        '[[ "$(jq -c "[.validator.state,.validator.invalid,.validator.total]" <<<"$SUM")" == "[\"invalid\",1,2]" ]]'
ck "sumário: validador fica fora do total"       '[[ "$(jq -r .total <<<"$SUM")" == 2 ]]'

# ---------------------------------------------------------------------------------------------------
echo "== 2. ponta a ponta: calib-report → sumário → /problems/calib e /problems/status =="
NOW="$EPOCHSECONDS"; T="$FIX/treino"
printf 'CONTEST_ID=treino\nCONTEST_END=%s\n' "$((NOW+86400))" > "$T/conf"
echo '{"col":{"members":["autor"],"admins":[],"public_allowed":true,"title":"Col"}}' > "$T/var/orgs.json"
P="$PROBS/col/pa"; mkdir -p "$P/sols/good" "$P/sols/slow" "$P/sols/wrong" "$P/tests/input" "$P/tests/output" "$P/docs"
printf 'CALIBRATIONTL=5\nTLOVERRIDE[py]=0.5\n' > "$P/conf"
printf '{"owner":"autor","public":false,"display_title":"PA"}\n' > "$P/.moj-meta.json"
printf 'int main(){}\n' > "$P/sols/good/sol.c"; printf 'print()\n' > "$P/sols/good/sol.py"
printf 'int main(){}\n' > "$P/sols/slow/lento.c"; printf 'int main(){}\n' > "$P/sols/wrong/int32.c"
printf '1\n' > "$P/tests/input/t1"; printf '1\n' > "$P/tests/output/t1"; printf 'x\n' > "$P/docs/enunciado.md"
( cd "$P" && git init -q && git add -A && git -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm init )
fx_user "$T" autor s "Autor"; fx_user "$T" outro s "Outro"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino autor Autor "$NOW" > "$SESS/aut"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino outro Outro "$NOW" > "$SESS/out"
source "$ROOT/api/v1/lib/common.sh" 2>/dev/null; source "$_LIBDIR/tl-store.sh"; source "$_LIBDIR/problems.sh"
TLC="$(pkg_tl_checksum "$P" 'col#pa')"
jq -cn --arg c "$TLC" '{problems:[{id:"col#pa",owner:"autor",repo:"col",prob:"pa",title:"PA",public:false,
   collaborators:[],collections:[],tl_checksum:$c,good_langs:["c","py"]}]}' > "$T/var/problem-owners.json"
tl_store_record juiz1 'col#pa' "$TLC" '{"c":"1.000","py":"2.000","default":"1.000"}' >/dev/null
get(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD=GET QUERY_STRING="$2" HTTP_AUTHORIZATION="Bearer $3" bash "$ROUTER" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
post(){ OUT="$(PATH_INFO=/judge/calib-report REQUEST_METHOD=POST HTTP_AUTHORIZATION="Bearer mojw_segredo" bash "$ROUTER" <<<"$1" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
get /judge/package-meta "id=col%23pa" mojw_segredo; VER="$(jq -r '.checksum // ""' <<<"$BODY")"
[[ -n "$VER" ]] || { echo "SETUP FAIL: package-meta sem checksum"; exit 1; }
# a calibração do relato: good .py acima do override, slow que deu WA junto do TLE, wrong que só deu TLE
SOLS='[
 {"file":"sol.c","lang":"c","category":"good","verdict":"Accepted,100p","tests":[{"name":"t1","code":"AC","time":0.3,"tl":5}]},
 {"file":"sol.py","lang":"py","category":"good","verdict":"Accepted,100p","tests":[{"name":"t1","code":"AC","time":0.9,"tl":5}]},
 {"file":"lento.c","lang":"c","category":"slow","verdict":"Time Limit Exceeded,0p","tests":[{"name":"t1","code":"TLE","time":1.1,"tl":1},{"name":"t2","code":"WA","time":0.2,"tl":1}]},
 {"file":"int32.c","lang":"c","category":"wrong","verdict":"Time Limit Exceeded,0p","tests":[{"name":"t1","code":"TLE","time":1.1,"tl":1}]},
 {"file":"scripts/validator.cpp","lang":"cpp","category":"validator","verdict":"invalid",
  "tests":[{"name":"t1","code":"INVALID","msg":"FAIL Integer 1296 violates the range [1, 1000]"},{"name":"t2","code":"OK"}]}]'
post "$(jq -cn --arg c "$VER" --argjson s "$SOLS" '{host:"juiz1", id:"col#pa", checksum:$c, log:"x", sols:$s}')"
ck "calib-report aceito"                          'grep -q "\"recorded\":true" <<<"$BODY"'
SF="$RUN/calib-sum/col#pa.json"
ck "sumário gravado em run/calib-sum"             '[[ -s "$SF" ]]'
ck "sumário: 1 divergente (good .py acima do override)" '[[ "$(jq -c .bad_files "$SF")" == "[\"good/sol.py\"]" ]]'
ck "sumário: slow com WA e wrong com TLE = note"  '[[ "$(jq -c ".note_files|sort" "$SF")" == "[\"slow/lento.c\",\"wrong/int32.c\"]" ]]'
ck "sumário: validador inválido"                  '[[ "$(jq -r .validator.state "$SF")" == invalid && "$(jq -r .validator.invalid "$SF")" == 1 ]]'
ck "mapa do Painel (run/calib-summary.json) com a chave" '[[ "$(jq -r ".[\"col#pa\"].bad" "$RUN/calib-summary.json")" == 1 ]]'
ck "msg da testlib passou pela projeção"          '[[ "$(jq -r ".sols[]|select(.category==\"validator\")|.tests[0].msg" "$RUN/calib/col#pa/juiz1.json")" == FAIL* ]]'

get /problems/calib "id=col%23pa" aut
ck "calib: expect em cada solução"                '[[ "$(jq -r "[.hosts[0].sols[].expect.state]|join(\",\")" <<<"$BODY")" == "ok,bad,note,note" ]]'
ck "calib: why do .py = over_tl, com o TL efetivo" '[[ "$(jq -r ".hosts[0].sols[]|select(.file==\"sol.py\")|.expect|\"\(.why) \(.tl)\"" <<<"$BODY")" == "over_tl 0.5" ]]'
ck "calib: validador FORA de sols e em hosts[].validator" '[[ "$(jq -r "[.hosts[0].sols[].category]|index(\"validator\")" <<<"$BODY")" == null && "$(jq -r ".hosts[0].validator.state" <<<"$BODY")" == invalid ]]'
ck "calib: validador traz os testes com msg"      '[[ "$(jq -r ".hosts[0].validator.tests[0].msg" <<<"$BODY")" == FAIL* ]]'
ck "calib: summary igual ao do Painel"            '[[ "$(jq -c "[.summary.bad,.summary.note,.summary.total]" <<<"$BODY")" == "[1,2,4]" ]]'
get /problems/calib "id=col%23pa" out
ck "calib: não-membro segue 404"                  'grep -q "not_found" <<<"$BODY"'

get /problems/status "" aut
ROW="$(jq -c '.problems[]|select(.id=="col#pa")' <<<"$BODY")"
ck "status: sols.state=bad com 1"                 '[[ "$(jq -c "[.sols.state,.sols.bad,.sols.note]" <<<"$ROW")" == "[\"bad\",1,2]" ]]'
ck "status: inputs invalid"                       '[[ "$(jq -c "[.inputs.state,.inputs.invalid]" <<<"$ROW")" == "[\"invalid\",1]" ]]'
ck "status: razões novas em review_reasons"       '[[ "$(jq -c ".review_reasons" <<<"$ROW")" == *sols_divergent:1* && "$(jq -c ".review_reasons" <<<"$ROW")" == *inputs_invalid:1* ]]'
ck "status: needs_review"                         'jq -e ".needs_review == true" <<<"$ROW" >/dev/null'
ck "status: não está pronto e diz por quê"        'jq -e ".ready == false and (.pending|index(\"sols_divergent:1\")) and (.pending|index(\"package_unchecked\"))" <<<"$ROW" >/dev/null'
ck "status: contagens novas"                      '[[ "$(jq -c "[.counts.ready,.counts.sols_divergent,.counts.inputs_invalid]" <<<"$BODY")" == "[0,1,1]" ]]'
get /problems/status "id=col%23pa" aut
ck "status ?id= estreita a um problema"           '[[ "$(jq -r ".problems|length" <<<"$BODY")" == 1 ]]'
get /problems/status "id=col%23outro" aut
ck "status ?id= de problema alheio/inexistente = vazio" '[[ "$(jq -r ".problems|length" <<<"$BODY")" == 0 ]]'

D="$(mktemp -d)"; printf 'TLMOD[java.drift]=0.02\n#TLMOD[cpp.drift]=9\nTLMOD[default.drift]="0.1"\nTLMOD[py3.drift]=.3\nTLMOD[java.drift]=0.05\n' > "$D/conf"
BODY="$(calx_drift "$D")"; rm -rf "$D"
ck "calx_drift: grep do conf (comentário fora, py3->py, última vence, aspas ok)" '[[ "$BODY" == "{\"java\":0.05,\"default\":0.1,\"py\":0.3}" ]]'

echo "== 3. problem_commit: mexeu no que a calibração exercita => sumário velho =="
printf 'y\n' > "$P/docs/enunciado.md"; problem_commit "$P" autor "só enunciado" >/dev/null
ck "editar só o enunciado NÃO marca"              'jq -e ".stale == false" "$SF" >/dev/null'
printf 'int main(){return 1;}\n' > "$P/sols/wrong/int32.c"; problem_commit "$P" autor "wrong nova" >/dev/null
ck "editar uma wrong marca stale"                 'jq -e ".stale == true" "$SF" >/dev/null'
ck "…e o mapa do Painel acompanha"                'jq -e ".[\"col#pa\"].stale == true" "$RUN/calib-summary.json" >/dev/null'
get /problems/status "" aut
ROW="$(jq -c '.problems[]|select(.id=="col#pa")' <<<"$BODY")"
ck "status: soluções 'stale' e sai de review_reasons" '[[ "$(jq -r .sols.state <<<"$ROW")" == stale && "$(jq -c .review_reasons <<<"$ROW")" != *sols_divergent* ]]'
ck "status: pendência sols_unchecked (o TL segue válido)" 'jq -e ".pending|index(\"sols_unchecked\")" <<<"$ROW" >/dev/null'
ck "status: entradas voltam a 'unknown'"          '[[ "$(jq -r .inputs.state <<<"$ROW")" == unknown ]]'

echo "== 4. tudo conforme + pacote conferido = pronto =="
rm -f "$P/sols/good/sol.py"; printf 'CALIBRATIONTL=5\n' > "$P/conf"; problem_commit "$P" autor "tira py" >/dev/null
TLC="$(pkg_tl_checksum "$P" 'col#pa')"
jq -cn --arg c "$TLC" '{problems:[{id:"col#pa",owner:"autor",repo:"col",prob:"pa",title:"PA",public:false,
   collaborators:[],collections:[],tl_checksum:$c,good_langs:["c"]}]}' > "$T/var/problem-owners.json"
tl_store_record juiz1 'col#pa' "$TLC" '{"c":"1.000","default":"1.000"}' >/dev/null
mkdir -p "$RUN/validation"; echo '{"id":"col#pa","ok":true,"checks":[{"name":"x","ok":true}],"at":1}' > "$RUN/validation/col#pa.json"
rm -f "$RUN/validation-summary.json"
get /judge/package-meta "id=col%23pa" mojw_segredo; VER="$(jq -r '.checksum // ""' <<<"$BODY")"
SOLS='[
 {"file":"sol.c","lang":"c","category":"good","verdict":"Accepted,100p","tests":[{"name":"t1","code":"AC","time":0.3}]},
 {"file":"lento.c","lang":"c","category":"slow","verdict":"Time Limit Exceeded,0p","tests":[{"name":"t1","code":"TLE","time":1.1}]},
 {"file":"int32.c","lang":"c","category":"wrong","verdict":"Wrong Answer,0p","tests":[{"name":"t1","code":"WA","time":0.1}]},
 {"file":"scripts/validator.cpp","lang":"cpp","category":"validator","verdict":"none","tests":[]}]'
post "$(jq -cn --arg c "$VER" --argjson s "$SOLS" '{host:"juiz1", id:"col#pa", checksum:$c, log:"x", sols:$s}')"
get /problems/status "id=col%23pa" aut
ROW="$(jq -c '.problems[0]' <<<"$BODY")"
ck "pronto: ready=true, pending vazio"            'jq -e ".ready == true and (.pending == [])" <<<"$ROW" >/dev/null'
ck "pronto: sols ok, entradas 'none' (sem validador não pesa)" '[[ "$(jq -c "[.sols.state,.inputs.state]" <<<"$ROW")" == "[\"ok\",\"none\"]" ]]'
ck "pronto: card 'prontos' = 1"                   '[[ "$(jq -r .counts.ready <<<"$BODY")" == 1 ]]'

echo "== 5. delete tira o sumário =="
calx_drop 'col#pa'
ck "calx_drop apaga o arquivo e a chave"          '[[ ! -e "$SF" ]] && [[ "$(jq -r "has(\"col#pa\")" "$RUN/calib-summary.json")" == false ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
