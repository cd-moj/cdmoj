#!/bin/bash
# Fila de revisão do veredicto manual: visibilidade dos votos (juiz comum não vê; admin e
# chief veem), claim/vote, conflito, resolve/override do admin (libera setverdict + audita)
# e o placar COMPLETO (sem freeze) p/ .cjudge (is_judge cobre o juiz-chefe).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; SPOOL="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$SPOOL"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
C="$FIX/rv"; mkdir -p "$C/review" "$C/var"
NOW="$(date +%s)"; OLD=$(( NOW - 1200 ))
printf 'CONTEST_ID=rv\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nMANUAL_VERDICT=1\n' "$((NOW-3600))" "$((NOW+3600))" > "$C/conf"
fx_user "$C" rv.admin  p Admin
fx_user "$C" j1.judge  p "Juiz Um"
fx_user "$C" j2.judge  p "Juiz Dois"
fx_user "$C" cj.cjudge p Chefe
fx_user "$C" aluno1    a Aluno
mkrev(){ printf '%s' "{\"id\":\"$1\",\"login\":\"aluno1\",\"problem_id\":\"apc#p1\",\"lang\":\"C\",\"computed_verdict\":\"Wrong Answer\",\"status\":\"open\",\"conflict\":false,\"created_at\":$OLD,\"sub_epoch\":$OLD,\"claimants\":[],\"votes\":[]}" > "$C/review/$1.json"; }
mkrev r1; mkrev r2
for s in adm:rv.admin j1:j1.judge j2:j2.judge cj:cj.cjudge alu:aluno1; do
  printf 'CONTEST=rv\nLOGIN=%s\nUSERFULLNAME=x\nLOGINAT=1\n' "${s#*:}" > "$SESS/${s%%:*}"
done
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-adm}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" SPOOLDIR="$SPOOL" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

echo "== list: gates e visibilidade dos votos =="
call /contest/review/list GET '' alu 'contest=rv'
ck "aluno não vê a fila (403)"    '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/review/list GET '' j1 'contest=rv'
ck "juiz vê 2 itens, manual on"   '[[ "$(jq -r ".items|length" <<<"$BODY")" == 2 && "$(jq -r .manual <<<"$BODY")" == true ]]'
ck "counts: 2 não avaliadas"      '[[ "$(jq -r .counts.not_evaluated <<<"$BODY")" == 2 ]]'
ck "idade disponível (created_at)" '[[ "$(jq -r ".items[0].created_at" <<<"$BODY")" == "$OLD" ]]'
ck "juiz comum NÃO vê o login do competidor" '[[ "$(jq -r ".items[0].login" <<<"$BODY")" == null ]]'

echo "== claim + vote (j1) =="
call /contest/review/claim POST '{"id":"r1","action":"claim"}' j1 'contest=rv'
ck "j1 pegou r1"                  '[[ "$(jq -r .updated.status <<<"$BODY")" == claimed ]]'
call /contest/review/list GET '' j2 'contest=rv'
ck "j2 vê quem pegou (claimants)" '[[ "$(jq -r ".items[]|select(.id==\"r1\").claimants[0].by" <<<"$BODY")" == "j1.judge" ]]'
call /contest/review/vote POST '{"id":"r1","label":"5 - NO - Wrong answer"}' j1 'contest=rv'
ck "voto do j1 registrado"        '[[ "$(jq -r .status <<<"$BODY")" == voting ]]'
call /contest/review/list GET '' j2 'contest=rv'
ck "juiz comum NÃO vê os votos"   '[[ "$(jq -r ".items[]|select(.id==\"r1\").votes" <<<"$BODY")" == null && "$(jq -r ".items[]|select(.id==\"r1\").votes_n" <<<"$BODY")" == 1 ]]'
call /contest/review/list GET '' adm 'contest=rv'
ck "ADMIN vê os votos"            '[[ "$(jq -r ".items[]|select(.id==\"r1\").votes[0].by" <<<"$BODY")" == "j1.judge" ]]'
ck "ADMIN vê o login do competidor" '[[ "$(jq -r ".items[0].login" <<<"$BODY")" == aluno1 ]]'
call /contest/review/list GET '' cj 'contest=rv'
ck "chefe vê os votos"            '[[ "$(jq -r ".items[]|select(.id==\"r1\").votes[0].by" <<<"$BODY")" == "j1.judge" ]]'

