#!/bin/bash
# smoke-submission-info.sh — /submission/info: a PÁGINA DA SUBMISSÃO do juiz (09/11/2026; Roberto e Paulo).
#   · id completo e PREFIXO (8+ hex): único = a submissão; ambíguo = 409 com os ids; desconhecido = 404;
#   · só juiz: time, outro time e .mon = 403;
#   · ANONIMATO: o juiz puro não recebe login/time/univ (nem pelo results JSON); chefe e admin recebem;
#   · pendente (sem results): sai do history; veredicto com ':' no history inteiro;
#   · revisão: estado e nº de votos; os votos só p/ o chefe;
#   · rodada ARQUIVADA: achada, com o minuto da rodada.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$HERE/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN"
NOW="$EPOCHSECONDS"; ST=$(( NOW - 3600 )); C="$FIX/si"; mkdir -p "$C/var" "$C/review"
{ printf 'CONTEST_ID=si\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\n' "$ST" "$(( NOW + 3600 ))"
  printf 'PROBS=( x col/pa Alfa A col#pa x col/pb Beta B col#pb )\n'; } > "$C/conf"
for u in dona outro si.judge si.cjudge si.admin si.mon; do fx_user "$C" "$u" s "$u"
  printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' si "$u" "$u" "$NOW" > "$SESS/tok-$u"; done
jq -c '.team={name:"Time da Dona", univ_short:"UNB"}' "$C/users/dona/account.json" > "$C/t" && mv "$C/t" "$C/users/dona/account.json"
D="$C/users/dona"
S1=0123456789abcdef0123456789abcdef   # julgada, com revisão e veredicto com ':' no history
S2=1111111111111111aaaaaaaaaaaaaaaa   # pendente (sem results)
S4=abcdef01aaaaaaaaaaaaaaaaaaaaaaaa; S5=abcdef01bbbbbbbbbbbbbbbbbbbbbbbb   # mesmo prefixo de 8
{ printf '%s:col#pa:CPP:Wrong Answer¦Resposta errada: confira o teste 2:%s:%s\n' $(( ST + 2820 )) $(( ST + 2820 )) "$S1"
  printf '%s:col#pb:PY:Not Answered Yet:%s:%s\n' $(( ST + 3000 )) $(( ST + 3000 )) "$S2"
  printf '%s:col#pa:CPP:Accepted:%s:%s\n' $(( ST + 100 )) $(( ST + 100 )) "$S4"
  printf '%s:col#pa:CPP:Accepted:%s:%s\n' $(( ST + 200 )) $(( ST + 200 )) "$S5"; } > "$D/history"
for s in "$S1" "$S2" "$S4" "$S5"; do printf 'int main(){}\n' > "$D/submissions/$s.cpp"; done
printf '<h1>R</h1>' | gzip -c > "$D/mojlog/$S1.html.gz"
jq -cn --arg id "$S1" '{host:"goiabada-judge", id:$id, contest:"si", problem_id:"col#pa", login:"dona", lang:"cpp",
  verdict:"Wrong Answer,25p", verdict_canon:"Wrong Answer", score:25, score_max:100, score_kind:"tests", correct:1,
  total_tests:4, duration_s:3, finalized_at:1, tests:[{name:"sample1",code:"AC",time:0.01,tl:1},{name:"t2",code:"WA",time:0.02,tl:1}]}' > "$D/results/$S1.json"
for s in "$S4" "$S5"; do jq -cn --arg id "$s" '{id:$id, login:"dona", lang:"cpp", verdict:"Accepted,100p", tests:[]}' > "$D/results/$s.json"; done
jq -cn --arg id "$S1" '{id:$id, status:"voting", computed_verdict:"Wrong Answer", conflict:false,
  votes:[{by:"si.judge", verdict:"Wrong Answer"}]}' > "$C/review/$S1.json"
# rodada arquivada
S3=2222222222222222bbbbbbbbbbbbbbbb; A="$C/rounds/aq1"; mkdir -p "$A/users/dona/results" "$A/users/dona/submissions" "$A/users/dona/mojlog"
jq -cn --argjson s $(( NOW - 90000 )) '{round:"aq1", start:$s}' > "$A/meta.json"
printf '%s:col#pb:C:Accepted:%s:%s\n' $(( NOW - 90000 + 600 )) $(( NOW - 90000 + 600 )) "$S3" > "$A/users/dona/history"
printf 'int main(){}\n' > "$A/users/dona/submissions/$S3.c"
jq -cn --arg id "$S3" '{id:$id, login:"dona", lang:"c", verdict:"Accepted,100p", verdict_canon:"Accepted", tests:[]}' > "$A/users/dona/results/$S3.json"

