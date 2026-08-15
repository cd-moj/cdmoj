#!/bin/bash
# Item 7: jplag — runner (roda java no jar) + handlers (run/results/match).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
JAR="${JPLAG_JAR:-/opt/moj/jplag/jplag-3.0.0-jar-with-dependencies.jar}"
command -v java >/dev/null 2>&1 || { echo "SKIP: sem java"; exit 0; }
[[ -f "$JAR" ]] || { echo "SKIP: sem jar"; exit 0; }
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
C="$FIX/jp"; mkdir -p "$C"
printf 'CONTEST_ID=jp\nCONTEST_TYPE=icpc\n' > "$C/conf"
# Store por-usuário: account.json + history próprio + submissions/<subid>.<ext> (SEM login no
# nome do arquivo). É o que o jplag-run.sh lê de fato — emit_history_stream (users/*/history) e
# user_dir/submissions/<subid>.* . NÃO existe passwd nem controle/history global.
fx_user "$C" jp.admin p "Admin"
fx_user "$C" alice a "Alice"
fx_user "$C" bob   b "Bob"
fx_user "$C" carol c "Carol"
printf 'CONTEST=jp\nLOGIN=jp.admin\nLOGINAT=1\n' > "$SESS/adm"
printf 'CONTEST=jp\nLOGIN=alice\nLOGINAT=1\n' > "$SESS/usr"
# alice e bob: código idêntico; carol: diferente
cat > "$C/users/alice/submissions/SID1.c" <<'EOF'
#include <stdio.h>
int soma(int a,int b){return a+b;}
int main(){int n,i,x,t=0;scanf("%d",&n);for(i=0;i<n;i++){scanf("%d",&x);t=soma(t,x);}printf("%d\n",t);return 0;}
EOF
cp "$C/users/alice/submissions/SID1.c" "$C/users/bob/submissions/SID2.c"
cat > "$C/users/carol/submissions/SID3.c" <<'EOF'
#include <stdio.h>
#include <string.h>
int main(){char buf[256];int cont=0;while(scanf("%255s",buf)==1){if(strlen(buf)>3)cont++;}printf("total %d\n",cont);return 0;}
EOF
# history por-usuário: 6 campos, login IMPLÍCITO (tempo:probid:lang:verdict:sub_epoch:subid)
printf '5:P:C:Accepted,100p:1718000000:SID1\n' > "$C/users/alice/history"
printf '6:P:C:Accepted,100p:1718000001:SID2\n' > "$C/users/bob/history"
printf '7:P:C:Accepted,100p:1718000002:SID3\n' > "$C/users/carol/history"

pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; ((fail++)); fi; }
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-adm}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }

echo "== runner (roda java) =="
CONTESTSDIR="$FIX" JPLAG_JAR="$JAR" bash "$ROOT/score/jplag-run.sh" jp >/dev/null 2>&1
R="$(ls "$C/jplag"/r-*.json 2>/dev/null | head -1)"
ck "gerou resultado"        '[[ -n "$R" ]]'
ck "status concluído"       '[[ "$(jq -r .running "$C/jplag/status.json" 2>/dev/null)" == "false" ]]'
ck "par alice-bob ~100%"    '[[ -n "$R" ]] && [[ "$(jq -r "[.pairs[]|select((.a==\"alice\" and .b==\"bob\") or (.a==\"bob\" and .b==\"alice\"))][0].similarity" "$R" 2>/dev/null | cut -d. -f1)" -ge 90 ]]'
ck "run gravou users.json"  '[[ -n "$R" ]] && [[ -s "$C/jplag/$(jq -r .run "$R")/users.json" ]]'
ck "par traz nome do time (a_name)" '[[ -n "$R" ]] && jq -e "[.pairs[]|select(.a_name==\"Alice\" or .b_name==\"Alice\")]|length>=1" "$R" >/dev/null'
ck "par traz login literal (a_login)" '[[ -n "$R" ]] && jq -e "[.pairs[]|select(.a_login==\"alice\" or .b_login==\"alice\")]|length>=1" "$R" >/dev/null'

echo "== handlers =="
call /contest/admin/jplag-results GET '' adm 'contest=jp'
ck "results: status + >=1 resultado" '[[ "$(jq -r ".status.running" <<<"$BODY")" == "false" && "$(jq -r ".results|length" <<<"$BODY")" -ge 1 ]]'
call /contest/admin/jplag-results GET '' usr 'contest=jp'
ck "não-admin 403"          '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/admin/jplag-run POST '{}' adm 'contest=jp'
ck "run dispara"            '[[ "$(jq -r .started <<<"$BODY")" == "true" ]]'

echo "== resposta GRANDE (regressão do 200 vazio) =="
# O agregado de r-*.json cresce com o nº de pares; acima de 128KiB o --argjson do jq estoura
# e a resposta saía 200 com corpo VAZIO (o front só dizia "Resposta inválida do servidor").
# Prova real: esquenta 2026, 22 problemas × 552 pares nomeados = 138KB. Aqui sintetizamos
# ~600 pares (>150KB) e exigimos JSON VÁLIDO com todos os resultados.
python3 - "$C/jplag" <<'PY' 2>/dev/null || jq -n '[range(0;30)]' >/dev/null
import json, sys, os
d = sys.argv[1]
for p in range(6):
    pairs = [{"a": f"time-fulano-de-tal-{i:04d}", "b": f"time-beltrano-da-silva-{i:04d}",
              "similarity": 42.5, "match": f"match-{i:04d}.html",
              "a_login": f"time-fulano-de-tal-{i:04d}", "b_login": f"time-beltrano-da-silva-{i:04d}",
              "a_name": "Equipe Fulano de Tal da Universidade", "b_name": "Equipe Beltrano da Silva",
              "a_univ": "UNIVERSIDADE FEDERAL EXEMPLO", "b_univ": "UNIVERSIDADE FEDERAL EXEMPLO"}
             for i in range(100)]
    json.dump({"problem": f"big#p{p}", "lang": "c", "run": "run-big", "pairs": pairs},
              open(os.path.join(d, f"r-big{p}.json"), "w"))
PY
BIG="$(cat "$C/jplag"/r-*.json | wc -c)"
ck "fixture passou de 128KiB"  '(( BIG > 131072 ))'
call /contest/admin/jplag-results GET '' adm 'contest=jp'
ck "resposta 200"              '[[ "$OUT" == *"Status: 200"* ]]'
ck "corpo é JSON de sucesso"   'jq -e ".success == true" >/dev/null 2>&1 <<<"$BODY"'
ck "traz os 6 resultados novos" '[[ "$(jq -r "[.results[]|select(.problem|startswith(\"big#\"))]|length" <<<"$BODY")" == 6 ]]'
ck "e os 600 pares"            '[[ "$(jq -r "[.results[]|select(.problem|startswith(\"big#\")).pairs|length]|add" <<<"$BODY")" == 600 ]]'
rm -f "$C/jplag"/r-big*.json

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
