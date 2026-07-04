#!/bin/bash
# Testa a migração de um contest LEGADO (passwd + controle/history com probid em OFFSET/
# pontilhado + flat files) para o store por-usuário: store-migrate.sh --from ... --apply.
# Verifica contas (com .team), canonicalização do probid, roteamento de arquivos, metrics,
# publicação em CONTESTSDIR e os placares icpc/obi (frozen × full) gerados dos metrics.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"   # .../server
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
FROM="$FIX/legado"; TARGET="$FIX/contests"
mkdir -p "$FROM/mg/controle" "$FROM/mg/submissions" "$FROM/mg/mojlog" "$FROM/mg/results" \
         "$FROM/mg/data" "$FROM/mg/var/profiles" "$TARGET"

C="$FROM/mg"
{ printf 'CONTEST_ID=mg\nCONTEST_NAME="Migra"\nCONTEST_TYPE=icpc\n'
  printf 'CONTEST_START=1000000\nCONTEST_END=2000000\nFREEZE_TIME=1005000\n'
  printf "PROBS=(f0 col/p1 'Um' A 'col#p1' f1 col/p2 'Dois' B 'col#p2')\n"; } > "$C/conf"
{ printf 'mg.admin:p:Admin\n'
  printf 'alice:a:Alice A:al@x:br:UnB:TimeA:Universidade de Brasilia\n'
  printf 'bob:b:Bob\n'; } > "$C/passwd"
# history legado (7 campos): probid em OFFSET (0, 5) e pontilhado (col.p1)
{ printf '5:alice:0:C:Wrong Answer,0p:1000200:aa01\n'
  printf '23:alice:0:C:Accepted,100p:1001400:aa02\n'
  printf '10:bob:col.p1:C:Wrong Answer,40p:1000500:bb01\n'
  printf '90:bob:5:C:Accepted,100p:1006000:bb02\n'; } > "$C/controle/history"   # bb02 pós-freeze
# flat files: nome legado com epoch (aa01) e novo (aa02); mojlog sem extensão; result de aa02
echo 'int a;' > "$C/submissions/1000200:aa01-alice-A.c"
echo 'int b;' > "$C/submissions/aa02-alice-col#p1.c"
echo 'localhost 41050 x' > "$C/mojlog/1001400:aa02"
printf '{"id":"aa02","verdict":"Accepted,100p","report_html":"mojlog/velho.html"}' > "$C/results/aa02.json"
echo 'legacy' > "$C/data/alice"
printf '{"favorite_editor":"vim"}' > "$C/var/profiles/alice.json"

pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; ((fail++)); fi; }

echo "== dry-run não muda nada =="
CONTESTSDIR="$TARGET" bash "$ROOT/bin/store-migrate.sh" mg --from "$FROM" >/dev/null 2>&1
ck "dry-run não criou users/" '[[ ! -d "$C/users" || -z "$(ls -A "$C/users" 2>/dev/null)" ]]'
ck "dry-run não publicou" '[[ ! -e "$TARGET/mg" ]]'

echo "== apply =="
CONTESTSDIR="$TARGET" bash "$ROOT/bin/store-migrate.sh" mg --from "$FROM" --apply > "$FIX/out" 2>&1
M="$TARGET/mg"
ck "publicado em CONTESTSDIR" '[[ -d "$M/users" && ! -e "$FROM/mg" ]]'
ck "3 contas" '[[ "$(ls "$M/users" | wc -l)" == 3 ]]'
ck "team da alice (passwd 5-8)" '[[ "$(jq -r .team.name "$M/users/alice/account.json")" == "TimeA" && "$(jq -r .team.flag "$M/users/alice/account.json")" == "br" ]]'
ck "perfil mesclado (favorite_editor)" '[[ "$(jq -r .favorite_editor "$M/users/alice/account.json")" == "vim" ]]'
ck "bob sem team" '[[ "$(jq -r "has(\"team\")" "$M/users/bob/account.json")" == "false" ]]'
ck "history alice canonicalizado (0 -> col#p1)" '[[ "$(awk -F: "{print \$2}" "$M/users/alice/history" | sort -u)" == "col#p1" ]]'
ck "history bob canonicalizado (col.p1+5 -> col#p1,col#p2)" '[[ "$(awk -F: "{print \$2}" "$M/users/bob/history" | sort -u | paste -sd,)" == "col#p1,col#p2" ]]'
ck "submissão epoch-prefixada roteada" '[[ -f "$M/users/alice/submissions/aa01.c" ]]'
ck "submissão nova roteada" '[[ -f "$M/users/alice/submissions/aa02.c" ]]'
ck "mojlog roteado" '[[ -f "$M/users/alice/mojlog/aa02" ]]'
ck "result roteado + report_html reescrito" '[[ "$(jq -r .report_html "$M/users/alice/results/aa02.json")" == "mojlog/aa02.html" ]]'
ck "metrics da alice (solved col#p1)" '[[ "$(jq -r ".by_problem[\"col#p1\"].solved" "$M/users/alice/metrics.json")" == "true" ]]'
ck "legado em .legacy-store (controle,data,passwd,profiles)" '[[ -d "$M/.legacy-store/controle" && -e "$M/.legacy-store/data" && -f "$M/.legacy-store/passwd" && -e "$M/.legacy-store/var__profiles" ]]'
ck "flat dirs saíram da raiz" '[[ ! -d "$M/submissions" && ! -d "$M/mojlog" && ! -d "$M/results" ]]'
ck "sem USER_STORE no conf" '! grep -q "^USER_STORE=" "$M/conf"'
ck ".score-dirty tocado" '[[ -e "$M/var/.score-dirty" ]]'

echo "== placar icpc (frozen × full) =="
ck "placar.txt modo icpc" '[[ "$(head -1 "$M/var/placar.txt")" == icpc ]]'
# alice resolveu A pré-freeze com 2 tentativas: célula 2/23 (min = (1001400-1000000)/60)
ck "alice A = 2/23, total 1" 'grep -q ":alice:.*:2/23::1$" "$M/var/placar.txt"'
# bob: AC do B é pós-freeze -> frozen esconde (1/- pendente); full mostra 1/100
ck "frozen: bob sem solved" 'grep -q ":bob:.*:0$" "$M/var/placar.txt"'
ck "full: bob B = 1/100" 'grep -q ":bob:.*1/100:1$" "$M/var/placar-full.txt"'

echo "== placar obi (best_score dos metrics) =="
CONTESTSDIR="$TARGET" CONTEST_TYPE=obi bash "$ROOT/score/build.sh" mg >/dev/null 2>&1
ck "obi frozen: alice 100, bob 40:-" 'grep -q "^alice:.*:100:-:100$" "$M/var/placar.txt" && grep -q "^bob:.*:40:-:40$" "$M/var/placar.txt"'
ck "obi full: bob 40+100" 'grep -q "^bob:.*:40:100:140$" "$M/var/placar-full.txt"'

echo ""; echo "RESULT: $pass passed, $fail failed"
(( fail > 0 )) && { echo "--- saída da migração ---"; cat "$FIX/out"; }
exit $(( fail>0?1:0 ))
