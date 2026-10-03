#!/bin/bash
# smoke-warm-auto.sh — AQUECIMENTO AUTOMÁTICO de juízes (TCP 2026, 03/10/2026: a oficial começou com juízes frios e o
# organizador não achou o botão). O judged (shard 0) dispara o bin/warm-judges.sh ~WARM_LEAD_S antes do CONTEST_START,
# UMA vez por início (carimbo var/.warm-prestart); o núcleo é o jw_warm do botão. Prende:
#   · contest de PROVA (prova/super) que começa dentro da janela: calibrate dirigido a cada par juiz×problema frio +
#     carimbo + audit (auto-inicio); LISTA de aula não (fica com o botão — decisão do Ribas, 03/10/2026);
#   · 2ª varredura: nada de novo (carimbo); contest longe do início, DEMO ou já começado: nada;
#   · início NOVO (rodada nova): aquece de novo (carimbo atualizado);
#   · AUTO_WARM_JUDGES=0 desliga; a varredura é UM grep (não um processo por contest).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
FIX="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" RUNDIR="$RUN" MOJ_PROBLEMS_DIR="$RUN/nao-existe" TL_STORE_DIR="$RUN/tl"
mkdir -p "$FIX/treino/var" "$RUN/registry" "$RUN/tl" "$RUN/commands" "$RUN/updates/inprogress" "$RUN/spool/submissions"
NOW=$EPOCHSECONDS
mk(){ local c="$1" st="$2" extra="${3:-}"; mkdir -p "$FIX/$c/var" "$FIX/$c/users"
  { printf 'CONTEST_ID=%s\nCONTEST_TYPE=icpc\nLANGUAGES="c"\nCONTEST_START=%s\nCONTEST_END=%s\n%s' "$c" "$st" $((st+18000)) "$extra"
    printf "PROBS=( a col/pa 'Alfa' A 'col#pa' b col/pb 'Beta' B 'col#pb' )\n"; } > "$FIX/$c/conf"; }
mk logo  $((NOW+600)) $'CONTEST_PRIORITY=prova\n'   # PROVA que começa em 10 min: aquece
mk lista $((NOW+600))                  # LISTA (sem prioridade = lista-publica) em 10 min: NÃO (fica com o botão)
mk longe $((NOW+7200))                 # em 2 h: ainda não
mk ja    $((NOW-60))                   # já começou: não (o botão/promoção cobrem)
mk demo  $((NOW+300)) $'DEMO=1\nCONTEST_PRIORITY=prova\n'   # DEMO: nunca
jq -cn --argjson t "$NOW" '{host:"h1", state:"free", last_seen:$t, langs:["c"], problems:{}}' > "$RUN/registry/h1.json"
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; ((fail++)); fi; }
sweep(){ ( cd "$ROOT/daemons" && AUTO_WARM_JUDGES="${1:-1}" SPOOLDIR="$RUN/spool/submissions" SPOOLDONEDIR="$RUN/spool/done" \
    JUDGE_BACKEND=queue INTAKE_MODE=queue bash judged.sh --prestart-warm >>"$RUN/judged.err" 2>&1 ); }
ncmd(){ find "$RUN/commands/h1" -name '*.json' 2>/dev/null | wc -l; }

echo "== desligado (AUTO_WARM_JUDGES=0): nada =="
sweep 0
ck "nenhum comando, nenhum carimbo"      '[[ "$(ncmd)" == 0 && ! -e "$FIX/logo/var/.warm-prestart" ]]'

echo "== contest que começa em 10 min: aquece =="
sweep 1
ck "2 calibrações dirigidas p/ h1"       '[[ "$(ncmd)" == 2 ]] && jq -e ".action == \"calibrate\"" "$RUN"/commands/h1/*.json >/dev/null'
ck "os dois problemas do contest"        '[[ "$(jq -r .id "$RUN"/commands/h1/*.json | sort | tr "\n" ,)" == "col#pa,col#pb," ]]'
ck "carimbo = o início"                  '[[ "$(cat "$FIX/logo/var/.warm-prestart")" == $((NOW+600)) ]]'
ck "audit: warm-judges by=auto-inicio"   'grep -q "warm-judges.*by=auto-inicio" "$FIX/logo/var/admin-audit.log"'
ck "longe/já começou/DEMO: intocados"    '[[ ! -e "$FIX/longe/var/.warm-prestart" && ! -e "$FIX/ja/var/.warm-prestart" && ! -e "$FIX/demo/var/.warm-prestart" ]]'
ck "LISTA de aula (decisão do Ribas): não aquece sozinha" '[[ ! -e "$FIX/lista/var/.warm-prestart" ]] && ! grep -q "warm-judges" "$FIX/lista/var/admin-audit.log" 2>/dev/null'

echo "== 2ª varredura: nada de novo =="
sweep 1
ck "continua com 2 comandos"             '[[ "$(ncmd)" == 2 && "$(grep -c "warm-judges" "$FIX/logo/var/admin-audit.log")" == 1 ]]'

echo "== início NOVO (rodada nova): aquece de novo =="
sed -i "s/^CONTEST_START=.*/CONTEST_START=$((NOW+480))/" "$FIX/logo/conf"
sweep 1
ck "carimbo atualizado e nova rodada auditada" '[[ "$(cat "$FIX/logo/var/.warm-prestart")" == $((NOW+480)) && "$(grep -c "warm-judges" "$FIX/logo/var/admin-audit.log")" == 2 ]]'
ck "par já aquecendo não é pedido de novo" '[[ "$(ncmd)" == 2 ]]'

echo "== a varredura é UM grep sobre os confs (nunca um processo por contest) =="
for i in $(seq 1 200); do mk "x$i" $((NOW+90000)); done
SHIM="$(mktemp -d)"; printf '#!/bin/bash\necho x >> "%s/grep.log"\nexec /usr/bin/grep "$@"\n' "$SHIM" > "$SHIM/grep"; chmod +x "$SHIM/grep"
( cd "$ROOT/daemons" && PATH="$SHIM:$PATH" AUTO_WARM_JUDGES=1 SPOOLDIR="$RUN/spool/submissions" SPOOLDONEDIR="$RUN/spool/done" \
    JUDGE_BACKEND=queue INTAKE_MODE=queue bash judged.sh --prestart-warm >/dev/null 2>&1 )
ng="$(wc -l < "$SHIM/grep.log" 2>/dev/null)"; ng="${ng//[^0-9]/}"; ng="${ng:-0}"; rm -rf "$SHIM"
ck "204 contests: no máx. 3 grep (era 1 por contest)" '(( ng <= 3 ))'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
