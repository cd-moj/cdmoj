#!/bin/bash
# bancada.sh — a BANCADA LOCAL de custo/vazão do MOJ (ver BANCADA.md). Rig ESTEIRA:
# mede quantos veredictos/min o judged sustenta e a QUE CUSTO (CPU, execs), no fluxo
# real de produção: submit → spool → intake (queue) → q_claim via /judge/heartbeat →
# /judge/result → spool result → ingest_result → metrics → placar coalescido.
#
#   bancada.sh esteira [--scenario nome] [--scale N] [--seed N] [--teams N]
#                      [--plateaus CSV] [--plateau-dur S] [--keep]
#   bancada.sh backlog [--backlog N] [--scenario nome] [--keep]
#       (pré-forja N RESULTS no spool + history pendente e mede o DRENO puro —
#        custo por veredicto EM FUNÇÃO da profundidade; é o spike S2)
#
# Tudo em fixture mktemp (CONTESTSDIR/RUNDIR/SESSIONDIR próprios — nada do checkout ou
# do sistema é tocado); componentes em cgroups separados quando systemd-run existir
# (senão /proc/<pid>/stat com utime+stime+cutime+cstime — o judged espera os filhos,
# então os filhos CONTAM). Saída: run dir com plan.tsv(+sha), lat.tsv, cpu.tsv,
# execs.txt e report.txt (bancada-report.sh).
set -u
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"                      # server/
: "${BANCADA_WORK:=${XDG_CACHE_HOME:-$HOME/.cache}/moj-bancada}"

RIG="${1:-}"; shift || true
[[ "$RIG" == esteira || "$RIG" == backlog || "$RIG" == prova ]] \
  || { echo "uso: bancada.sh <esteira|backlog|prova> [opts]" >&2; exit 1; }
SCEN=baseline; SCALE=1; SEED=42; TEAMS=300; PLATEAUS="40,60,80,100,120"; PDUR=180
BACKLOG=500; KEEP=0; NP=14
while (( $# )); do case "$1" in
  --scenario) SCEN="$2"; shift 2;;
  --scale) SCALE="$2"; shift 2;;
  --seed) SEED="$2"; shift 2;;
  --teams) TEAMS="$2"; shift 2;;
  --plateaus) PLATEAUS="$2"; shift 2;;
  --plateau-dur) PDUR="$2"; shift 2;;
  --backlog) BACKLOG="$2"; shift 2;;
  --keep) KEEP=1; shift;;
  *) echo "opção desconhecida: $1" >&2; exit 1;;
esac; done

TS="$(printf '%(%Y%m%d-%H%M%S)T')"
RUND="$BANCADA_WORK/run-$RIG-$SCEN-s$SEED-$TS"
mkdir -p "$RUND"

