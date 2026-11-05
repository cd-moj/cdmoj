#!/bin/bash
# RELÓGIO DO TL (05/11/2026; mojtools build-and-test, docs/PACOTE.md "Relógio do TL"). Pedido do Roberto/Ribas: em
# problema ICPC, TLCLOCK=cpu no conf cobra o TL pelo tempo de CPU (user+sys) e a parede vira só um teto maior. O juízo é
# do juiz (mojtools test-tl-clock.sh); o servidor só EXIBE. Garante, do lado do servidor:
#   · tl_conf_clock_to lê TLCLOCK/WALLTL SEM source (aspas, última linha, valor desconhecido = parede; WALLTL fora da
#     forma de número JSON = vazio) e o conf envenenado não executa nada;
#   · TLCLOCK MUDA o tl_checksum (o contrário do TLMETHOD: trocar o relógio recalibra);
#   · /problems/get, /problems/tl, /problems/calib, /ops/problemtl e /problems/status dizem o relógio;
#   · a folha de TL da prova (_doc_tl_table) marca o problema de CPU com † e a nota nos três idiomas.
# O /contest/problems (do json servível) fica no smoke-statement-langs.sh; o Central, no smoke-preflight.sh.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
: "${MOJTOOLS_DIR:=$(cd "$ROOT/../../mojtools" 2>/dev/null && pwd)}"; export MOJTOOLS_DIR
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; PROBS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN" "$PROBS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" MOJ_PROBLEMS_DIR="$PROBS" TL_STORE_DIR="$RUN/tl" \
       CALIB_DIR="$RUN/calib" UPDATESDIR="$RUN/updates"
mkdir -p "$RUN/tl" "$RUN/calib" "$RUN/secrets" "$FIX/treino/var"; printf 'mojw_smoketest' > "$RUN/secrets/worker.token"

NOW="$EPOCHSECONDS"
echo '{"col":{"members":["autor"],"admins":[],"public_allowed":true,"title":"Col"}}' > "$FIX/treino/var/orgs.json"
P="$PROBS/col/pa"; mkdir -p "$P/sols/good" "$P/tests/input" "$P/tests/output"
printf 'CALIBRATIONTL=5\n' > "$P/conf"
printf '{"owner":"autor","public":true,"display_title":"pa"}\n' > "$P/.moj-meta.json"
printf 'int main(){return 0;}\n' > "$P/sols/good/sol.c"
printf '1\n' > "$P/tests/input/t1"; printf '1\n' > "$P/tests/output/t1"
git -C "$P" init -q 2>/dev/null; git -C "$P" add -A 2>/dev/null
git -C "$P" -c user.name=t -c user.email=t@t commit -qm init 2>/dev/null
fx_user "$FIX/treino" autor s "Autor"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino autor Autor "$NOW" > "$SESS/aut"

pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:300}"; ((fail++)); fi; }
J(){ # <rota> <query> <método> <token> [corpo]
  OUT="$(PATH_INFO="$1" REQUEST_METHOD="$3" QUERY_STRING="$2" HTTP_AUTHORIZATION="Bearer $4" bash "$ROUTER" <<<"${5:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
source "$ROOT/api/v1/lib/tl-store.sh"; source "$ROOT/api/v1/lib/problems.sh" 2>/dev/null
rd(){ printf '%s\n' "$1" > "$P/conf"; local c w; tl_conf_clock_to c w "$P"; BODY="$c|$w"; }

echo "== tl_conf_clock_to: sem source, a última linha vence =="
rd 'CALIBRATIONTL=5';                ck "sem as chaves: parede, sem WALLTL"   '[[ "$BODY" == "wall|" ]]'
rd 'TLCLOCK=cpu';                    ck "cpu"                                  '[[ "$BODY" == "cpu|" ]]'
rd 'TLCLOCK="cpu" # icpc';           ck "entre aspas, com comentário"          '[[ "$BODY" == "cpu|" ]]'
rd $'TLCLOCK=cpu\nTLCLOCK=wall';     ck "a última linha vence"                 '[[ "$BODY" == "wall|" ]]'
rd 'TLCLOCK=CPU';                    ck "maiúscula = parede (o juiz compara exato)" '[[ "$BODY" == "wall|" ]]'
rd $'TLCLOCK=cpu\nWALLTL=8';         ck "WALLTL inteiro"                       '[[ "$BODY" == "cpu|8" ]]'
rd $'TLCLOCK=cpu\nWALLTL="8.5"';     ck "WALLTL decimal entre aspas"           '[[ "$BODY" == "cpu|8.5" ]]'
rd $'TLCLOCK=cpu\nWALLTL=08';        ck "WALLTL com zero à esquerda = vazio (vai por --argjson)" '[[ "$BODY" == "cpu|" ]]'
rd $'TLCLOCK=cpu\nWALLTL=abc';       ck "WALLTL não numérico = vazio"          '[[ "$BODY" == "cpu|" ]]'
rd "TLCLOCK=\$(touch $RUN/pwned)cpu"; ck "conf envenenado não executa nada"    '[[ ! -e "$RUN/pwned" && "$BODY" == "wall|" ]]'

echo "== tl_checksum: o relógio está DENTRO (trocar recalibra) =="
printf 'CALIBRATIONTL=5\n' > "$P/conf"; C0="$(pkg_tl_checksum "$P")"
printf 'CALIBRATIONTL=5\nTLCLOCK=cpu\n' > "$P/conf"; C1="$(pkg_tl_checksum "$P")"
printf 'CALIBRATIONTL=5\nTLCLOCK=cpu\nWALLTL=8\n' > "$P/conf"; C2="$(pkg_tl_checksum "$P")"
BODY="$C0 $C1 $C2"
ck "TLCLOCK e WALLTL mudam o carimbo" '[[ -n "$C0" && "$C0" != "$C1" && "$C1" != "$C2" ]]'

echo "== as rotas de gestão dizem o relógio =="
printf 'CALIBRATIONTL=5\nTLCLOCK=cpu\nWALLTL=8\n' > "$P/conf"
problem_commit "$P" autor "relógio de CPU" >/dev/null
J /problems/get "id=col%23pa" GET aut
ck "/problems/get: tl_clock cpu, wall_tl 8"   '[[ "$(jq -c "[.tl_clock, .wall_tl]" <<<"$BODY")" == "[\"cpu\",8]" ]]'
J /problems/tl "id=col%23pa" GET aut
ck "/problems/tl: idem"                       '[[ "$(jq -c "[.tl_clock, .wall_tl]" <<<"$BODY")" == "[\"cpu\",8]" ]]'
J /problems/calib "id=col%23pa" GET aut
ck "/problems/calib: idem"                    '[[ "$(jq -c "[.tl_clock, .wall_tl]" <<<"$BODY")" == "[\"cpu\",8]" ]]'
fx_user "$FIX/treino" boss.admin s "Boss"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino boss.admin Boss "$NOW" > "$SESS/adm"
J /ops/problemtl "problem=col%23pa" GET adm
ck "/ops/problemtl: idem"                     '[[ "$(jq -c "[.tl_clock, .wall_tl]" <<<"$BODY")" == "[\"cpu\",8]" ]]'
bash "$MOJTOOLS_DIR/gen-problem-owners.sh" >/dev/null 2>&1
J /problems/status "" GET aut
BODY="$(jq -c '.problems[] | select(.id=="col#pa")' <<<"$BODY")"
ck "/problems/status: tl_clock cpu (do índice de donos)" '[[ "$(jq -r .tl_clock <<<"$BODY")" == cpu ]]'
printf 'CALIBRATIONTL=5\n' > "$P/conf"; problem_commit "$P" autor "volta à parede" >/dev/null
J /problems/get "id=col%23pa" GET aut
ck "de volta à parede: wall e wall_tl null"   '[[ "$(jq -c "[.tl_clock, .wall_tl]" <<<"$BODY")" == "[\"wall\",null]" ]]'

echo "== a folha de TL da prova marca o problema de CPU (_doc_tl_table) =="
_DIR="$ROOT/api/v1"; source "$ROOT/api/v1/lib/contest-docs.sh" 2>/dev/null
CT="$FIX/ct"; mkdir -p "$CT"; printf 'LANGUAGES=%q\n' "c cpp" > "$CT/conf"
_doc_tl_matrix(){ printf '%s' '[{"letter":"A","name":"Alfa","cpu":true,"tl":{"c":1,"cpp":1}},{"letter":"B","name":"Beta","cpu":false,"tl":{"c":2,"cpp":2}}]'; }
for l in pt en es; do
  BODY="$(_doc_tl_table ct "$l")"
  case "$l" in pt) w='tempo de CPU';; en) w='CPU time';; es) w='tiempo de CPU';; esac
  ck "$l: Alfa com †, Beta sem, e a nota" '[[ "$BODY" == *">Alfa †<"* && "$BODY" == *">Beta<"* && "$BODY" == *"† "*"$w"* ]]'
done
_doc_tl_matrix(){ printf '%s' '[{"letter":"B","name":"Beta","cpu":false,"tl":{"c":2}}]'; }
BODY="$(_doc_tl_table ct pt)"
ck "sem problema de CPU: sem † nem a nota"    '[[ "$BODY" != *"†"* ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
