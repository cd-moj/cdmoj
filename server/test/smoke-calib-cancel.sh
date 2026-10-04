#!/bin/bash
# smoke-calib-cancel.sh — POST /ops/calib-cancel (cancelar calibrações de um problema) devolve as CONTAGENS certas
# e não larga temporário. Antes (achado de 04/10/2026): as contagens iam p/ "$UPDATESDIR/.cancel-*.${BASHPID}"
# gravados de dentro de um SUBSHELL (BASHPID do filho) e lidos pelo pai com outro nome — removed_pending,
# removed_inprogress e inflight saíam SEMPRE 0 e os arquivos ficavam largados em UPDATESDIR.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$HERE/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN"
T="$FIX/treino"; mkdir -p "$T/var"; printf 'CONTEST_ID=treino\n' > "$T/conf"
fx_user "$T" rb.admin s Admin >/dev/null; fx_user "$T" ana s Ana >/dev/null
printf 'CONTEST=treino\nLOGIN=rb.admin\nLOGINAT=1\n' > "$SESS/adm"; printf 'CONTEST=treino\nLOGIN=ana\nLOGINAT=1\n' > "$SESS/ana"
U="$RUN/updates"; mkdir -p "$U/pending" "$U/inprogress/j1" "$U/inprogress/j2" "$RUN/commands/j1" "$RUN/commands/j2"
mk(){ jq -cn "$2" > "$1"; }
seed(){
  mk "$U/pending/a.json" '{kind:"calibrate", target:"org#p"}'; mk "$U/pending/b.json" '{kind:"calibrate", target:"org#p"}'
  mk "$U/pending/c.json" '{kind:"calibrate", target:"org#outro"}'
  mk "$RUN/commands/j1/x.json" '{action:"calibrate", id:"org#p"}'; mk "$RUN/commands/j2/y.json" '{action:"calibrate", id:"org#p"}'
  mk "$RUN/commands/j2/z.json" '{action:"calibrate", id:"org#outro"}'
  mk "$U/inprogress/j1/i1.json" '{kind:"calibrate", target:"org#p"}'; mk "$U/inprogress/j2/i2.json" '{kind:"calibrate", target:"org#p"}'
  mk "$U/inprogress/j2/i3.json" '{kind:"calibrate", target:"org#outro"}'
}
call(){ OUT="$(PATH_INFO=/ops/calib-cancel REQUEST_METHOD=POST HTTP_AUTHORIZATION="Bearer ${2:-adm}" bash "$ROUTER" <<<"$1" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
J(){ jq -r "$1" <<<"$BODY" 2>/dev/null; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:240}"; ((fail++)); fi; }

echo "== sem inprogress: remove pendentes e direcionados, CONTA os em execução =="
seed; call '{"id":"org#p"}'
ck "removed_pending = 2"            '[[ "$(J .removed_pending)" == 2 && ! -e "$U/pending/a.json" && -e "$U/pending/c.json" ]]'
ck "removed_targeted = 2"           '[[ "$(J .removed_targeted)" == 2 && ! -e "$RUN/commands/j1/x.json" && -e "$RUN/commands/j2/z.json" ]]'
ck "inflight = 2, nada removido"    '[[ "$(J .inflight)" == 2 && "$(J .removed_inprogress)" == 0 && -e "$U/inprogress/j1/i1.json" ]]'
ck "nenhum temporário largado"      '[[ -z "$(find "$U" -maxdepth 1 -name ".cancel-*" | head -1)" ]]'
echo "== com inprogress:true: remove também os em execução do problema =="
call '{"id":"org#p","inprogress":true}'
ck "removed_inprogress = 2; o de outro problema fica" '[[ "$(J .removed_inprogress)" == 2 && "$(J .inflight)" == 0 && ! -e "$U/inprogress/j2/i2.json" && -e "$U/inprogress/j2/i3.json" ]]'
ck "nada mais pendente do problema" '[[ "$(J .removed_pending)" == 0 && "$(J .removed_targeted)" == 0 ]]'
ck "nenhum temporário largado"      '[[ -z "$(find "$U" -maxdepth 1 -name ".cancel-*" | head -1)" ]]'
echo "== só admin =="
call '{"id":"org#p"}' ana
ck "usuário comum = 403"            '[[ "$OUT" == *"Status: 403"* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