# ========================================================================================
# RIG PROVA: fluxo INTEIRO acoplado no MESMO box, pela pilha web de DEV (nginx 8080 +
# fcgiwrap deste checkout): submit HTTP → spool → judged (fila) → q_claim via heartbeat
# HTTP → /judge/result HTTP → ingest → metrics → placar, com POLLERS retroalimentados
# (times com pendência polam history+summary a 5-10 s — a espiral do dia 29). Usa o
# contest DEMO `zz-bancada` no CONTESTSDIR REAL de dev e o RUNDIR real (spool
# compartilhado com o fcgiwrap) — por isso o guarda de escritor único abaixo.
if [[ "$RIG" == prova ]]; then
  DEVBASE="${BANCADA_BASE:-http://127.0.0.1:8080}"
  DEVHOST="zz-bancada.moj.charge.naquadah.com.br"
  trap '[[ -n "${JPID:-}" ]] && kill "$JPID" 2>/dev/null; [[ -n "${MPID:-}" ]] && kill "$MPID" 2>/dev/null; [[ -n "${PPID_POLLER:-}" ]] && kill "$PPID_POLLER" 2>/dev/null' EXIT
  RC="${CONTESTSDIR:-$HOME/moj/contests}"; RR="${RUNDIR:-$HOME/moj/run}"
  curl -s -o /dev/null -m 3 "$DEVBASE/api/v1/index/status" -H "Host: moj.charge.naquadah.com.br" \
    || { echo "pilha web de dev fora do ar (start-fcgiwrap.sh + nginx do ~/nginx-proxy)"; exit 1; }
  # ESCRITOR ÚNICO: recusa se já há um judged preso ao spool REAL
  for p in $(pgrep -f 'bash judged.sh' 2>/dev/null); do
    if tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -q "^SPOOLDIR=$RR/spool"; then
      echo "já existe judged no spool real (pid $p) — mate-o antes"; exit 1
    fi
  done
  # contest DEMO zz-bancada (idempotente)
  ZC="$RC/zz-bancada"; mkdir -p "$ZC/var" "$ZC/enunciados"
  if [[ ! -f "$ZC/conf" ]]; then
    { printf 'CONTEST_ID=zz-bancada\nCONTEST_NAME=Bancada\\ Prova\nCONTEST_TYPE=icpc\nDEMO=1\n'
      printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$(( EPOCHSECONDS - 3600 ))" "$(( EPOCHSECONDS + 864000 ))"
      printf 'PROBS=('
      for (( p = 0; p < NP; p++ )); do printf " x col#p%02d 'Prob %02d' P%02d col#p%02d" "$p" "$p" "$p" "$p"; done
      printf ' )\n'; } > "$ZC/conf"
  fi
  CANON=(); for (( p = 0; p < NP; p++ )); do CANON+=("$(printf 'col#p%02d' "$p")"); done
  echo "== fixture ($TEAMS times) + sessões (carga-*)…"
  CONTESTSDIR="$RC" RUNDIR="$RR" APIDIR="$ROOT/api/v1" CARGA_TMP="$RUND" \
    bash "$HERE/carga-fixture.sh" zz-bancada "$TEAMS" 20 >/dev/null
  CONTESTSDIR="$RC" RUNDIR="$RR" CARGA_TMP="$RUND" bash "$HERE/carga-sessoes.sh" zz-bancada >/dev/null
  # plano
  awk -v seed="$SEED" -v teams="$TEAMS" -v np="$NP" -v plateaus="$PLATEAUS" -v dur="$PDUR" \
      -v scale="$SCALE" -f "$HERE/bancada-plan.awk" > "$RUND/plan.tsv"
  PLAN_SHA="$(sha256sum "$RUND/plan.tsv" | cut -c1-16)"; NSUB="$(wc -l < "$RUND/plan.tsv")"
  { echo "rig=prova scenario=$SCEN scale=$SCALE seed=$SEED teams=$TEAMS plateaus=$PLATEAUS dur=$PDUR"
    echo "plan_sha=$PLAN_SHA nsub=$NSUB base=$DEVBASE"
    echo "git=$(git -C "$ROOT/.." rev-parse --short HEAD 2>/dev/null || echo '?')"
  } > "$RUND/env.txt"
  echo "== plano: $NSUB subs (sha $PLAN_SHA)"
  # registro do juiz mock no registry REAL + daemon no spool REAL
  jq -cn --argjson now "$EPOCHSECONDS" \
     --argjson probs "$(printf '%s\n' "${CANON[@]}" | jq -Rcs 'split("\n")|map(select(length>0))')" \
    '{host:"mockj", last_seen:$now, state:"free", inv_hash:"bancada", free_slots:8,
      total_slots:8, ncpu:8, problems:$probs, langs:[], capability:""}' > "$RR/registry/mockj.json"
  ( cd "$ROOT/daemons" && exec env CONTESTSDIR="$RC" RUNDIR="$RR" \
      SPOOLDIR="$RR/spool/submissions" SPOOLDONEDIR="$RR/spool/submissions-done" \
      JUDGE_BACKEND=queue INTAKE_MODE=queue SCORE_COALESCE_S=5 \
      bash judged.sh >/dev/null 2>>"$RUND/judged.err" ) &
  JPID=$!
  # rotas de juiz vão no host PRINCIPAL (o vhost do contest isola /judge/*)
  RUNDIR="$RR" MOCKJ_BASE="$DEVBASE" MOCKJ_HOST="moj.charge.naquadah.com.br" \
    "$HERE/bancada-mock-judge.sh" "$ROOT/api/v1/router.sh" "$RUND" >/dev/null 2>>"$RUND/mockj.err" &
  MPID=$!
  # pollers: mix base + espiral por pendência
  : > "$RUND/pend.txt"
  BANCADA_CONTEST=zz-bancada POLLER_HOST="$DEVHOST" "$HERE/bancada-poller.sh" "$DEVBASE" "$RUND/carga-tokens-teams.txt" \
      $(( $(wc -l < "$RUND/plan.tsv") )) "$RUND/web.log" "$RUND/pend.txt" >/dev/null 2>&1 &
  PPID_POLLER=$!
  # medidores
  cpu_of(){ awk '{print $14+$15+$16+$17}' "/proc/$1/stat" 2>/dev/null || echo 0; }
  # ⚠ o fcgiwrap NÃO acumula cutime dos bashs por requisição (medido 30/08: cutime=0 no
  # pool após 8k reqs) — atribuição fina do tier web exigiria cgroup próprio. O que vale:
  # CPU do BOX inteiro (user+sys de /proc/stat) como teto, e o judged por utime+cutime.
  cpu_box(){ awk '/^cpu /{print $2+$3+$4+$7+$8}' /proc/stat; }
  PROC0="$(awk '/^processes/{print $2}' /proc/stat)"
  CPUJ0="$(cpu_of "$JPID")"; CPUB0="$(cpu_box)"
  T0="$EPOCHSECONDS"
  # feeder HTTP no relógio do plano (+ pendfile p/ a espiral)
  mapfile -t TT < "$RUND/carga-tokens-teams.txt"
  SUBOK=0; SUBFAIL=0
  while IFS=$'\t' read -r toff team prob v; do
    now=$(( EPOCHSECONDS - T0 )); (( toff > now )) && sleep $(( toff - now ))
    u="$(printf 'eq-%04d' "$team")"
    tok="${TT[$(( team - 1 ))]:-}"
    [[ -n "$tok" ]] || { SUBFAIL=$(( SUBFAIL + 1 )); continue; }
    b64="$(printf '//moj-mock: %s\nint main(){return 0;}\n' "$v" | base64 -w0)"
    code="$(curl -sk -o /dev/null -m 20 -w '%{http_code}' -X POST \
        -H "Host: $DEVHOST" -H 'Content-Type: application/json' -H "Authorization: Bearer $tok" \
        -d "{\"problem_id\":\"${CANON[$prob]}\",\"filename\":\"a.c\",\"code_b64\":\"$b64\"}" \
        "$DEVBASE/api/v1/submit?contest=zz-bancada" 2>/dev/null)"
    if [[ "$code" == 200 ]]; then
      SUBOK=$(( SUBOK + 1 )); printf '%s\t%s\n' "$u" "$EPOCHSECONDS" >> "$RUND/subs.tsv"
      # pendência (o poller pola com este TOKEN): entra ao submeter; só cresce durante o
      # run — é a pendência de PICO, o pior caso honesto da espiral
      grep -qxF "$tok" "$RUND/pend.txt" 2>/dev/null || echo "$tok" >> "$RUND/pend.txt"
    else SUBFAIL=$(( SUBFAIL + 1 )); fi
  done < "$RUND/plan.tsv"
  echo "== subs: $SUBOK ok, $SUBFAIL falhas; aguardando dreno (teto 5 min)…"
  for _ in $(seq 300); do
    nres="$(find "$RR/spool/submissions-done" -maxdepth 1 -name "zz-bancada:*:result:*" -newer "$RUND/env.txt" 2>/dev/null | wc -l)"
    (( nres >= SUBOK )) && break
    sleep 1
  done
  T1="$EPOCHSECONDS"
  CPUJ1="$(cpu_of "$JPID")"; CPUB1="$(cpu_box)"
  PROC1="$(awk '/^processes/{print $2}' /proc/stat)"
  kill "$JPID" "$MPID" "$PPID_POLLER" 2>/dev/null; wait 2>/dev/null; JPID=""; MPID=""
  TICK="$(getconf CLK_TCK)"
  { echo "subs=$SUBOK fails=$SUBFAIL wall_s=$(( T1 - T0 )) veredictos_aterrissados=$nres"
    echo "cpu_judged_s=$(( (CPUJ1 - CPUJ0) / TICK )) cpu_box_s=$(( (CPUB1 - CPUB0) / TICK ))"
    echo "forks_do_box=$(( PROC1 - PROC0 ))"
    awk '{ n[$2]++; t[$2]+=$4; c[$2 "_" $3]++ } END {
      for (r in n) printf "web %s: n=%d t_avg=%.3fs err=%d\n", r, n[r], t[r]/n[r], n[r]-c[r "_200"] }' \
      "$RUND/web.log" 2>/dev/null | sort
  } | tee "$RUND/report.txt"
  echo "run: $RUND"
  trap - EXIT
  exit 0