echo "== conflito + resolve do admin =="
call /contest/review/claim POST '{"id":"r1","action":"claim"}' j2 'contest=rv'
call /contest/review/vote POST '{"id":"r1","label":"1 - YES"}' j2 'contest=rv'
ck "votos diferentes => conflito" '[[ "$(jq -r .status <<<"$BODY")" == conflict ]]'
call /contest/review/resolve POST '{"id":"r1","verdict":"5 - NO - Wrong answer"}' j1 'contest=rv'
ck "juiz comum não resolve (403)" '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/review/resolve POST '{"id":"r1","verdict":"5 - NO - Wrong answer"}' adm 'contest=rv'
ck "admin resolve o conflito"     '[[ "$(jq -r .status <<<"$BODY")" == released && "$(jq -r .released_verdict <<<"$BODY")" == "Wrong Answer" ]]'
ck "setverdict enfileirado"       'ls "$SPOOL" | grep -q setverdict'
ck "auditado (review-resolve)"    'grep -q "review-resolve" "$C/var/admin-audit.log"'

echo "== override do admin SEM conflito (r2 sem votos) =="
call /contest/review/resolve POST '{"id":"r2","verdict":"1 - YES"}' adm 'contest=rv'
ck "override direto => released"  '[[ "$(jq -r .status <<<"$BODY")" == released && "$(jq -r .released_verdict <<<"$BODY")" == Accepted ]]'
call /contest/review/resolve POST '{"id":"r2","verdict":"1 - YES"}' adm 'contest=rv'
ck "resolver de novo => 409"      '[[ "$OUT" == *"Status: 409"* ]]'
call /contest/review/list GET '' adm 'contest=rv'
ck "released some da fila"        '[[ "$(jq -r ".items|length" <<<"$BODY")" == 0 ]]'

echo "== opções com 3 campos: classe das 6 + texto p/ o time (final-verdicts) =="
call /contest/final-verdicts POST '{"options":[{"label":"1 - YES","verdict":"Accepted","team":"ignorado"},{"label":"7 - NO - Formato","verdict":"Wrong Answer","team":"Formato de saída errado"},{"label":"8 - NO - Lento","verdict":"Time Limit Exceeded"}]}' cj 'contest=rv'
ck "chefe grava opções com team"  '[[ "$(jq -r .saved <<<"$BODY")" == true && "$(jq -r ".options[1].team" <<<"$BODY")" == "Formato de saída errado" ]]'
ck "Accepted nunca leva team"     '[[ "$(jq -r ".options[0].team" <<<"$BODY")" == "" ]]'
call /contest/final-verdicts POST '{"options":[{"label":"x","verdict":"Banana"}]}' cj 'contest=rv'
ck "classe fora das 6 => 422 verdict_invalid" '[[ "$OUT" == *"Status: 422"* && "$(jq -r .error.code <<<"$BODY")" == verdict_invalid ]]'
call /contest/final-verdicts POST '{"options":[{"label":"x","verdict":"Wrong Answer","team":"com:dois pontos"}]}' cj 'contest=rv'
ck "team com ':' => 422"          '[[ "$OUT" == *"Status: 422"* ]]'
call /contest/final-verdicts GET '' j1 'contest=rv'
ck "GET traz classes (6) e team"  '[[ "$(jq -r ".classes|length" <<<"$BODY")" == 6 && "$(jq -r ".options[1].team" <<<"$BODY")" == "Formato de saída errado" ]]'
printf '[{"label":"6 - NO - Contact staff","verdict":"Contact staff"},"Presentation Error"]' > "$C/final-verdicts.json"
call /contest/final-verdicts GET '' j1 'contest=rv'
ck "arquivo LEGADO: verdict fora das 6 vira Wrong Answer + team" '[[ "$(jq -r ".options[0].verdict" <<<"$BODY")" == "Wrong Answer" && "$(jq -r ".options[0].team" <<<"$BODY")" == "Contact staff" && "$(jq -r ".options[1].team" <<<"$BODY")" == "Presentation Error" ]]'
call /contest/final-verdicts POST '{"options":[{"label":"1 - YES","verdict":"Accepted"},{"label":"7 - NO - Formato","verdict":"Wrong Answer","team":"Formato de saída errado"}]}' cj 'contest=rv'
mkrev r3
call /contest/review/resolve POST '{"id":"r3","verdict":"7 - NO - Formato"}' cj 'contest=rv'
ck "resolve com opção de texto => classe¦texto no released_verdict" '[[ "$(jq -r .released_verdict <<<"$BODY")" == "Wrong Answer¦Formato de saída errado" ]]'
ck "spool leva classe¦texto"      'grep -l "Formato de saída errado" "$SPOOL"/*setverdict* >/dev/null'
call /contest/set-verdict POST '{"problem_id":"apc#p1","verdict":"Banana","username":"aluno1"}' cj 'contest=rv'
ck "set-verdict legado NÃO aceita string livre (422)" '[[ "$OUT" == *"Status: 422"* ]]'
call /contest/set-verdict POST '{"problem_id":"apc#p1","verdict":"7 - NO - Formato","username":"aluno1"}' cj 'contest=rv'
ck "set-verdict legado pelo label => enfileirado" '[[ "$(jq -r .status <<<"$BODY")" == queued ]]'
call /contest/auto-verdicts GET '' cj 'contest=rv'
ck "auto-verdicts: vocabulário = as 6 classes" '[[ "$(jq -r ".verdicts|length" <<<"$BODY")" == 6 ]]'

