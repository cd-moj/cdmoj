#!/bin/bash
# BALÃO "PRIMEIRO DA SEDE" — a tarefa do `.staff` avisa se aquele é o primeiro balão daquela cor
# NA SEDE (★ + first to solve), e a decisão só sai com CERTEZA.
#
# A regra: só é o primeiro se nenhum time da MESMA sede resolveu o problema antes E nenhuma run
# mais antiga da sede, no mesmo problema, ainda está por julgar. Enquanto houver dúvida a tarefa
# ESPERA (print-requests/.balloon-hold) e é reavaliada no reconcile seguinte; passado
# BALLOON_FIRST_WAIT_S ela sai SEM estrela — a falha segura, porque o time recebe o balão e
# ninguém anuncia um primeiro lugar falso.
#
# POR QUE A ESPERA: o placar pode ser otimista (é repintado a cada build e a estrela se corrige
# sozinha); o balão NÃO — é físico, o staff atravessa a sala e anuncia. E no modo automático a
# folha é impressa segundos depois de a tarefa nascer, com o PDF cacheado para sempre: promover
# a estrela depois mudaria a tela e nunca o papel.
set -u
# o PISO do reconcile (1x/10s sob churn de veredicto) é comportamento de produção; aqui os
# cenários encadeiam reconciles em segundos e o que se testa é a SEMÂNTICA — piso desligado.
export BALLOON_RECONCILE_FLOOR_S=0
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX"
C="$FIX/bs"; mkdir -p "$C/var" "$C/print-requests"
NOW="$(date +%s)"; T0=$((NOW-3600))
conf(){ { printf 'CONTEST_ID=bs\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nUSER_STORE=v2\n' "$T0" "$((NOW+3600))"
          printf 'PROBS=( cdmoj apc#p1 Um A apc#p1 )\n'
          [[ -n "${1:-}" ]] && printf '%s\n' "$1"; } > "$C/conf"; }
conf ""
fx_user "$C" bs.admin p "Admin"
fx_user "$C" sede.staff p "Staff"
for u in a1 a2 b1; do fx_user "$C" "$u" x "Time ${u}"; done
# a1 e a2 na sede A; b1 na sede B. É o `.team.region` que define a sede (o mesmo campo que o
# staff-filters usa em `region:<nome>`).
# ⚠ `local u="$1" f=".../$u/..."` NÃO funciona: o bash expande TODOS os valores antes de o
# `local` atribuir qualquer um, então o `$u` do terceiro é o do escopo de FORA (aqui, o `u` que
# sobrou do for acima = b1). As três chamadas escreviam no mesmo arquivo e só a última valia —
# o teste "passava" no 1º cenário por acidente. Declare em linhas separadas.
setreg(){ local u="$1" r="$2" f
          f="$C/users/$u/account.json"
          jq -c --arg r "$r" '.team = ((.team // {}) + {region:$r})' "$f" > "$f.t" && mv "$f.t" "$f"; }