fi
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"
JPID=""; MPID=""
cleanup(){
  [[ -n "$JPID" ]] && kill "$JPID" 2>/dev/null
  [[ -n "$MPID" ]] && kill "$MPID" 2>/dev/null
  wait 2>/dev/null
  (( KEEP )) || rm -rf "$FIX" "$SESS" "$RUN"
}
trap cleanup EXIT

export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" \
       SPOOLDIR="$RUN/spool/submissions" SPOOLDONEDIR="$RUN/spool/submissions-done"
mkdir -p "$SPOOLDIR" "$SPOOLDONEDIR" "$RUN/secrets" "$RUN/registry" "$RUN/results"
ROUTER="$ROOT/api/v1/router.sh"

# --- fixture: contest bz com NP problemas + TEAMS times + sessões ------------------------
NOW="$EPOCHSECONDS"
C="$FIX/bz"; mkdir -p "$C/var" "$C/enunciados"
{ printf 'CONTEST_ID=bz\nCONTEST_NAME=Bancada\nCONTEST_TYPE=icpc\nDEMO=1\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$(( NOW - 3600 ))" "$(( NOW + 86400 ))"
  printf 'PROBS=('
  for (( p = 0; p < NP; p++ )); do
    printf " x col#p%02d 'Prob %02d' P%02d col#p%02d" "$p" "$p" "$p" "$p"
  done
  printf ' )\n'; } > "$C/conf"
