#!/bin/bash
# Métricas: as DUAS portas do mesmo programa jq (lib/users.sh) — `metrics_recompute` (uma conta, a do
# daemon) e `metrics_recompute_all` (o contest inteiro num jq, o recompute em massa do build.sh) —
# têm de gravar o MESMO metrics.json (menos `computed_at`), conta a conta. E o carimbo do build.sh
# (`.metrics-stamp` com a assinatura de freeze + penalidade) só refaz o contest inteiro quando o que
# as métricas usam do conf muda (15/10/2026, ensaio de escrita de 800 times).
# Rode também com o jq 1.7 (o programa mora em variável, fora do jq-portability.sh).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX"
source "$ROOT/api/v1/lib/users.sh"
C="$FIX/mb"; mkdir -p "$C/var"
S0=1000; FZ=$(( S0 + 3000 ))
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; ((fail++)); fi; }

conf(){ { printf 'CONTEST_ID=mb\nCONTEST_TYPE=icpc\nCONTEST_NAME=MB\nCONTEST_START=%s\nCONTEST_END=%s\n' "$S0" 999999999
          printf "PROBS=( cdmoj p/a 'A' A 'p#a' cdmoj p/b 'B' B 'p#b' )\n"
          [[ -n "${1:-}" ]] && printf '%s\n' "$1"; } > "$C/conf"; }
H(){ printf '%s\n' "$2" >> "$C/users/$1/history"; }
for u in vazio pend ac ce ign time heur obi jerr ruim daemon; do fx_user "$C" "$u" x "$u" >/dev/null; : > "$C/users/$u/history"; done
# pend: provisórias (Not Answered Yet / Running) antes e depois do freeze
H pend "1:p#a:c:Not Answered Yet:$((S0+100)):p1"; H pend "2:p#b:c:Running:$((FZ+60)):p2"
# ac: WA, AC antes do freeze, AC de novo depois; no B só depois do freeze
H ac "1:p#a:cpp:Wrong Answer:$((S0+60)):a1"; H ac "2:p#a:cpp:Accepted:$((S0+600)):a2"
H ac "3:p#a:cpp:Accepted:$((S0+900)):a3";    H ac "4:p#b:py:Time Limit Exceeded:$((FZ+10)):a4"
H ac "5:p#b:py:Accepted:$((FZ+20)):a5"
# ce: CE conta ou não conforme PENALTY_VERDICTS
H ce "1:p#a:c:Compilation Error:$((S0+30)):c1"; H ce "2:p#a:c:Compilation Error:$((S0+40)):c2"
H ce "3:p#a:c:Accepted:$((S0+50)):c3"
# ign: Accepted (Ignored) não resolve nem conta
H ign "1:p#a:c:Accepted (Ignored):$((S0+10)):i1"; H ign "2:p#a:c:Wrong Answer (Ignored):$((S0+20)):i2"
# time: o texto do time depois do ¦ (configurável) não pontua — inclusive "Not Accepted"
H time "1:p#a:c:Wrong Answer¦Not Accepted, sorry:$((S0+10)):t1"; H time "2:p#a:c:Accepted¦Muito bem:$((S0+20)):t2"
# heur: veredicto heurístico com TAB e ':' no meio
H heur "1:p#a:c:Accepted,80p. Score 120	Score Ajustado 3.5 | obs: x:$((S0+10)):h1"
H heur "2:p#a:c:Wrong Answer,0p. Score -4	Score Ajustado 1:$((S0+20)):h2"
# obi: pontos parciais
H obi "1:p#a:c:Wrong Answer,30p:$((S0+10)):o1"; H obi "2:p#a:c:Accepted,100p:$((S0+20)):o2"
H obi "3:p#b:c:Time Limit Exceeded,30p. Pontos | 30 | 0 | quantitativos:$((S0+30)):o3"
# jerr: Judge Error e No_Servers nunca contam
H jerr "1:p#a:c:Judge Error:$((S0+10)):j1"; H jerr "2:p#a:c:No_Servers:$((S0+20)):j2"
H jerr "3:p#a:c:Runtime Error:$((S0+30)):j3"
# ruim: linha estragada (sem ':') — o programa FALHA nesta conta; as outras do lote têm de sair
H ruim "1:p#a:c:Accepted:$((S0+10)):r1"; H ruim "lixo"
H daemon "1:p#a:c:Accepted:$((S0+10)):d1"
# vazio: history PRESENTE e vazio (o BEGINFILE do gawk é que garante esta conta no lote)

