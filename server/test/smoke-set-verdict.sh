#!/bin/bash
# smoke-set-verdict.sh — /contest/set-verdict (a troca de veredicto da página Avaliar nos contests SEM veredicto manual)
# de ponta a ponta: a rota → o spool → o daemon (judged.sh --drain) → o history do aluno. Até 16/11/2026 a rota
# respondia "queued" sem o id da submissão e o daemon descartava o pedido ("submissão não achada"): os testes só
# olhavam o "queued". Afirma:
#   • a troca chega ao history (a linha da submissão muda, as outras não) e ao results/<id>.json (host manual);
#   • sem id = 400 id_required; id que não é do aluno = 404; de outro problema = 422; em julgamento = 409 (o resultado
#     do juiz chegaria depois e apagaria a troca) — e nada vai ao spool;
#   • juiz comum não troca (403 chief_required); string livre = 422 verdict_invalid.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export SPOOLDIR="$RUN/spool/submissions" SPOOLDONEDIR="$RUN/spool/submissions-done"; mkdir -p "$SPOOLDIR" "$SPOOLDONEDIR"
C="$FIX/sv"; mkdir -p "$C/var"
NOW="$(date +%s)"; OLD=$(( NOW - 1200 ))
printf 'CONTEST_ID=sv\nCONTEST_TYPE=treino\nCONTEST_START=%s\nCONTEST_END=%s\nPROBS=( x col#pa Alfa A col#pa x col#pb Beta B col#pb )\n' \
  "$((NOW-3600))" "$((NOW+3600))" > "$C/conf"
fx_user "$C" sv.admin  p Admin
fx_user "$C" j1.judge  p Juiz
fx_user "$C" cj.cjudge p Chefe
fx_user "$C" aluno     a Aluno
A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; P=cccccccccccccccccccccccccccccccc
{ printf '%s:col#pa:C:Accepted,100p:%s:%s\n' "$OLD" "$OLD" "$A"
  printf '%s:col#pb:C:Wrong Answer,0p:%s:%s\n' "$((OLD+10))" "$((OLD+10))" "$B"
  printf '%s:col#pa:C:Not Answered Yet:%s:%s\n' "$((OLD+20))" "$((OLD+20))" "$P"; } > "$C/users/aluno/history"
for s in adm:sv.admin j1:j1.judge cj:cj.cjudge; do printf 'CONTEST=sv\nLOGIN=%s\nUSERFULLNAME=x\nLOGINAT=1\n' "${s#*:}" > "$SESS/${s%%:*}"; done
call(){ OUT="$(PATH_INFO=/contest/set-verdict REQUEST_METHOD=POST QUERY_STRING="contest=sv" HTTP_AUTHORIZATION="Bearer ${2:-adm}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"$1" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
code(){ jq -r '.error.code // empty' <<<"$BODY" 2>/dev/null; }
spooln(){ find "$SPOOLDIR" -name '*setverdict*' | wc -l; }
drain(){ ( cd "$ROOT/daemons" && CONTESTSDIR="$FIX" RUNDIR="$RUN" JUDGE_BACKEND=queue INTAKE_MODE=queue bash judged.sh --drain >/dev/null 2>&1 ); }
line(){ grep ":$1$" "$C/users/aluno/history"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

echo "== recusas (nada vai ao spool) =="
call '{"problem_id":"col#pa","verdict":"Wrong Answer","username":"aluno"}'
ck "sem id: 400 id_required (era o 'queued' que o daemon descartava)" '[[ "$OUT" == *"Status: 400"* && "$(code)" == id_required ]]'
call "{\"id\":\"$(printf d%.0s {1..32})\",\"verdict\":\"Wrong Answer\",\"username\":\"aluno\"}"
ck "id que não está no history do aluno: 404"       '[[ "$OUT" == *"Status: 404"* && "$(code)" == submission_notfound ]]'
call "{\"id\":\"$A\",\"problem_id\":\"col#pb\",\"verdict\":\"Wrong Answer\",\"username\":\"aluno\"}"
ck "submissão de outro problema: 422"               '[[ "$OUT" == *"Status: 422"* && "$(code)" == problem_mismatch ]]'
call "{\"id\":\"$P\",\"verdict\":\"Accepted\",\"username\":\"aluno\"}"
ck "submissão em julgamento: 409"                   '[[ "$OUT" == *"Status: 409"* && "$(code)" == submission_pending ]]'
call "{\"id\":\"$A\",\"verdict\":\"Banana\",\"username\":\"aluno\"}"
ck "string livre: 422 verdict_invalid"              '[[ "$(code)" == verdict_invalid ]]'
call "{\"id\":\"$A\",\"verdict\":\"Wrong Answer\",\"username\":\"aluno\"}" j1
ck "juiz comum: 403 chief_required"                 '[[ "$(code)" == chief_required ]]'
call "{\"id\":\"../x\",\"verdict\":\"Wrong Answer\",\"username\":\"aluno\"}"
ck "id malformado: 400 id_invalid"                  '[[ "$(code)" == id_invalid ]]'
ck "nenhuma recusa foi ao spool"                    '[[ "$(spooln)" == 0 ]]'

echo "== a troca chega ao history =="
call "{\"id\":\"$A\",\"problem_id\":\"col#pa\",\"verdict\":\"Wrong Answer\",\"username\":\"aluno\"}"
ck "admin: queued, com o id da submissão"           '[[ "$(jq -r .status <<<"$BODY")" == queued && "$(jq -r .id <<<"$BODY")" == "$A" ]]'
ck "…um setverdict no spool, com o id da submissão"  '[[ "$(spooln)" == 1 ]] && grep -q "\"id\":\"$A\"" "$(find "$SPOOLDIR" -name "*setverdict*")"'
drain
ck "o daemon aplicou: a linha da submissão virou Wrong Answer" '[[ "$(line $A | cut -d: -f4)" == "Wrong Answer" ]]'
ck "…as outras linhas não mudaram"                  '[[ "$(line $B | cut -d: -f4)" == "Wrong Answer,0p" && "$(line $P | cut -d: -f4)" == "Not Answered Yet" ]]'
ck "…results/<id>.json com host manual"             '[[ "$(jq -r .host "$C/users/aluno/results/$A.json" 2>/dev/null)" == manual ]]'
ck "…o spool foi consumido"                         '[[ "$(spooln)" == 0 ]]'
call "{\"id\":\"$B\",\"verdict\":\"Accepted\",\"username\":\"aluno\"}" cj
drain
ck "juiz-chefe, sem problem_id (vem do history): B virou Accepted" '[[ "$(line $B | cut -d: -f4)" == Accepted ]]'
ck "auditado com o id da submissão"                 'grep -qP "\tset-verdict\tid=$B user=aluno prob=col#pb verdict=Accepted" "$C/var/admin-audit.log"'

echo "== retida na revisão manual: pode =="
mkdir -p "$C/review"; printf '{"id":"%s","login":"aluno","problem_id":"col#pa","status":"open","votes":[],"claimants":[]}' "$P" > "$C/review/$P.json"
call "{\"id\":\"$P\",\"verdict\":\"Accepted\",\"username\":\"aluno\"}"
ck "em revisão (Not Answered Yet + review/<id>.json): queued" '[[ "$(jq -r .status <<<"$BODY")" == queued ]]'
drain
ck "…aplicou e a revisão foi liberada"              '[[ "$(line $P | cut -d: -f4)" == Accepted && "$(jq -r .status "$C/review/$P.json")" == released ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
