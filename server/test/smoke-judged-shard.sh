#!/bin/bash
# smoke-judged-shard.sh — a partição do escritor por hash(login) (lib/spool-shard.sh +
# JUDGED_SHARDS no judged.sh). O que ele fixa:
#   1. K=1 (default): spool_shard_dir = raiz SEMPRE, nenhum s*/ nasce (compat total);
#   2. determinismo/partição: mesmo login ⇒ mesmo shard; K logins caem em >1 shard;
#   3. produtor no shard certo: result de login do shard 1 gravado em s1/ é ingerido pelo
#      WORKER 1 (--drain) e NÃO pelo worker 0; history/results do usuário certos;
#   4. roteador do worker 0: result deixado na RAIZ (produtor legado) p/ login de outro
#      shard é MOVIDO p/ s<k>/ (e não processado pelo 0); o worker do shard o finaliza;
#   5. reconcile particionado: worker só carimba pendente dos PRÓPRIOS logins;
#   6. sweep de órfãos: dir s<j> com j>=K volta p/ a raiz.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$(mktemp -d)"; RUN="$(mktemp -d)"
trap 'rm -rf "$FIX" "$RUN"' EXIT
export CONTESTSDIR="$FIX" RUNDIR="$RUN"
export SPOOLDIR="$RUN/spool/submissions" SPOOLDONEDIR="$RUN/spool/submissions-done"
mkdir -p "$SPOOLDIR" "$SPOOLDONEDIR" "$RUN/results" "$RUN/assigned"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
bad(){ FAIL=$((FAIL+1)); echo "FALHOU: $*" >&2; }
check(){ if eval "$1"; then ok; else bad "$2"; fi }

C="$FIX/sz"; mkdir -p "$C/var"
NOW=$EPOCHSECONDS
printf 'CONTEST_ID=sz\nCONTEST_TYPE=icpc\nDEMO=1\nCONTEST_START=%s\nCONTEST_END=%s\nPROBS=( x pa A A pa )\n' \
  "$((NOW-3600))" "$((NOW+86400))" > "$C/conf"

# --- 1. K=1: raiz sempre, sem subdir -----------------------------------------------------
( export JUDGED_SHARDS=1
  source "$ROOT/api/v1/lib/spool-shard.sh"
  d="$(spool_shard_dir "aluno-qualquer")"
  [[ "$d" == "$SPOOLDIR" ]] || exit 1
  compgen -G "$SPOOLDIR/s*" >/dev/null && exit 1
  exit 0 ) && ok || bad "K=1 tem de ser a raiz, sem s*/"

# --- 2. determinismo + espalhamento ------------------------------------------------------
mapfile -t SH < <( export JUDGED_SHARDS=4
  source "$ROOT/api/v1/lib/spool-shard.sh"
  for u in eq-0001 eq-0002 eq-0003 eq-0004 eq-0005 eq-0006 eq-0007 eq-0008; do
    shard_of_login "$u"; echo
  done
  shard_of_login eq-0001; echo )
check '[[ "${SH[0]}" == "${SH[8]}" ]]' "hash não determinístico"
check '(( $(printf "%s\n" "${SH[@]:0:8}" | sort -u | wc -l) > 1 ))' "8 logins caíram todos num shard só"

# acha 1 login de shard 0 e 1 de shard != 0 (p/ os cenários abaixo)
U0=""; U1=""; K1=""
for u in eq-0001 eq-0002 eq-0003 eq-0004 eq-0005 eq-0006 eq-0007 eq-0008; do
  k="$(JUDGED_SHARDS=4 bash -c "source '$ROOT/api/v1/lib/spool-shard.sh'; shard_of_login $u")"
  if [[ "$k" == 0 && -z "$U0" ]]; then U0="$u"; fi
  if [[ "$k" != 0 && -z "$U1" ]]; then U1="$u"; K1="$k"; fi
done
[[ -n "$U0" && -n "$U1" ]] || { echo "fixture azarada: sem par de shards distintos"; exit 1; }
for u in "$U0" "$U1"; do mkdir -p "$C/users/$u/mojlog" "$C/users/$u/results" "$C/users/$u/submissions"; : > "$C/users/$u/history"; done

mkresult(){ # <login> <id> <destdir>
  printf '%s:pa:C:Not Answered Yet:%s:%s\n' "$NOW" "$NOW" "$2" >> "$C/users/$1/history"
  jq -cn --arg id "$2" --arg u "$1" \
    '{host:"mockj", id:$id, contest:"sz", problem_id:"pa", login:$u, lang:"C",
      verdict:"Wrong Answer", verdict_canon:"Wrong Answer",
      report_html_b64:"PGgxPm1vY2s8L2gxPgo="}' > "$3/sz:$NOW:$2:mockj:result:pa"
}