setreg a1 "Sede A"; setreg a2 "Sede A"; setreg b1 "Sede B"
printf 'CONTEST=bs\nLOGIN=bs.admin\nUSERFULLNAME=Admin\nLOGINAT=1\n' > "$SESS/adm"

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD=GET QUERY_STRING="${2:-}" HTTP_AUTHORIZATION="Bearer adm" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" </dev/null 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
queue(){ call /contest/staff/queue 'contest=bs'; }
# first_site da tarefa de balão do login
# ⚠ distinga "tarefa não existe" de "existe sem estrela": no 1º teste deste arquivo o `// ` do
# jq colapsou os dois (campo ausente é null, e `null // x` devolve x) e 11 asserções mentiram.
fs(){ jq -r --arg l "$1" '[.requests[]|select(.kind=="balloon" and .login==$l)] as $t
        | if ($t|length)==0 then "SEM-TAREFA" else ($t[0].first_site|tostring) end' <<<"$BODY"; }
nb(){ jq -r '[.requests[]|select(.kind=="balloon")]|length' <<<"$BODY"; }
# reconcile: o gate é o mtime do .score-dirty contra o carimbo
touchdirty(){ sleep 1; touch "$C/var/.score-dirty"; }
# ⚠ o metrics_recompute precisa do PENALTY_CODES_DEFAULT/VERDICT_CANON_JQ, que moram no
# lib/verdict.sh — sourcear só o users.sh num subshell com `set -u` mata a função em silêncio e
# o teste passa a medir METRICS VELHO (foi o que aconteceu na 1ª versão deste arquivo).
source "$ROOT/api/v1/lib/verdict.sh"; source "$ROOT/api/v1/lib/users.sh"
hist(){ printf '%s\n' "$2" > "$C/users/$1/history"; metrics_recompute bs "$1"; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:220}"; ((fail++)); fi; }

echo "== o primeiro da sede ganha a estrela; o segundo da MESMA sede não =="
hist a1 "$((T0+600)):apc#p1:C:Accepted,100p:$((T0+600)):s1"
hist a2 "$((T0+900)):apc#p1:C:Accepted,100p:$((T0+900)):s2"
touchdirty; queue
ck "duas tarefas de balão"        '[[ "$(nb)" == 2 ]]'
ck "a1 (mais antigo) tem ★"       '[[ "$(fs a1)" == true ]]'
ck "a2 (mesma sede) não tem"      '[[ "$(fs a2)" == false ]]'

echo "== é por SEDE, não global: a sede B tem o seu próprio primeiro =="
hist b1 "$((T0+1200)):apc#p1:C:Accepted,100p:$((T0+1200)):s3"
touchdirty; queue
ck "b1 ganha ★ mesmo resolvendo depois" '[[ "$(fs b1)" == true ]]'

echo "== run mais antiga da sede AINDA NA FILA: a tarefa espera =="
rm -f "$C"/print-requests/bln*.json "$C/print-requests/.balloon-stamp" "$C/print-requests/.balloon-hold"
hist a1 "$((T0+600)):apc#p1:C:Not Answered Yet:$((T0+600)):s1"
hist a2 "$((T0+900)):apc#p1:C:Accepted,100p:$((T0+900)):s2"
touchdirty; queue
ck "a2 NÃO vira tarefa ainda"     '[[ "$(fs a2)" == "SEM-TAREFA" ]]'
ck "ficou registrado na espera"   '[[ -s "$C/print-requests/.balloon-hold" ]]'
ck "a espera guarda o epoch"      '[[ "$(jq -r .sub_epoch "$C/print-requests/.balloon-hold")" == "'"$((T0+900))"'" ]]'

echo "== a run antiga julgada como WA: a tarefa sai COM a estrela =="
hist a1 "$((T0+600)):apc#p1:C:Wrong Answer:$((T0+600)):s1"
touchdirty; queue
ck "a2 vira tarefa"               '[[ "$(fs a2)" == true ]]'
ck "a espera foi esvaziada"       '[[ ! -s "$C/print-requests/.balloon-hold" ]]'

echo "== a run antiga julgada como AC: quem espera sai SEM a estrela =="
rm -f "$C"/print-requests/bln*.json "$C/print-requests/.balloon-stamp" "$C/print-requests/.balloon-hold"
hist a1 "$((T0+600)):apc#p1:C:Not Answered Yet:$((T0+600)):s1"
hist a2 "$((T0+900)):apc#p1:C:Accepted,100p:$((T0+900)):s2"
touchdirty; queue                                   # a2 segurado
hist a1 "$((T0+600)):apc#p1:C:Accepted,100p:$((T0+600)):s1"
touchdirty; queue
ck "a1 (o mais antigo) tem ★"     '[[ "$(fs a1)" == true ]]'
ck "a2 sai sem ★"                 '[[ "$(fs a2)" == false ]]'

echo "== prazo vencido: o balão não espera para sempre =="
rm -f "$C"/print-requests/bln*.json "$C/print-requests/.balloon-stamp" "$C/print-requests/.balloon-hold"
conf 'BALLOON_FIRST_WAIT_S=0'                        # 0 = não espera nada
hist a1 "$((T0+600)):apc#p1:C:Not Answered Yet:$((T0+600)):s1"
hist a2 "$((T0+900)):apc#p1:C:Accepted,100p:$((T0+900)):s2"
touchdirty; queue
ck "sai na hora, SEM estrela"     '[[ "$(fs a2)" == false ]]'
ck "nada ficou na espera"         '[[ ! -s "$C/print-requests/.balloon-hold" ]]'

echo "== time sem sede declarada: entra sem estrela e sem segurar ninguém =="
rm -f "$C"/print-requests/bln*.json "$C/print-requests/.balloon-stamp" "$C/print-requests/.balloon-hold"
conf ""
f="$C/users/b1/account.json"; jq -c 'del(.team.region)' "$f" > "$f.t" && mv "$f.t" "$f"
hist b1 "$((T0+1200)):apc#p1:C:Accepted,100p:$((T0+1200)):s3"
hist a1 "$((T0+600)):apc#p1:C:Accepted,100p:$((T0+600)):s1"
hist a2 "$((T0+1500)):apc#p1:C:Accepted,100p:$((T0+1500)):s2"
touchdirty; queue
ck "b1 (sem sede) sem estrela"    '[[ "$(fs b1)" == false ]]'
ck "a1 segue com a dele"          '[[ "$(fs a1)" == true ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
