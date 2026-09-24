#!/bin/bash
# smoke-sample-flag.sh — PROBLEMA SEM EXEMPLO (`SAMPLE=no` no conf, 2026-09-23). Ver docs/PACOTE.md,
# "Problema sem exemplo".
#   1. seleção (mojtools/statement-langs.sh): exemplo é SÓ sample*; SAMPLE=no esconde até os sample*;
#      sem sample* e sem flag não há exemplo — TESTE OCULTO NUNCA vira exemplo (o fallback de legado
#      mostrava os 2 primeiros testes: em problema de função, o formato interno do driver);
#   2. validador: examples_present exige sample* OU SAMPLE=no; o aviso "exemplo-no-texto" some com
#      SAMPLE=no (o texto é o lugar do exemplo);
#   3. tl-checksum IGNORA a linha SAMPLE (marcar não recalibra), e conf sem ela dá o hash de antes;
#   4. server/bin/sample-flag-migrate.sh: dry-run não mexe; --apply marca SAMPLE=no no COMEÇO do conf,
#      tira o arquivo `samples` legado, commita, e o tl-checksum não muda.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
: "${MOJTOOLS_DIR:=$(cd "$ROOT/../../mojtools" && pwd)}"; export MOJTOOLS_DIR
command -v pandoc >/dev/null 2>&1 || { echo "SKIP: sem pandoc (render do enunciado)"; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export RUNDIR="$T/run" CONTESTSDIR="$T/contests" MOJ_PROBLEMS_DIR="$T/probs" TL_STORE_DIR="$T/run/tl"
mkdir -p "$RUNDIR/tl" "$CONTESTSDIR/treino/var/jsons" "$CONTESTSDIR/treino/var/jsons-private"
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; ((fail++)); fi; }

mkpkg(){ # <org/prob> <conf-bytes> [sample?]  — pacote mínimo com 1 teste oculto (SEGREDO)
  local p="$MOJ_PROBLEMS_DIR/$1"; mkdir -p "$p/docs" "$p/tests/input" "$p/tests/output" "$p/sols/good"
  printf 'Implemente f.\n\n## Entrada\n\nOs parametros.\n\n## Saída\n\nO retorno.\n\n## Exemplo\n\n`f(3)` devolve `9`.\n' > "$p/docs/enunciado.md"
  printf 'SEGREDO-DRIVER (()())\n' > "$p/tests/input/001"; printf '9\n' > "$p/tests/output/001"
  printf 'SEGREDO-DOIS\n' > "$p/tests/input/002"; printf '4\n' > "$p/tests/output/002"
  [[ "${3:-}" == sample ]] && { printf '3\n' > "$p/tests/input/sample1"; printf '9\n' > "$p/tests/output/sample1"; }
  printf 'Autor\n' > "$p/author"; printf 'int f(int x){return x*x;}\n' > "$p/sols/good/a.c"
  printf '{"public":true,"display_title":"F"}' > "$p/.moj-meta.json"
  printf '%b' "$2" > "$p/conf"; }
gen(){ TREINO_JSONS="$CONTESTSDIR/treino/var/jsons" MOJ_TL_STORE="$RUNDIR/tl" bash "$MOJTOOLS_DIR/gen-problem-json.sh" "$MOJ_PROBLEMS_DIR/$1" "${1/\//#}" >/dev/null 2>&1
  J="$CONTESTSDIR/treino/var/jsons/${1/\//#}.json"; H="$(jq -r .statement_html_b64 "$J" 2>/dev/null | base64 -d 2>/dev/null)"; }
val(){ VALIDATE_RUN_SOLS=0 TREINO_JSONS="$CONTESTSDIR/treino/var/jsons" bash "$MOJTOOLS_DIR/validate-problem.sh" "$MOJ_PROBLEMS_DIR/$1" "${1/\//#}" >/dev/null 2>&1
  V="$RUNDIR/validation/${1/\//#}.json"; }
ex(){ jq -r '.checks[] | select(.name=="examples_present") | "\(.ok) \(.detail)"' "$V" 2>/dev/null; }
sect(){ grep -q '<section class="moj-exemplos' <<<"$H"; }