call(){ OUT="$(PATH_INFO=/submission/info REQUEST_METHOD=GET QUERY_STRING="contest=si&id=$2" HTTP_AUTHORIZATION="Bearer tok-$1" \
    bash "$ROUTER" 2>/dev/null)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${OUT:0:300}"; ((fail++)); fi; }
J(){ jq -r "$1" <<<"$BODY"; }

echo "== id completo, juiz puro: tudo para julgar, sem identidade =="
call si.judge "$S1"
ck "200 com o problema, a letra e o título"     '[[ "$(J ".problem_id + \" \" + .letter + \" \" + .title")" == "col#pa A Alfa" ]]'
ck "o minuto da prova (47)"                       '[[ "$(J .minute)" == 47 ]]'
ck "testes, juiz e pontos"                        '[[ "$(J ".tests | length")" == 2 && "$(J .host)" == goiabada-judge && "$(J .score)" == 25 ]]'
ck "ANÔNIMO: sem login/time/univ"                  '[[ "$(J ".anonymous")" == true && "$(J "has(\"login\") or has(\"team\") or has(\"univ\")")" == false ]]'
ck "o login do results JSON não vaza"             '! grep -q "\"dona\"" <<<"$BODY"'
ck "revisão: estado e votos_n, sem os votos"      '[[ "$(J .review.status)" == voting && "$(J .review.votes_n)" == 1 && "$(J ".review | has(\"votes\")")" == false ]]'
ck "has_source e has_log"                         '[[ "$(J .has_source)" == true && "$(J .has_log)" == true ]]'
echo "== chefe e admin: identidade e votos =="
call si.cjudge "$S1"
ck "chefe: login, time e univ"                    '[[ "$(J ".login + \"|\" + .team + \"|\" + .univ")" == "dona|Time da Dona|UNB" && "$(J .anonymous)" == false ]]'
ck "chefe: os votos"                              '[[ "$(J ".review.votes[0].by")" == si.judge ]]'
call si.admin "$S1";  ck "admin: identidade"      '[[ "$(J .login)" == dona ]]'
echo "== prefixo =="
call si.judge "${S1:0:8}";  ck "prefixo único (8 hex) = a submissão" '[[ "$(J .id)" == "$S1" ]]'
call si.judge "abcdef01";   ck "prefixo ambíguo = 409 com os 2 ids"  '[[ "$OUT" == *"Status: 409"* && "$(J ".error.code")" == ambiguous && "$(J ".error.ids | length")" == 2 ]]'
call si.judge "abcdef01a";  ck "1 caractere a mais desempata"         '[[ "$(J .id)" == "$S4" ]]'
call si.judge "ffffffff";   ck "desconhecido = 404"                    '[[ "$OUT" == *"Status: 404"* ]]'
call si.judge "xyz";        ck "id inválido = 400"                     '[[ "$OUT" == *"Status: 400"* ]]'
echo "== quem não é juiz =="
call dona "$S1";    ck "o próprio time: 403"   '[[ "$OUT" == *"Status: 403"* ]]'
call outro "$S1";   ck "outro time: 403"       '[[ "$OUT" == *"Status: 403"* ]]'
call si.mon "$S1";  ck ".mon: 403"             '[[ "$OUT" == *"Status: 403"* ]]'
echo "== pendente e veredicto com ':' =="
call si.judge "$S2"
ck "pendente: do history, sem testes"            '[[ "$(J .pending)" == true && "$(J .verdict)" == "Not Answered Yet" && "$(J ".tests | length")" == 0 && "$(J .lang)" == PY ]]'
ck "pendente: a letra B"                          '[[ "$(J .letter)" == B ]]'
mv "$D/results/$S1.json" "$RUN/s1.json"; call si.judge "$S1"; mv "$RUN/s1.json" "$D/results/$S1.json"
ck "veredicto com ':' no history: só a classe, inteira" '[[ "$(J .verdict)" == "Wrong Answer" ]]'
echo "== rodada arquivada =="
call si.judge "$S3"
ck "achada, com a rodada e o minuto dela (10)"   '[[ "$(J .round)" == aq1 && "$(J .minute)" == 10 && "$(J .verdict_canon)" == Accepted ]]'
call si.judge "${S3:0:10}"; ck "prefixo acha a arquivada" '[[ "$(J .id)" == "$S3" ]]'
echo; echo "RESULT: $pass passed, $fail failed"; (( fail == 0 ))