CANON=(); for (( p = 0; p < NP; p++ )); do CANON+=("$(printf 'col#p%02d' "$p")"); done
echo "== fixture: $TEAMS times…"
for (( t = 1; t <= TEAMS; t++ )); do
  u="$(printf 'eq-%04d' "$t")"; d="$C/users/$u"
  mkdir -p "$d/submissions" "$d/results" "$d/mojlog"
  printf '{"login":"%s","password":"x","fullname":"Equipe %s","status":"active"}\n' "$u" "$u" > "$d/account.json"
  : > "$d/history"
  printf 'CONTEST=bz\nLOGIN=%s\nLOGINAT=1\n' "$u" > "$SESS/tk$u"
done
printf 'mojw_bancada000000000000\n' > "$RUN/secrets/worker.token"; chmod 600 "$RUN/secrets/worker.token"
# registro do juiz mock pré-semeado (evita o handshake de register): tem TODOS os problemas
jq -cn --argjson now "$NOW" --argjson probs "$(printf '%s\n' "${CANON[@]}" | jq -Rcs 'split("\n")|map(select(length>0))')" \
  '{host:"mockj", last_seen:$now, state:"free", inv_hash:"bancada", free_slots:8, total_slots:8,
    ncpu:8, problems:$probs, langs:[], capability:""}' > "$RUN/registry/mockj.json"

# --- plano ------------------------------------------------------------------------------
awk -v seed="$SEED" -v teams="$TEAMS" -v np="$NP" -v plateaus="$PLATEAUS" -v dur="$PDUR" \
    -v scale="$SCALE" -f "$HERE/bancada-plan.awk" > "$RUND/plan.tsv"
PLAN_SHA="$(sha256sum "$RUND/plan.tsv" | cut -c1-16)"
NSUB="$(wc -l < "$RUND/plan.tsv")"
{ echo "rig=$RIG scenario=$SCEN scale=$SCALE seed=$SEED teams=$TEAMS np=$NP plateaus=$PLATEAUS dur=$PDUR"
  echo "plan_sha=$PLAN_SHA nsub=$NSUB backlog=$BACKLOG"
  echo "git=$(git -C "$ROOT/.." rev-parse --short HEAD 2>/dev/null || echo '?')"
} > "$RUND/env.txt"
echo "== plano: $NSUB submissões (sha $PLAN_SHA)"