echo "== 1. seleção dos exemplos =="
mkpkg o/leg 'TLMOD[calibrafactor]=1.35\n'
gen o/leg
ck "sem sample* e sem flag: samples [] e sem seção de exemplos"  '[[ "$(jq -c .samples "$J")" == "[]" ]] && ! sect'
ck "…e o teste oculto NÃO aparece (fim do fallback)"            '! grep -q SEGREDO <<<"$H" && ! grep -q SEGREDO "$J"'
mkpkg o/off 'SAMPLE=no\nTLMOD[calibrafactor]=1.35\n' sample
gen o/off
ck "SAMPLE=no COM sample1: samples [] e sem seção"              '[[ "$(jq -c .samples "$J")" == "[]" ]] && ! sect'
ck "…o exemplo do TEXTO continua no enunciado"                  'grep -q "devolve" <<<"$H"'
mkpkg o/std 'TLMOD[calibrafactor]=1.35\n' sample
gen o/std
ck "com sample1 e sem flag: samples [sample1] e seção presente" '[[ "$(jq -c "[.samples[].name]" "$J")" == "[\"sample1\"]" ]] && sect && ! grep -q SEGREDO <<<"$H"'
mkpkg o/quo 'SAMPLE="NO"\n' sample; gen o/quo
ck "SAMPLE=\"NO\" (aspas, maiúscula) também desliga"           '[[ "$(jq -c .samples "$J")" == "[]" ]]'
mkpkg o/yes 'SAMPLE=yes\n' sample; gen o/yes
ck "SAMPLE=yes não desliga"                                     '[[ "$(jq -c "[.samples[].name]" "$J")" == "[\"sample1\"]" ]]'
mkpkg o/lgf 'A=1\n'; : > "$MOJ_PROBLEMS_DIR/o/lgf/samples"; printf '1\n' > "$MOJ_PROBLEMS_DIR/o/lgf/tests/input/sample1"; printf '1\n' > "$MOJ_PROBLEMS_DIR/o/lgf/tests/output/sample1"
gen o/lgf
ck "arquivo 'samples' legado é ignorado (o sample1 aparece)"   '[[ "$(jq -c "[.samples[].name]" "$J")" == "[\"sample1\"]" ]]'

echo "== 2. validador =="
val o/leg
ck "sem sample* e sem flag: examples_present REPROVA com a dica" '[[ "$(ex)" == "false "*"SAMPLE=no"* && "$(jq -r .ok "$V")" == false ]]'
val o/off
ck "SAMPLE=no: examples_present passa (sem exemplos)"            '[[ "$(ex)" == "true sem exemplos (SAMPLE=no no conf)" ]]'
ck "SAMPLE=no: sem aviso exemplo-no-texto; aviso de sample* escondido" '! jq -r "tostring" "$V" | grep -q "exemplo-no-texto" && jq -r "tostring" "$V" | grep -q "sample-oculto-por-SAMPLE=no(1)"'
# bloco de código no texto COM SAMPLE=no: a precedência do `||` escapava da condição e avisava mesmo assim
mkpkg o/cod 'SAMPLE=no\n'; printf '\n```\nf(3) = 9\n```\n' >> "$MOJ_PROBLEMS_DIR/o/cod/docs/enunciado.md"
val o/cod
ck "SAMPLE=no + bloco de código no texto: sem aviso exemplo-no-texto" '! jq -r "tostring" "$V" | grep -q "exemplo-no-texto"'
val o/std
ck "com sample1: passa (1 exemplo) e avisa o exemplo no texto"  '[[ "$(ex)" == "true 1 exemplo(s)" ]] && jq -r "tostring" "$V" | grep -q "exemplo-no-texto"'

echo "== 3. tl-checksum ignora SAMPLE =="
P="$MOJ_PROBLEMS_DIR/o/std"; cks(){ bash "$MOJTOOLS_DIR/tl-checksum.sh" "$@" "$P"; }
a="$(cks)"; aa="$(cks --all-sols)"; printf 'SAMPLE=no\n' >> "$P/conf"
ck "acrescentar SAMPLE=no não muda o tl-checksum nem a versão do pacote" '[[ "$(cks)" == "$a" && "$(cks --all-sols)" == "$aa" ]]'
printf 'TLMOD[calibrafactor]=2\n' > "$P/conf"
ck "mudar outra chave do conf muda (controle)"                   '[[ "$(cks)" != "$a" ]]'

