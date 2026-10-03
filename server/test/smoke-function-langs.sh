#!/bin/bash
# smoke-function-langs.sh — SUBMISSÃO DE FUNÇÃO declarada (`FUNCTION_LANGS` no conf, 2026-09-30). Ver
# docs/PACOTE.md (conf, `FUNCTION_LANGS`). A metade do mojtools (tl-checksum, gen-problem-json, validate,
# install-fn, a heurística) tem o próprio teste: mojtools/fn/test-function-langs.sh. Aqui:
#   1. server/bin/function-langs-migrate.sh: dry-run não mexe; --apply PROPÕE a linha pela heurística
#      (main num heredoc) só em pacote de função — ban e OpenMP ficam de fora —, no COMEÇO do conf,
#      um commit `moj` por pacote, tl-checksum intacto; declarado que diverge só é LISTADO; sem conf é
#      pulado; idempotente;
#   2. o reindex leva `function_langs` ao json servível (o que o /contest/problems e o treino leem).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
: "${MOJTOOLS_DIR:=$(cd "$ROOT/../../mojtools" && pwd)}"; export MOJTOOLS_DIR
command -v pandoc >/dev/null 2>&1 || { echo "SKIP: sem pandoc (render do enunciado no reindex)"; exit 0; }
[[ -f "$MOJTOOLS_DIR/fn/driver-langs.sh" ]] || { echo "SKIP: mojtools sem fn/driver-langs.sh (git pull)"; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export RUNDIR="$T/run" CONTESTSDIR="$T/contests" MOJ_PROBLEMS_DIR="$T/probs" TL_STORE_DIR="$T/run/tl"
mkdir -p "$RUNDIR/tl" "$CONTESTSDIR/treino/var/jsons" "$CONTESTSDIR/treino/var/jsons-private"
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:-}"; ((fail++)); fi; }

M="$MOJ_PROBLEMS_DIR"
mkpkg(){ # <org/prob> <conf-bytes|-> — pacote mínimo; '-' = sem conf
  local p="$M/$1"; mkdir -p "$p/docs" "$p/tests/input" "$p/tests/output" "$p/sols/good" "$p/scripts"
  printf 'Implemente f.\n\n## Entrada\n\nx\n\n## Saída\n\ny\n' > "$p/docs/enunciado.md"
  printf '1\n' > "$p/tests/input/001"; printf '1\n' > "$p/tests/output/001"; printf 'Autor\n' > "$p/author"
  printf '{"owner":"autor","public":true,"display_title":"F"}' > "$p/.moj-meta.json"
  [[ "$2" == - ]] || printf '%b' "$2" > "$p/conf"; }
drv(){ mkdir -p "$M/$1/scripts/$2"; printf '#!/bin/bash\ncat > /tmp/rwdir/__judge_main.c <<'"'"'EOF'"'"'\nint f(int);\nint main(void){ return 0; }\nEOF\nmake\n' > "$M/$1/scripts/$2/compile.sh"; }
ban(){ mkdir -p "$M/$1/scripts/$2"; printf '#!/bin/bash\n# programa completo: proíbe strlen\ngrep -q strlen *.c && exit 1\nmake\n' > "$M/$1/scripts/$2/compile.sh"; }

echo "== 1. function-langs-migrate.sh =="
mkpkg fn/soma 'STOPWHEN_TLE=y\nSTOPWHEN_WA=n\nTLMOD[calibrafactor]=1.35\nULIMITS[-u]=10000'; drv fn/soma c; drv fn/soma py3   # conf SEM \n final
mkpkg ban/cesar 'A=1\n'; ban ban/cesar c                          # ban: programa completo
mkpkg omp/par 'CPUNEEDED=4\n'; ban omp/par cpp                     # OpenMP/flags: programa completo
mkpkg fn/jadecl 'FUNCTION_LANGS=c\n'; drv fn/jadecl c; drv fn/jadecl java   # declarado, diverge
mkpkg fn/semconf -; drv fn/semconf c
for d in "$M"/*/*; do git -C "$d" init -q; git -C "$d" add -A; git -C "$d" -c user.name=t -c user.email=t@t commit -qm init; done
# o reindex parte do índice de donos (reindex-all.sh) — gera o da fixture
bash "$MOJTOOLS_DIR/gen-problem-owners.sh" >/dev/null 2>&1
c0="$(bash "$MOJTOOLS_DIR/tl-checksum.sh" "$M/fn/soma")"
OUT="$(bash "$ROOT/bin/function-langs-migrate.sh" 2>&1)"; DBG="$OUT"
ck "dry-run: propõe c,py só no de função"                        'grep -q "fn/soma  + FUNCTION_LANGS=c,py" <<<"$OUT" && ! grep -q "ban/cesar\|omp/par" <<<"$OUT"'
ck "dry-run: o declarado que diverge é só listado"                'grep -q "fn/jadecl: declarado FUNCTION_LANGS=c, driver em c,java" <<<"$OUT"'
ck "dry-run: sem conf é pulado"                                   'grep -q "fn/semconf: SEM conf" <<<"$OUT"'
ck "dry-run não mexe em nada"                                     '! grep -q FUNCTION_LANGS "$M/fn/soma/conf"'
OUT="$(bash "$ROOT/bin/function-langs-migrate.sh" --apply 2>&1)"; DBG="$OUT"
ck "--apply: a linha no COMEÇO, o resto intacto (sem \\n final)"  '[[ "$(head -1 "$M/fn/soma/conf")" == FUNCTION_LANGS=c,py && "$(tail -c 6 "$M/fn/soma/conf")" == "=10000" ]]'
ck "--apply: tl-checksum idêntico (nada recalibra)"               '[[ "$(bash "$MOJTOOLS_DIR/tl-checksum.sh" "$M/fn/soma")" == "$c0" ]]'
ck "--apply: um commit, autor moj, árvore limpa"                  '[[ "$(git -C "$M/fn/soma" log -1 --format=%an:%s)" == "moj:submissão de função: FUNCTION_LANGS=c,py"* && -z "$(git -C "$M/fn/soma" status --porcelain)" ]]'
ck "--apply: intocados (ban, OpenMP, declarado, sem conf)"        '[[ "$(git -C "$M/ban/cesar" log --oneline | wc -l)" == 1 && "$(git -C "$M/omp/par" log --oneline | wc -l)" == 1 && "$(git -C "$M/fn/jadecl" log --oneline | wc -l)" == 1 && ! -f "$M/fn/semconf/conf" ]]'
J="$CONTESTSDIR/treino/var/jsons-private/fn#soma.json"; DBG="$(cat "$J" 2>&1 | head -c 200)"
ck "o reindex leva function_langs ao json servível"               '[[ "$(jq -c .function_langs "$J")" == "[\"c\",\"py\"]" ]]'
# TCP 2026 (03/10/2026): parar no 1º erro + nº de testes vão ao json servível (o checklist da prova, sem abrir pacote)
ck "o json servível leva stop_when (do conf) e o nº de testes"    '[[ "$(jq -c .stop_when "$J")" == "{\"wa\":false,\"tle\":true,\"re\":false}" && "$(jq .tests "$J")" == 1 ]]'
OUT="$(bash "$ROOT/bin/function-langs-migrate.sh" 2>&1)"; DBG="$OUT"
ck "idempotente: depois do --apply, nada a migrar"                'grep -q " 0 a migrar" <<<"$OUT"'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