# --- medidores ---------------------------------------------------------------------------
cpu_of(){ # <pid> -> "utime+stime+cutime+cstime" em ticks (filhos CONTAM após wait)
  awk '{print $14+$15+$16+$17}' "/proc/$1/stat" 2>/dev/null || echo 0
}
PROC0="$(awk '/^processes/{print $2}' /proc/stat)"

# --- judged ------------------------------------------------------------------------------
start_judged(){
  # exec: o subshell VIRA o judged (JPID aponta o daemon; utime+cutime dos filhos contam)
  ( cd "$ROOT/daemons" && exec env SPOOLDIR="$SPOOLDIR" SPOOLDONEDIR="$SPOOLDONEDIR" CONTESTSDIR="$FIX" \
      RUNDIR="$RUN" JUDGE_BACKEND=queue INTAKE_MODE=queue SCORE_COALESCE_S=5 \
      bash judged.sh >/dev/null 2>>"$RUND/judged.err" ) &
  JPID=$!
}

forge_result(){ # <id> <team> <prob-canon> <verdict> <epoch> — result no spool + pendência no history
  local id="$1" u="$2" pc="$3" v="$4" ep="$5"
  printf '%s:%s:C:Not Answered Yet:%s:%s\n' "$ep" "$pc" "$ep" "$id" >> "$C/users/$u/history"
  jq -cn --arg id "$id" --arg u "$u" --arg p "$pc" --arg v "$v" \
    '{host:"mockj", id:$id, contest:"bz", problem_id:$p, login:$u, lang:"C", verdict:$v,
      verdict_canon:($v | sub(",.*$"; "")), score:0, score_max:100, correct:1, total_tests:2,
      duration_s:1, tl_used:1, report_html_b64:"PGgxPm1vY2s8L2gxPgo="}' \
    > "$SPOOLDIR/.in.$id" && mv -f "$SPOOLDIR/.in.$id" "$SPOOLDIR/bz:$ep:$id:mockj:result:$pc"
}

# ========================================================================================
if [[ "$RIG" == backlog ]]; then
  # S2: dreno puro — custo por veredicto × profundidade do spool
  echo "== forjando $BACKLOG results no spool…"
  n=0
  while IFS=$'\t' read -r _t team prob v; do
    (( n < BACKLOG )) || break
    n=$(( n + 1 ))
    id="$(printf 'bk%030d' "$n")"
    forge_result "$id" "$(printf 'eq-%04d' "$team")" "${CANON[$prob]}" "$v" "$NOW"
  done < "$RUND/plan.tsv"
  echo "== drenando ($n results)…"
  T0="$EPOCHSECONDS"
  ( cd "$ROOT/daemons" && SPOOLDIR="$SPOOLDIR" SPOOLDONEDIR="$SPOOLDONEDIR" CONTESTSDIR="$FIX" \
      RUNDIR="$RUN" JUDGE_BACKEND=queue INTAKE_MODE=queue SCORE_COALESCE_S=999999 \
      bash judged.sh --drain >/dev/null 2>>"$RUND/judged.err" ) &
  JPID=$!
  # strace de execs numa janela (se disponível)
  if command -v strace >/dev/null 2>&1; then
    ( strace -f -qq -c -e trace=execve -p "$JPID" -o "$RUND/execs.txt" & STP=$!
      sleep 30; kill -INT "$STP" 2>/dev/null ) 2>/dev/null &
  fi
  CPU0="$(cpu_of "$JPID")"
  wait "$JPID" 2>/dev/null; RC=$?
  T1="$EPOCHSECONDS"; JPID=""
  DONE_N="$(find "$SPOOLDONEDIR" -maxdepth 1 -type f 2>/dev/null | wc -l)"
  WALL=$(( T1 - T0 )); (( WALL > 0 )) || WALL=1
  PROC1="$(awk '/^processes/{print $2}' /proc/stat)"
  { echo "backlog=$n drenados=$DONE_N wall_s=$WALL rc=$RC"
    echo "veredictos_por_min=$(( DONE_N * 60 / WALL ))"
    echo "ms_por_veredicto=$(( WALL * 1000 / (DONE_N > 0 ? DONE_N : 1) ))"
    echo "forks_do_box_no_intervalo=$(( PROC1 - PROC0 ))"
    echo "forks_por_veredicto=$(( (PROC1 - PROC0) / (DONE_N > 0 ? DONE_N : 1) )) (bruto: inclui a própria bancada)"
  } | tee "$RUND/report.txt"
  echo "run: $RUND"
  exit 0
