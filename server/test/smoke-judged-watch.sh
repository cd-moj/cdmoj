#!/bin/bash
# smoke-judged-watch.sh — o laço de watch do judged com inotifywait -m PERSISTENTE (coproc):
#   1. evento que chega ENQUANTO o daemon drena/rearma não se perde: 15 results gravados no
#      padrão atômico (.in.* + mv) são ingeridos em segundos com WATCH_REDRAIN_SECS=60 (o
#      re-drain NÃO pode ser quem os pegou);
#   2. watcher morto (inotifywait cai) é re-subido e o daemon segue ingerindo;
#   3. judged.alive é batido.
# Usa um inotifywait FALSO no PATH (emula -m por varredura de 0,2 s): testa a plumbing do
# laço (coproc, read -t, rajada, respawn) sem depender do inotify-tools da máquina.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$(mktemp -d)"; RUN="$(mktemp -d)"; BIN="$(mktemp -d)"
DPID=""
cleanup(){ [[ -n "$DPID" ]] && { kill "$DPID" 2>/dev/null; wait "$DPID" 2>/dev/null; }; pkill -f "$BIN/inotifywait" 2>/dev/null; rm -rf "$FIX" "$RUN" "$BIN"; }
trap cleanup EXIT
export CONTESTSDIR="$FIX" RUNDIR="$RUN"
export SPOOLDIR="$RUN/spool/submissions" SPOOLDONEDIR="$RUN/spool/submissions-done"
mkdir -p "$SPOOLDIR" "$SPOOLDONEDIR" "$RUN/results" "$RUN/assigned"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
bad(){ FAIL=$((FAIL+1)); echo "FALHOU: $*" >&2; }
check(){ if eval "$1"; then ok; else bad "$2"; fi }

# inotifywait falso: -m por varredura (imprime nomes NOVOS do dir a cada 0,2 s)
cat > "$BIN/inotifywait" <<'FAKE'
#!/bin/bash
dir="${@: -1}"; seen="$(mktemp)"; trap 'rm -f "$seen"' EXIT
ls -A "$dir" 2>/dev/null | sort > "$seen"
while true; do
  sleep 0.2
  ls -A "$dir" 2>/dev/null | sort > "$seen.now"
  comm -13 "$seen" "$seen.now"
  mv -f "$seen.now" "$seen"
done
FAKE
chmod +x "$BIN/inotifywait"

C="$FIX/sz"; mkdir -p "$C/var" "$C/users/u1/mojlog" "$C/users/u1/results" "$C/users/u1/submissions"; : > "$C/users/u1/history"
NOW=$EPOCHSECONDS
printf 'CONTEST_ID=sz\nCONTEST_TYPE=icpc\nDEMO=1\nCONTEST_START=%s\nCONTEST_END=%s\nPROBS=( x pa A A pa )\n' "$((NOW-3600))" "$((NOW+86400))" > "$C/conf"
mkresult(){ # <id> : escrita ATÔMICA como o handler judge/result (.in.* + mv) — é o que perdia evento
  printf '%s:pa:C:Not Answered Yet:%s:%s\n' "$NOW" "$NOW" "$1" >> "$C/users/u1/history"
  jq -cn --arg id "$1" '{host:"mockj", id:$id, contest:"sz", problem_id:"pa", login:"u1", lang:"C",
      verdict:"Wrong Answer", verdict_canon:"Wrong Answer", report_html_b64:"PGgxPm1vY2s8L2gxPgo="}' > "$SPOOLDIR/.in.result.$1.$$"
  mv -f "$SPOOLDIR/.in.result.$1.$$" "$SPOOLDIR/sz:$NOW:$1:mockj:result:pa"
}
nwa(){ grep -c ':Wrong Answer' "$C/users/u1/history" 2>/dev/null || echo 0; }
waitfor(){ local want="$1" secs="$2" i; for ((i=0; i<secs*10; i++)); do [[ "$(nwa)" -ge "$want" ]] && return 0; sleep 0.1; done; return 1; }

LOG="$RUN/judged.log"
JUDGED_SHARDS=1 JUDGE_BACKEND=mock WATCH_REDRAIN_SECS=60 PATH="$BIN:$PATH" \
  bash "$ROOT/daemons/judged.sh" --watch 2>"$LOG" &
DPID=$!
for i in $(seq 1 50); do grep -q "inotifywait -m persistente" "$LOG" 2>/dev/null && break; sleep 0.1; done
check 'grep -q "inotifywait -m persistente" "$LOG"' "daemon não anunciou o watcher persistente"
check 'pgrep -f "$BIN/inotifywait" >/dev/null' "inotifywait (falso) não está rodando"

# 1. rajada com escrita atômica — sem o watcher persistente, parte cairia no re-drain (60 s)
for i in $(seq -w 1 15); do mkresult "id0$i"; sleep 0.3; done
check 'waitfor 15 10' "15 results não ingeridos em 10 s (só $(nwa)) — evento perdido, esperaria o re-drain"
check '[[ ! -s "$SPOOLDIR/sz:$NOW:id001:mockj:result:pa" ]]' "arquivo de result ficou no spool"
check '[[ -f "$RUN/judged.alive" ]]' "judged.alive não batido"

# 2. watcher morre — o daemon re-sobe e continua
pkill -f "$BIN/inotifywait"; sleep 2
check 'grep -q "inotifywait terminou" "$LOG"' "daemon não percebeu a morte do watcher"
check 'pgrep -f "$BIN/inotifywait" >/dev/null' "watcher não foi re-subido"
sleep 0.5; mkresult id0X
check 'waitfor 16 10' "result depois do respawn não ingerido (só $(nwa))"

kill "$DPID" 2>/dev/null; wait "$DPID" 2>/dev/null; DPID=""
echo "smoke-judged-watch: PASS=$PASS FAIL=$FAIL"; exit $(( FAIL>0 ))