norm(){ jq -cS 'del(.computed_at)' "$1" 2>/dev/null; }
compara(){ # <rótulo> — por-conta × lote, todas as contas (menos ruim/daemon, conferidas à parte)
  local u bad=0 R="$FIX/ref"; rm -rf "$R"; mkdir -p "$R"
  for u in vazio pend ac ce ign time heur obi jerr; do
    rm -f "$C/users/$u/metrics.json"; metrics_recompute mb "$u"; norm "$C/users/$u/metrics.json" > "$R/$u"
    [[ -s "$R/$u" ]] || { echo "    por-conta não gravou $u"; bad=1; }
    rm -f "$C/users/$u/metrics.json"
  done
  printf '{"sentinela":true}\n' > "$C/users/ruim/metrics.json"
  printf '{"sentinela":true}\n' > "$C/users/daemon/metrics.json"; touch -d '+30 seconds' "$C/users/daemon/metrics.json"
  MRC_CHUNK=4 metrics_recompute_all mb 2>"$FIX/err"
  for u in vazio pend ac ce ign time heur obi jerr; do
    cmp -s <(norm "$C/users/$u/metrics.json") "$R/$u" || { echo "    DIFERE $u:"; diff <(norm "$C/users/$u/metrics.json") "$R/$u" | head -4; bad=1; }
  done
  ck "$1: por-conta == lote em todas as contas (lotes de 4 contas)" '(( bad == 0 ))'
  ck "$1: linha estragada derruba SÓ a conta dela (metrics antigo fica, o resto do lote sai)" \
     '[[ "$(jq -c . "$C/users/ruim/metrics.json")" == "{\"sentinela\":true}" && -s "$C/users/jerr/metrics.json" ]]'
  ck "$1: conta regravada pelo daemon depois do início do lote é PULADA" \
     '[[ "$(jq -c . "$C/users/daemon/metrics.json")" == "{\"sentinela\":true}" ]]'
  ck "$1: a falha aparece no stderr" 'grep -q "1 conta(s) sem recompute" "$FIX/err"'
}

echo "== sem freeze, penalidade padrão"
conf ""
compara "padrão"
ck "vazio: history vazio = 0 submissões" '[[ "$(jq -r .submissions "$C/users/vazio/metrics.json")" == 0 ]]'
ck "ce: CE fora da penalidade (counted = só o AC)" '[[ "$(jq -r ".by_problem[\"p#a\"].counted" "$C/users/ce/metrics.json")" == 1 ]]'
echo "== freeze + CE contando"
conf "FREEZE_TIME=$FZ
PENALTY_VERDICTS=wa\ tle\ mle\ rte\ ce"
compara "freeze+ce"
ck "ce: CE conta (counted = 2 CE + o AC)" '[[ "$(jq -r ".by_problem[\"p#a\"].counted" "$C/users/ce/metrics.json")" == 3 ]]'
ck "ac: B resolvido depois do freeze fica escondido na visão congelada" \
   '[[ "$(jq -r ".by_problem[\"p#b\"].frozen.solved" "$C/users/ac/metrics.json")" == false ]]'

echo "== assinatura: penalidade explícita igual ao padrão = mesma assinatura"
conf ""; s1="$(metrics_conf_sig mb)"
conf "PENALTY_VERDICTS=wa\ tle\ mle\ rte"; s2="$(metrics_conf_sig mb)"
conf "FREEZE_TIME=$FZ"; s3="$(metrics_conf_sig mb)"
ck "padrão explícito == ausente" '[[ "$s1" == "$s2" ]]'
ck "freeze muda a assinatura"   '[[ "$s1" != "$s3" ]]'

echo "== build.sh: só refaz o contest inteiro quando a assinatura muda"
rm -f "$C/users/ruim/history" "$C/users/ruim/metrics.json" "$C/users/daemon/metrics.json"
build(){ bash "$ROOT/score/build.sh" mb >/dev/null 2>&1 || { echo "build.sh FALHOU"; exit 1; }; }
conf ""; rm -f "$C/var/.metrics-stamp"; build
ck "1º build grava a assinatura no carimbo" '[[ "$(cat "$C/var/.metrics-stamp")" == "$(metrics_conf_sig mb)" ]]'
# carimbo logo DEPOIS da lib (num checkout recém-editado a lib é de minutos atrás: um carimbo de "1 h atrás"
# dispararia o recompute pela lib, não pelo conf) e o conf regravado AGORA
touch -d '-1 hour' "$C"/users/*/metrics.json
touch -d "@$(( $(stat -c %Y "$ROOT/api/v1/lib/users.sh") + 1 ))" "$C/var/.metrics-stamp"
conf "LOGIN_START_TIME=$S0"; build      # mudança que as métricas NÃO usam
ck "conf editado sem mudar freeze/penalidade: nenhuma métrica refeita" \
   '[[ -z "$(find "$C/users" -name metrics.json -newer "$C/conf")" ]]'
ck "…e o carimbo anda (mais novo que o conf)" '[[ "$C/var/.metrics-stamp" -nt "$C/conf" ]]'
touch -d '-1 hour' "$C"/users/*/metrics.json "$C/var/.metrics-stamp"
conf "LOGIN_START_TIME=$S0
FREEZE_TIME=$FZ"; build
ck "freeze editado: o contest inteiro é refeito" \
   '[[ -z "$(find "$C/users" -name metrics.json ! -newer "$C/conf")" && "$(jq -r .freeze_time "$C/users/ac/metrics.json")" == "$FZ" ]]'
touch -d '2000-01-01' "$C/var/.metrics-stamp"; touch -d '2000-01-01' "$C/conf"; touch -d '-1 hour' "$C"/users/*/metrics.json
build
ck "lib mais nova que o carimbo (deploy) refaz mesmo com a mesma assinatura" \
   '[[ -z "$(find "$C/users" -name metrics.json -mmin +5)" ]]'
rm -f "$C/var/.metrics-stamp"; touch -d '-1 hour' "$C"/users/*/metrics.json; build
ck "carimbo apagado (settings/rodadas/kick) força" '[[ -z "$(find "$C/users" -name metrics.json -mmin +5)" ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