fi

# ========================================================================================
# RIG ESTEIRA: fluxo completo com juiz mock em PULL
start_judged
"$HERE/bancada-mock-judge.sh" "$ROUTER" "$RUND" >/dev/null 2>>"$RUND/mockj.err" &
MPID=$!

echo "== replay do plano ($NSUB subs; platôs: $PLATEAUS ×${PDUR}s)…"
T0="$EPOCHSECONDS"
CPUJ0="$(cpu_of "$JPID")"
SUBOK=0; SUBFAIL=0
while IFS=$'\t' read -r toff team prob v; do
  now=$(( EPOCHSECONDS - T0 ))
  (( toff > now )) && sleep $(( toff - now ))
  u="$(printf 'eq-%04d' "$team")"
  b64="$(printf '//moj-mock: %s\nint main(){return 0;}\n' "$v" | base64 -w0)"
  ep="$EPOCHSECONDS"
  out="$(PATH_INFO=/submit REQUEST_METHOD=POST QUERY_STRING="contest=bz" \
      HTTP_AUTHORIZATION="Bearer tk$u" bash "$ROUTER" \
      <<<"{\"problem_id\":\"${CANON[$prob]}\",\"filename\":\"a.c\",\"code_b64\":\"$b64\"}" 2>/dev/null)"
  if grep -q '"success":true' <<<"$out"; then
    id="$(grep -o '"submission_id":"[a-f0-9]*"' <<<"$out" | head -1 | cut -d'"' -f4)"
    printf '%s\t%s\t%s\n' "$id" "$ep" "$u" >> "$RUND/submitted.tsv"
    SUBOK=$(( SUBOK + 1 ))
  else
    SUBFAIL=$(( SUBFAIL + 1 ))
  fi
done < "$RUND/plan.tsv"
echo "== submissões: $SUBOK ok, $SUBFAIL falhas; aguardando dreno…"
# espera TODO veredicto aterrissar (result no done) — spool vazio não basta: o job pode
# estar na fila run/queue esperando o claim do mock. Teto de 5 min.
for _ in $(seq 300); do
  ndone="$(find "$SPOOLDONEDIR" -maxdepth 1 -name '*:result:*' 2>/dev/null | wc -l)"
  (( ndone >= SUBOK )) && break
  sleep 1
done
T1="$EPOCHSECONDS"
CPUJ1="$(cpu_of "$JPID")"
PROC1="$(awk '/^processes/{print $2}' /proc/stat)"
kill "$JPID" "$MPID" 2>/dev/null; wait 2>/dev/null; JPID=""; MPID=""

# latência por veredicto: submit_ep (submitted.tsv) × mtime do result em submissions-done
: > "$RUND/lat.tsv"
while IFS=$'\t' read -r id ep u; do
  f="$(find "$SPOOLDONEDIR" -maxdepth 1 -name "bz:*:$id:*:result:*" 2>/dev/null | head -1)"
  [[ -n "$f" ]] || continue
  mt="$(stat -c %Y "$f")"
  printf '%s\t%s\t%s\n' "$id" "$ep" "$(( mt - ep ))" >> "$RUND/lat.tsv"
done < "$RUND/submitted.tsv"

TICK="$(getconf CLK_TCK)"
{ echo "subs=$SUBOK fails=$SUBFAIL wall_s=$(( T1 - T0 ))"
  echo "cpu_judged_s=$(( (CPUJ1 - CPUJ0) / TICK ))"
  echo "forks_do_box=$(( PROC1 - PROC0 ))"
  cut -f3 "$RUND/lat.tsv" | sort -n | awk '{ l[NR]=$1 } END { if (NR) {
      p50=l[int((NR+1)*0.5)]; p95=l[int((NR+1)*0.95)]; if (p95=="") p95=l[NR]
      printf "veredictos=%d lat_p50_s=%d lat_p95_s=%d lat_max_s=%d\n", NR, p50, p95, l[NR] } }' 
} | tee "$RUND/report.txt"
echo "run: $RUND"