echo "== 4. sample-flag-migrate.sh =="
M="$MOJ_PROBLEMS_DIR"; rm -rf "$M"; mkdir -p "$M"
mkpkg fn/semex 'TLMOD[calibrafactor]=1.35\nULIMITS[-u]=10000'          # conf SEM \n final
mkpkg it/legado 'ULIMITS[-u]=10000\n' sample; : > "$M/it/legado/samples"  # samples vazio + sample1
mkpkg ok/normal 'A=1\n' sample
mkpkg ok/jatem 'SAMPLE=no\n'
mkpkg xx/lista 'A=1\n'; printf 'test1\n' > "$M/xx/lista/samples"
for d in "$M"/*/*; do git -C "$d" init -q; git -C "$d" add -A; git -C "$d" -c user.name=t -c user.email=t@t commit -qm init; done
c0="$(bash "$MOJTOOLS_DIR/tl-checksum.sh" "$M/fn/semex")"; c1="$(bash "$MOJTOOLS_DIR/tl-checksum.sh" "$M/it/legado")"
OUT="$(bash "$ROOT/bin/sample-flag-migrate.sh" 2>&1)"
ck "dry-run lista os 2 a migrar e o de lista à mão"             'grep -q "fn/semex.*+ SAMPLE=no" <<<"$OUT" && grep -q "it/legado.*+ SAMPLE=no.*- samples" <<<"$OUT" && grep -q "xx/lista: arquivo samples COM nomes" <<<"$OUT" && ! grep -q "ok/normal\|ok/jatem" <<<"$OUT"'
ck "dry-run não mexe em nada"                                   '! grep -q SAMPLE "$M/fn/semex/conf" && [[ -f "$M/it/legado/samples" ]]'
OUT="$(bash "$ROOT/bin/sample-flag-migrate.sh" --apply 2>&1)"
ck "--apply: SAMPLE=no no COMEÇO do conf, resto intacto (sem \\n final)" '[[ "$(head -1 "$M/fn/semex/conf")" == SAMPLE=no && "$(tail -c 6 "$M/fn/semex/conf")" == "=10000" ]]'
ck "--apply: samples legado removido e SAMPLE=no gravado"       '[[ ! -e "$M/it/legado/samples" ]] && grep -q "^SAMPLE=no" "$M/it/legado/conf"'
ck "--apply: tl-checksum idêntico ao de antes (nada recalibra)" '[[ "$(bash "$MOJTOOLS_DIR/tl-checksum.sh" "$M/fn/semex")" == "$c0" && "$(bash "$MOJTOOLS_DIR/tl-checksum.sh" "$M/it/legado")" == "$c1" ]]'
ck "--apply: um commit por pacote, autor moj"                   '[[ "$(git -C "$M/fn/semex" log -1 --format=%an:%s)" == "moj:exemplos: SAMPLE=no"* && "$(git -C "$M/it/legado" status --porcelain | wc -l)" == 0 ]]'
ck "--apply: intocados (normal, já marcado, lista)"             '[[ "$(git -C "$M/ok/normal" log --oneline | wc -l)" == 1 && "$(git -C "$M/ok/jatem" log --oneline | wc -l)" == 1 && -f "$M/xx/lista/samples" ]]'
OUT="$(bash "$ROOT/bin/sample-flag-migrate.sh" 2>&1)"
ck "idempotente: depois do --apply, nada a migrar"              'grep -q " 0 a migrar" <<<"$OUT"'
source <(sed -n '/^_rx()/p' "$ROOT/bin/sample-flag-migrate.sh")
RX="^($(_rx 'o.x#a(b)')|$(_rx 'fn#semex'))\$"
ck "id -> regex do reindex: literal (ponto/parênteses escapados)" '[[ "$(printf "o.x#a(b)\noxx#a(b)\nfn#semex\n" | grep -Ec "$RX")" == 2 ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
