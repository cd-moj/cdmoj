#!/bin/bash
# smoke-esqueletos.sh — módulo `esqueletos` do contest (lib/esqueletos.sh; issue #40, decisões de 30/09/2026):
#   • catálogo + mod_detect (arquivo com linguagens = "dados presentes");
#   • o módulo EXIGE o editor embutido NAS DUAS DIREÇÕES: ligar sem editor = 422 editor_required; desligar o
#     editor com o módulo ligado = 409 module_needs_editor SEM gravar nada (nem os outros campos do POST);
#     criar/duplicar com show_editor:false + esqueletos = 422; conf editado à mão = módulo sem efeito;
#   • /contest/admin/esqueletos: set/off/reset, código vazio = off, linguagem inválida/grande demais = 422,
#     gravar LIGA o módulo, auditado; só o admin;
#   • /contest/esqueletos (o time) e o `code_templates` do /contest/userinfo seguem o EFETIVO;
#   • spec unificado: create grava o arquivo, export/duplicar o levam — inclusive acima de 128 KiB (ARG_MAX);
#   • Central (preflight): fail sem editor, warn com Java `public class`, warn em ICPC, ok nos demais.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
NOW="$(date +%s)"; FUT=$(( NOW + 100000 ))
mkdir -p "$FIX/treino/var/jsons" "$FIX/treino/users"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\n' > "$FIX/treino/conf"
fx_user "$FIX/treino" prof s "Prof"
printf '{"threshold":0,"allow":["prof"],"deny":[]}' > "$FIX/treino/var/contest-perms.json"
printf 'CONTEST=treino\nLOGIN=prof\nUSERFULLNAME=Prof\nLOGINAT=1\n' > "$SESS/prof"
mkc(){ # <id> <tipo> [extra conf]
  local C="$FIX/$1"; mkdir -p "$C/var" "$C/enunciados"
  { printf 'CONTEST_ID=%s\nCONTEST_TYPE=%s\nCONTEST_NAME=%s\nCONTEST_START=%s\nCONTEST_END=%s\n' "$1" "$2" "$1" "$((NOW-3600))" "$FUT"
    printf "PROBS=( cdmoj p/a 'Prob A' A 'p#a' )\n"; printf '%s' "${3:-}"; } > "$C/conf"
  fx_user "$C" "$1.admin" p Admin; fx_user "$C" time1 a "Time 1"
  printf 'CONTEST=%s\nLOGIN=%s.admin\nLOGINAT=1\n' "$1" "$1" > "$SESS/adm-$1"
  printf 'CONTEST=%s\nLOGIN=time1\nLOGINAT=1\n' "$1" > "$SESS/usr-$1"
}
mkc ev treino; mkc mar icpc
E="$FIX/ev"
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-adm-ev}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" bash "$ROUTER" <<<"${3:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
J(){ jq -r "$1" <<<"$BODY" 2>/dev/null; }
confmods(){ ( CONTEST_MODULES=""; source "$1/conf" 2>/dev/null; printf '%s' "$CONTEST_MODULES" ); }
pre(){ call /contest/admin/preflight GET '' "adm-$1" "contest=$1"; PRE="$(J '[.checks[]|select(.id=="esqueletos")|.level]|join(",")')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:240}"; ((fail++)); fi; }

echo "== catálogo =="
call /contest/admin/modules GET '' adm-ev 'contest=ev'
ck "esqueletos no catálogo, desligado"        '[[ "$(J ".modules[]|select(.id==\"esqueletos\")|.on")" == false ]]'

echo "== pré-requisito: o editor embutido =="
printf 'SHOWEDITOR=0\n' >> "$E/conf"
call /contest/admin/modules POST '{"on":["esqueletos"]}' adm-ev 'contest=ev'
ck "ligar sem editor: 422 editor_required"    '[[ "$OUT" == *"Status: 422"* && "$(J .error.code)" == editor_required && -z "$(confmods "$E")" ]]'
call /contest/admin/esqueletos POST '{"action":"set","lang":"c","code":"int main(){}"}' adm-ev 'contest=ev'
ck "gravar esqueleto sem editor: 422 (gravar ligaria o módulo)" '[[ "$(J .error.code)" == editor_required && ! -e "$E/esqueletos.json" ]]'
sed -i '/^SHOWEDITOR=/d' "$E/conf"
call /contest/admin/modules POST '{"on":["esqueletos"]}' adm-ev 'contest=ev'
ck "com o editor: liga"                       '[[ "$(confmods "$E")" == esqueletos ]]'
call /contest/admin/settings POST '{"name":"Outro nome","show_editor":false}' adm-ev 'contest=ev'
ck "desligar o editor com o módulo: 409 module_needs_editor" '[[ "$OUT" == *"Status: 409"* && "$(J .error.code)" == module_needs_editor ]]'
ck "…e NADA foi gravado (nem o nome)"         '! grep -q "^SHOWEDITOR=" "$E/conf" && grep -q "^CONTEST_NAME=ev$" "$E/conf"'
for v in '"false"' 0 null; do
  call /contest/admin/settings POST "{\"show_editor\":$v}" adm-ev 'contest=ev'
  ck "show_editor:$v (o bset desliga com tudo que não é true): 409 também" '[[ "$(J .error.code)" == module_needs_editor ]] && ! grep -q "^SHOWEDITOR=" "$E/conf"'
done
call /contest/admin/settings POST '{"show_editor":true}' adm-ev 'contest=ev'
ck "manter o editor ligado passa"             '[[ "$OUT" == *"Status: 200"* ]]'

echo "== /contest/admin/esqueletos =="
call /contest/admin/esqueletos GET '' adm-ev 'contest=ev'
ck "GET: efetivo, sem personalização"         '[[ "$(J "[.module_on,.editor_on,.effective,(.langs|length)]|@csv")" == "true,true,true,0" ]]'
call /contest/admin/esqueletos GET '' usr-ev 'contest=ev'
ck "o time não administra (403)"              '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/admin/esqueletos POST "$(jq -cn '{action:"set",lang:"c",code:"#include <stdio.h>\nint main(void){\n  /* turma */\n}\n"}')" adm-ev 'contest=ev'
ck "set c: personalizado"                     '[[ "$(J ".langs.c.mode")" == custom && "$(J ".langs.c.code")" == *"/* turma */"* ]]'
call /contest/admin/esqueletos POST '{"action":"off","lang":"java"}' adm-ev 'contest=ev'
ck "off java"                                 '[[ "$(J ".langs.java.mode")" == off && "$(J ".langs.c.mode")" == custom ]]'
call /contest/admin/esqueletos POST '{"action":"set","lang":"py","code":"   \n"}' adm-ev 'contest=ev'
ck "código só de espaço = sem esqueleto (off)" '[[ "$(J ".langs.py.mode")" == off ]]'
call /contest/admin/esqueletos POST '{"action":"reset","lang":"py"}' adm-ev 'contest=ev'
ck "reset py: volta ao padrão (some)"         '[[ "$(J ".langs|has(\"py\")")" == false ]]'
call /contest/admin/esqueletos POST '{"action":"set","lang":"../x","code":"a"}' adm-ev 'contest=ev'
ck "linguagem inválida: 422 lang_invalid"     '[[ "$(J .error.code)" == lang_invalid ]]'
call /contest/admin/esqueletos POST '{"action":"set","lang":"pddl","code":"a"}' adm-ev 'contest=ev'
ck "exótica não declarada pelo contest: 422"  '[[ "$(J .error.code)" == lang_invalid ]]'
printf '{"p#a":["pddl"]}' > "$E/problem-langs.json"
call /contest/admin/esqueletos POST '{"action":"set","lang":"pddl","code":"(define)"}' adm-ev 'contest=ev'
ck "exótica declarada por problema: aceita"   '[[ "$(J ".langs.pddl.mode")" == custom ]]'
head -c 70000 /dev/zero | tr '\0' 'x' > "$RUN/big"
call /contest/admin/esqueletos POST "$(jq -cn --rawfile c "$RUN/big" '{action:"set",lang:"rs",code:$c}')" adm-ev 'contest=ev'
ck "acima de 64 KB: 422 code_too_big"         '[[ "$(J .error.code)" == code_too_big ]]'
call /contest/admin/esqueletos POST '{"action":"zap","lang":"c"}' adm-ev 'contest=ev'
ck "ação inválida: 422"                       '[[ "$(J .error.code)" == action_invalid ]]'
ck "auditado"                                 'grep -q "	esqueletos-set	lang=c" "$E/var/admin-audit.log" && grep -q "	esqueletos-off	lang=java" "$E/var/admin-audit.log"'

echo "== o time: /contest/esqueletos e userinfo =="
call /contest/userinfo GET '' usr-ev 'contest=ev'
ck "userinfo: code_templates true"            '[[ "$(J .code_templates)" == true ]]'
call /contest/esqueletos GET '' usr-ev 'contest=ev'
ck "o time recebe os personalizados"          '[[ "$(J ".on")" == true && "$(J ".langs.c.mode")" == custom && "$(J ".langs.java.mode")" == off ]]'
printf 'SHOWEDITOR=0\n' >> "$E/conf"   # conf editado À MÃO (as portas não deixam)
call /contest/esqueletos GET '' usr-ev 'contest=ev'
ck "editor desligado à mão: 404 module_off"   '[[ "$OUT" == *"Status: 404"* && "$(J .error.code)" == module_off ]]'
call /contest/userinfo GET '' usr-ev 'contest=ev'
ck "…e userinfo: code_templates false"        '[[ "$(J .code_templates)" == false ]]'
pre ev
ck "Central: fail (módulo sem efeito)"        '[[ "$PRE" == fail ]]'
sed -i '/^SHOWEDITOR=/d' "$E/conf"
pre ev
ck "Central: ok com o editor"                 '[[ "$PRE" == ok ]]'
call /contest/admin/modules POST '{"off":["esqueletos"]}' adm-ev 'contest=ev'
call /contest/esqueletos GET '' usr-ev 'contest=ev'
ck "módulo desligado: 404 e o arquivo fica"   '[[ "$OUT" == *"Status: 404"* && -s "$E/esqueletos.json" ]]'
call /contest/admin/modules GET '' adm-ev 'contest=ev'
ck "desligado com dados: detected"            '[[ "$(J ".modules[]|select(.id==\"esqueletos\")|.reason")" == esqueletos.json ]]'
call /contest/admin/esqueletos POST '{"action":"reset","lang":"pddl"}' adm-ev 'contest=ev'
ck "gravar LIGA o módulo de novo (mod_enable)" '[[ "$(confmods "$E")" == esqueletos ]]'

echo "== Central: Java public class e ICPC =="
call /contest/admin/esqueletos POST "$(jq -cn '{action:"set",lang:"java",code:"public class Solucao {\n public static void main(String[] a){}\n}\n"}')" adm-ev 'contest=ev'
pre ev
ck "Java com public class: warn"              '[[ "$PRE" == warn && "$(J ".checks[]|select(.id==\"esqueletos\")|.label")" == *"public class"* ]]'
call /contest/admin/modules POST '{"on":["esqueletos"]}' adm-mar 'contest=mar'
pre mar
ck "contest ICPC: warn"                       '[[ "$PRE" == warn && "$(J ".checks[]|select(.id==\"esqueletos\")|.label_en")" == *ICPC* ]]'

echo "== spec unificado: criar, exportar, duplicar =="
mkspec(){ # <id> <show_editor> <ARQUIVO com o objeto modules> — por arquivo: 180 KB no argv do jq estouraria
  jq -cn --arg id "$1" --argjson end "$FUT" --argjson se "$2" --slurpfile m "$3" \
  '{id:$id, name:$id, mode:"treino", end:$end, show_editor:$se, admin:{login:"boss",password:"x",fullname:"Boss"},
    problems:[{bank_id:"p#a",name:"P1",letter:"A"}], modules:$m[0]}'; }
printf '%s' '{"id":"p#a","title":"A","tags":[]}' > "$FIX/treino/var/jsons/p#a.json"
printf '{"esqueletos":true}' > "$RUN/m1.json"
call /treino/contest-create/create POST "$(mkspec esq1 false "$RUN/m1.json")" prof
ck "criar sem editor + esqueletos: 422 editor_required" '[[ "$(J .error.code)" == editor_required && ! -d "$FIX/esq1" ]]'
call /treino/contest-create/create POST "$(mkspec esq1 '"false"' "$RUN/m1.json")" prof
ck "show_editor:\"false\" (string) também: 422"  '[[ "$(J .error.code)" == editor_required && ! -d "$FIX/esq1" ]]'
for l in c cpp java; do head -c 60000 /dev/zero | tr '\0' "${l:0:1}" > "$RUN/t-$l"; done
jq -cn --rawfile c "$RUN/t-c" --rawfile p "$RUN/t-cpp" --rawfile j "$RUN/t-java" \
  '{esqueletos:{langs:{c:{mode:"custom",code:$c}, cpp:{mode:"custom",code:$p}, java:{mode:"custom",code:$j}, py:{mode:"off"}}}}' > "$RUN/mods.json"
call /treino/contest-create/create POST "$(mkspec esq2 true "$RUN/mods.json")" prof
ck "criar com 180 KB de esqueletos: ok, módulo ligado" '[[ "$(J .success)" == true && "$(confmods "$FIX/esq2")" == esqueletos ]]'
ck "…o arquivo nasce com as 4 linguagens"     '[[ "$(jq -r ".langs|keys|join(\",\")" "$FIX/esq2/esqueletos.json")" == "c,cpp,java,py" ]]'
printf '{"esqueletos":{"langs":{"c":{"mode":"x"}}}}' > "$RUN/m3.json"
call /treino/contest-create/create POST "$(mkspec esq3 true "$RUN/m3.json")" prof
ck "seção inválida: 422 modules_spec_invalid" '[[ "$(J .error.code)" == modules_spec_invalid ]]'
call /treino/contest-create/export GET '' prof 'id=esq2'
ck "export leva os esqueletos (acima de 128 KiB, sem ARG_MAX)" '[[ "$(J ".modules.esqueletos.langs.java.code|length")" == 60000 && "$(J ".modules.esqueletos.langs.py.mode")" == off ]]'
call /treino/contest-create/duplicate POST '{"from":"esq2","id":"esq4","name":"esq4"}' prof
ck "duplicar leva o módulo e o arquivo"       '[[ "$(confmods "$FIX/esq4")" == esqueletos && "$(jq -r ".langs.cpp.code|length" "$FIX/esq4/esqueletos.json")" == 60000 ]]'

echo; echo "RESULT: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