# --- 3. worker do shard certo processa o próprio dir -------------------------------------
mkdir -p "$SPOOLDIR/s$K1"
mkresult "$U1" idAAA "$SPOOLDIR/s$K1"
JUDGED_SHARDS=4 JUDGED_SHARD=0 bash "$ROOT/daemons/judged.sh" --drain >/dev/null 2>&1
check '[[ -f "$SPOOLDIR/s$K1/sz:$NOW:idAAA:mockj:result:pa" ]]' "worker 0 comeu arquivo do shard $K1"
JUDGED_SHARDS=4 JUDGED_SHARD="$K1" bash "$ROOT/daemons/judged.sh" --drain >/dev/null 2>&1
check 'grep -q ":Wrong Answer:.*:idAAA$" "$C/users/$U1/history"' "worker $K1 não finalizou idAAA"
check '[[ -f "$C/users/$U1/results/idAAA.json" ]]' "results/idAAA.json ausente"

# --- 4. roteador: result LEGADO na raiz, de login de outro shard -------------------------
mkresult "$U1" idBBB "$SPOOLDIR"
JUDGED_SHARDS=4 JUDGED_SHARD=0 bash "$ROOT/daemons/judged.sh" --drain >/dev/null 2>&1
check '[[ -f "$SPOOLDIR/s$K1/sz:$NOW:idBBB:mockj:result:pa" ]]' "roteador não moveu idBBB p/ s$K1"
check '! grep -q ":Wrong Answer:.*:idBBB$" "$C/users/$U1/history"' "worker 0 finalizou idBBB (era do $K1)"
JUDGED_SHARDS=4 JUDGED_SHARD="$K1" bash "$ROOT/daemons/judged.sh" --drain >/dev/null 2>&1
check 'grep -q ":Wrong Answer:.*:idBBB$" "$C/users/$U1/history"' "worker $K1 não finalizou idBBB roteado"

# --- 4b. result do PRÓPRIO shard 0 na raiz segue processado ------------------------------
mkresult "$U0" idCCC "$SPOOLDIR"
JUDGED_SHARDS=4 JUDGED_SHARD=0 bash "$ROOT/daemons/judged.sh" --drain >/dev/null 2>&1
check 'grep -q ":Wrong Answer:.*:idCCC$" "$C/users/$U0/history"' "worker 0 não finalizou o próprio idCCC"

# --- 5. reconcile particionado -----------------------------------------------------------
# pendente VELHO dos dois logins, sem rastro: worker 0 só pode carimbar o do U0
sed -i '/idAAA\|idBBB/!d' "$C/users/$U1/history" 2>/dev/null
OLD=$((NOW-3600))
printf '%s:pa:C:Not Answered Yet:%s:idD0\n' "$OLD" "$OLD" >> "$C/users/$U0/history"
printf '%s:pa:C:Not Answered Yet:%s:idD1\n' "$OLD" "$OLD" >> "$C/users/$U1/history"
sed -i 's/^DEMO=1$/DEMO=0/' "$C/conf"   # reconcile pula contest DEMO
JUDGED_SHARDS=4 JUDGED_SHARD=0 PENDING_TTL_MIN=1 bash "$ROOT/daemons/judged.sh" --reconcile >/dev/null 2>&1
check 'grep -q ":Judge Error:.*:idD0$" "$C/users/$U0/history"' "reconcile do 0 não resolveu idD0"
check 'grep -q ":Not Answered Yet:.*:idD1$" "$C/users/$U1/history"' "reconcile do 0 tocou login do shard $K1"
JUDGED_SHARDS=4 JUDGED_SHARD="$K1" PENDING_TTL_MIN=1 bash "$ROOT/daemons/judged.sh" --reconcile >/dev/null 2>&1
check 'grep -q ":Judge Error:.*:idD1$" "$C/users/$U1/history"' "reconcile do $K1 não resolveu idD1"

# --- 6. sweep de órfãos (API com K maior que o daemon) -----------------------------------
mkdir -p "$SPOOLDIR/s7"
mkresult "$U0" idEEE "$SPOOLDIR/s7"
( export JUDGED_SHARDS=4 JUDGED_SHARD=0 SPOOLDIR RUNDIR CONTESTSDIR
  source "$ROOT/api/v1/lib/spool-shard.sh"
  MY_SPOOL="$SPOOLDIR"
  source /dev/stdin <<< "$(sed -n '/^sweep_orphan_shards()/,/^}/p' "$ROOT/daemons/judged.sh")"
  sweep_orphan_shards )
check '[[ -f "$SPOOLDIR/sz:$NOW:idEEE:mockj:result:pa" ]]' "sweep não devolveu órfão de s7 à raiz"

echo "smoke-judged-shard: PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
