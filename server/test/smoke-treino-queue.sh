#!/bin/bash
# smoke-treino-queue.sh — GET /treino/admin/queue?details=1 (a fila de pendentes do painel do treino) e o
# count_pending (lib/users.sh) sem um processo POR CONTA / POR LINHA.
#
# XIV Maratona UnB (25/09/2026): a rota chegou a 8,6 s — o count_pending rodava um `grep -c` POR CONTA (o
# treino tem ~1.000) a cada vez que o cache sujava, e os detalhes um `$(wc -l)` + grep por conta e awk + tr +
# jq POR LINHA pendente. Prende: total certo; teto de 100 detalhes NA MESMA ORDEM do glob antigo (contas por
# nome, linhas na ordem do arquivo); estado no pipeline e fonte; e o nº de processos que NÃO cresce por conta.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"
NU=150   # contas do treino com pendência (> 100: exercita o teto e a ordem do recorte)
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; SHIM="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN" "$SHIM"' EXIT
source "$HERE/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" SPOOLDIR="$RUN/spool" SPOOLDONEDIR="$RUN/spool/done"
mkdir -p "$RUN/spool/done" "$RUN/queue" "$RUN/assigned" "$FIX/treino/var"; NOW=$EPOCHSECONDS
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nCONTEST_NAME=Treino\nCONTEST_END=%s\n' "$((NOW+86400))" > "$FIX/treino/conf"
fx_user "$FIX/treino" boss.admin p Boss >/dev/null; printf 'CONTEST=treino\nLOGIN=boss.admin\nUSERFULLNAME=B\nLOGINAT=1\n' > "$SESS/adm"
for i in $(seq -w 1 $NU); do u="aluno$i"; fx_user "$FIX/treino" $u p "A$i" >/dev/null
  { printf '%s:apc#p1:C:Accepted,100p:%s:ok%s\n' $((NOW-900)) $((NOW-900)) $i
    printf '%s:apc#p2:CPP:Not Answered Yet:%s:pd%s\n' $((NOW-600+10#$i)) $((NOW-600+10#$i)) $i; } > "$FIX/treino/users/$u/history"
  (( 10#$i % 3 == 0 )) && { mkdir -p "$FIX/treino/users/$u/submissions"; printf 'x' > "$FIX/treino/users/$u/submissions/pd$i.cpp"; }
done
touch "$RUN/queue/x"; mkdir -p "$RUN/queue/h"; : > "$RUN/queue/h/9_pd003.json"; : > "$RUN/spool/done/t:pd006:x"
C="$FIX/ct"; mkdir -p "$C/var"; printf 'CONTEST_ID=ct\nCONTEST_NAME=Prova\\ X\nCONTEST_TYPE=icpc\n' > "$C/conf"
fx_user "$C" t1 p T1 >/dev/null; printf '%s:ct#a:PY:Running:%s:r1\n%s:ct#b:C:Wrong Answer:%s:w1\n' $((NOW-50)) $((NOW-50)) $((NOW-40)) $((NOW-40)) > "$C/users/t1/history"
fx_user "$C" t2 p T2 >/dev/null; printf '%s:ct#a:C:On queue:%s:q2\n' $((NOW-30)) $((NOW-30)) > "$C/users/t2/history"
C3="$FIX/zz"; mkdir -p "$C3/var"; printf 'CONTEST_ID=zz\nCONTEST_TYPE=icpc\n' > "$C3/conf"; fx_user "$C3" u p U >/dev/null; printf '%s:zz#a:C:Accepted:%s:a1\n' $NOW $NOW > "$C3/users/u/history"
REALJQ="$(command -v jq)"
for b in grep jq wc awk tr; do printf '#!/bin/bash\necho %s >> "%s/n"\nexec "%s" "$@"\n' $b "$SHIM" "$(command -v $b)" > "$SHIM/$b"; chmod +x "$SHIM/$b"; done
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:-}"; ((fail++)); fi; }
rm -f "$FIX"/*/var/.pending-count; : > "$SHIM/n"
OUT="$(LC_ALL=C PATH="$SHIM:$PATH" PATH_INFO=/treino/admin/queue REQUEST_METHOD=GET QUERY_STRING='details=1' HTTP_AUTHORIZATION="Bearer adm" bash "$ROOT/api/v1/router.sh" </dev/null 2>/dev/null)"
BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; NP=$(wc -l < "$SHIM/n"); DBG="${BODY:0:300}"
echo "== total e contests =="
ck "total = 150 (treino) + 2 (ct); o contest sem pendência fica fora" '[[ "$("$REALJQ" .total_pending <<<"$BODY")" == 152 && "$("$REALJQ" -c "[.lists[] | {contest, pending}]" <<<"$BODY")" == "[{\"contest\":\"treino\",\"pending\":150},{\"contest\":\"ct\",\"pending\":2}]" ]]'
echo "== detalhes: teto de 100, na ordem do glob =="
ck "teto: 100 detalhes (há 152 pendentes)" '[[ "$("$REALJQ" ".pending_details|length" <<<"$BODY")" == 100 ]]'
ck "o recorte (QUAIS 100) = o do glob antigo: os 2 do ct (vem antes de treino) + aluno001…aluno098" '[[ "$("$REALJQ" -r "[.pending_details[] | .contest + \"/\" + .login] | (index(\"ct/t1\") != null) and (index(\"ct/t2\") != null) and (index(\"treino/aluno098\") != null) and (index(\"treino/aluno099\") == null)" <<<"$BODY")" == true ]]'
ck "estado no pipeline: na-fila (pd003), consumido-sem-veredicto (pd006), o resto sem-rastro" '[[ "$("$REALJQ" -r "[.pending_details[] | select(.id==\"pd003\" or .id==\"pd006\") | .state] | join(\",\")" <<<"$BODY")" == "na-fila,consumido-sem-veredicto" ]]'
ck "has_source: com o arquivo em submissions/ (a cada 3ª conta) true, sem false" '[[ "$("$REALJQ" -r "[.pending_details[] | select(.login==\"aluno003\" or .login==\"aluno004\") | .has_source] | join(\",\")" <<<"$BODY")" == "true,false" ]]'
ck "campos da linha: problem, lang, since" '[[ "$("$REALJQ" -r ".pending_details[] | select(.id==\"r1\") | [.problem, .lang, (.since|tostring)] | join(\"|\")" <<<"$BODY")" == "ct#a|PY|$((NOW-50))" ]]'
echo "== processos: não crescem por conta (eram ~4 por conta com pendência + 1 grep por conta no count_pending) =="
DBG="$NP processos"
ck "≤ 60 processos com 150 contas pendentes [$NP]" '(( NP <= 60 ))'
echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