echo "== leitores: o TIME vê o texto; placar/estatística veem a classe =="
ID9="99999999999999999999999999999999"; ID8="88888888888888888888888888888888"
printf '%s:apc#p1:C:Wrong Answer¦Formato de saída errado:%s:%s\n' "$OLD" "$OLD" "$ID9" >> "$C/users/aluno1/history"
printf '%s:apc#p1:C:Accepted,100p:%s:%s\n' "$((OLD+10))" "$((OLD+10))" "$ID8" >> "$C/users/aluno1/history"
call /contest/history GET '' alu 'contest=rv'
ck "history do time mostra o TEXTO (sem classe, sem ¦)" '[[ "$(grep ":$ID9$" <<<"$BODY" | cut -d: -f5)" == "Formato de saída errado" ]]'
ck "e o Accepted canônico"        '[[ "$(grep ":$ID8$" <<<"$BODY" | cut -d: -f5)" == "Accepted" ]]'
mkdir -p "$C/users/aluno1/results" "$C/users/aluno1/submissions"; : > "$C/users/aluno1/submissions/$ID9.c"
printf '{"id":"%s","contest":"rv","problem_id":"apc#p1","login":"aluno1","lang":"C","verdict":"Wrong Answer¦Formato de saída errado","host":"manual"}' "$ID9" > "$C/users/aluno1/results/$ID9.json"
printf 'SHOWLOG=1\n' >> "$C/conf"   # em icpc o summary do competidor é oculto sem SHOWLOG explícito (anti-leak)
call /submission/summary GET '' alu "contest=rv&ids=$ID9"
ck "summary do time: verdict=texto, verdict_canon=classe" '[[ "$(jq -r ".[\"$ID9\"].verdict" <<<"$BODY")" == "Formato de saída errado" && "$(jq -r ".[\"$ID9\"].verdict_canon" <<<"$BODY")" == "Wrong Answer" ]]'
call /contest/allsubmissions GET '' adm 'contest=rv'
ck "allsubmissions (juiz/admin) traz a string crua classe¦texto" '[[ "$BODY" == *"Wrong Answer¦Formato de saída errado"* ]]'
( source "$ROOT/api/v1/lib/verdict.sh"
  jq -rn "$VERDICT_CANON_JQ"'"Time Limit Exceeded¦Lento" | vcanon' ) > "$FIX/vc.txt"
ck "vcanon classifica pela classe"  '[[ "$(cat "$FIX/vc.txt")" == "Time Limit Exceeded" ]]'
( source "$ROOT/api/v1/lib/verdict.sh"; source "$ROOT/api/v1/lib/common.sh" 2>/dev/null; source "$ROOT/api/v1/lib/users.sh"
  CONTESTSDIR="$FIX" metrics_recompute rv aluno1 >/dev/null 2>&1
  jq -r '.by_verdict["Wrong Answer"] // 0, .accepted' "$C/users/aluno1/metrics.json" ) > "$FIX/m.txt" 2>/dev/null
ck "metrics: by_verdict agrupa pela classe e conta o AC" '[[ "$(sed -n 1p "$FIX/m.txt")" == 1 && "$(sed -n 2p "$FIX/m.txt")" == 1 ]]'

echo "== placar completo (sem freeze) p/ .cjudge =="
printf 'icpc\nCONGELADO\n' > "$C/var/placar.txt"
printf 'icpc\nCOMPLETO\n' > "$C/var/placar-full.txt"
call /contest/score GET '' cj 'contest=rv'
ck ".cjudge vê o placar COMPLETO" '[[ "$OUT" == *COMPLETO* ]]'
call /contest/score GET '' alu 'contest=rv'
ck "aluno vê o congelado"         '[[ "$OUT" == *CONGELADO* && "$OUT" != *COMPLETO* ]]'


echo "== set-verdict: sobrescrever veredicto é ato de CHEFIA (gate fechado 2026-08-20) =="
# a UI já escondia a coluna do juiz puro, mas a rota aceitava qualquer is_judge: por curl um
# juiz comum sobrescrevia veredicto de time sozinho, fora do quórum.
call /contest/set-verdict POST '{"problem_id":"apc#p1","verdict":"Accepted","username":"aluno1"}' j1 'contest=rv'
ck "juiz puro NÃO sobrescreve"    '[[ "$OUT" == *chief_required* ]]'
call /contest/set-verdict POST '{"problem_id":"apc#p1","verdict":"Accepted","username":"aluno1"}' cj 'contest=rv'
ck "juiz-chefe sobrescreve"       '[[ "$OUT" == *queued* ]]'
call /contest/set-verdict POST '{"problem_id":"apc#p1","verdict":"Accepted","username":"aluno1"}' adm 'contest=rv'
ck "admin sobrescreve"            '[[ "$OUT" == *queued* ]]'


echo "== desligar o veredicto manual NÃO pode deixar submissão presa (bug 2026-08-20) =="
# sobras: r3 sem voto (ninguém contestou -> sai com o computado) e r4 em conflito (dois humanos
# discordaram -> FICA p/ o chefe decidir)
printf '%s' "{\"id\":\"r3\",\"login\":\"aluno1\",\"problem_id\":\"apc#p1\",\"lang\":\"C\",\"computed_verdict\":\"Accepted\",\"status\":\"open\",\"conflict\":false,\"created_at\":$OLD,\"sub_epoch\":$OLD,\"claimants\":[],\"votes\":[]}" > "$C/review/r3.json"
printf '%s' "{\"id\":\"r4\",\"login\":\"aluno1\",\"problem_id\":\"apc#p1\",\"lang\":\"C\",\"computed_verdict\":\"Accepted\",\"status\":\"conflict\",\"conflict\":true,\"created_at\":$OLD,\"sub_epoch\":$OLD,\"claimants\":[],\"votes\":[{\"by\":\"j1.judge\",\"verdict\":\"Accepted\"},{\"by\":\"j2.judge\",\"verdict\":\"Wrong Answer\"}]}" > "$C/review/r4.json"
call /contest/admin/settings POST '{"manual_verdict":false}' adm 'contest=rv'
ck "resposta diz quantas liberou"  '[[ "$OUT" == *\"review_released\":1* ]]'
ck "e quantas ficaram p/ o chefe"  '[[ "$OUT" == *\"review_pending\":1* ]]'
ck "a sem voto saiu com o computado" '[[ "$(jq -r .status "$C/review/r3.json")" == released && "$(jq -r .released_verdict "$C/review/r3.json")" == "Accepted" ]]'
ck "o conflito NÃO foi atropelado"   '[[ "$(jq -r .status "$C/review/r4.json")" != released ]]'
ck "o setverdict foi p/ o spool"     'grep -lF "\"id\":\"r3\"" "$SPOOL"/rv:*:setverdict:* >/dev/null 2>&1 || grep -rlF "r3" "$SPOOL" >/dev/null 2>&1'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
