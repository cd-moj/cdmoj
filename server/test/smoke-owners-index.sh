#!/bin/bash
# smoke-owners-index.sh — o ÍNDICE DE PROBLEMAS NÃO PODE MENTIR.
#
# O bug que este teste tranca: com `jq -s A B`, se A (o problem-owners.json) NÃO EXISTE ou tem 0 byte,
# o jq só reclama no stderr (engolido pelo 2>/dev/null), NÃO aborta, e as entradas ANDAM UMA CASA —
# `.[0]` vira o OVERLAY. O programa então imprime um `{"problems":[]}` PERFEITAMENTE VÁLIDO: a guarda
# `[[ -n "$out" ]]` não dispara e a API responde **200 com lista vazia**. Board, Painel, `moj ls`,
# coleções e orgs ficam vazios, calados — indistinguível de "você não tem problema nenhum".
#
# Regra: índice ausente/0-byte/quebrado ⇒ owners_merged ERRA (rc!=0, stdout vazio) ⇒ o handler
# responde 503. Overlay quebrado ⇒ é IGNORADO (é só visibilidade imediata), o índice segue valendo.
set -uo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
API="$(cd "$HERE/../api/v1" && pwd)"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export CONTESTSDIR="$T/contests" RUNDIR="$T/run" MOJ_PROBLEMS_DIR="$T/moj-problems"
export MOJTOOLS_DIR="${MOJTOOLS_DIR:-$(cd "$HERE/../../../mojtools" && pwd)}"
export SESSION_LOGIN=tester
mkdir -p "$CONTESTSDIR/treino/var" "$RUNDIR" "$MOJ_PROBLEMS_DIR"

# stubs do ambiente de handler (não vamos emitir HTTP aqui)
emit_json(){ :; }
fail(){ printf 'FAIL_CALLED %s %s\n' "$1" "${3:-}"; exit 9; }
EPOCHSECONDS="${EPOCHSECONDS:-0}"
# shellcheck disable=SC1090
source "$API/lib/problems.sh"

IDX="$CONTESTSDIR/treino/var/problem-owners.json"
OVL="$CONTESTSDIR/treino/var/authored.json"
ok=0; bad=0
chk(){ if [[ "$2" == "$3" ]]; then echo "  ok   $1"; ok=$((ok+1)); else echo "  FALHA $1: esperado '$3', veio '$2'"; bad=$((bad+1)); fi; }

# Neutraliza a regeração (o gerador precisaria de um acervo real): o que se testa aqui é a REAÇÃO da
# lib a um índice inutilizável, não o gerador.
ensure_owners_index(){ [[ -s "$IDX" ]] && jq -e . "$IDX" >/dev/null 2>&1; }

# 1) índice BOM + overlay ausente -> lista o índice
printf '{"problems":[{"id":"o#p","owner":"tester","public":false}]}\n' > "$IDX"
rm -f "$OVL"
out="$(owners_merged)"; rc=$?
chk "índice bom => rc 0"            "$rc" "0"
chk "índice bom => 1 problema"      "$(jq -r '.problems|length' <<<"$out")" "1"

# 2) índice AUSENTE -> ERRO (antes: {"problems":[]} com rc 0 — o bug)
rm -f "$IDX"
out="$(owners_merged 2>/dev/null)"; rc=$?
chk "índice AUSENTE => rc != 0"     "$([[ $rc -ne 0 ]] && echo sim || echo nao)" "sim"
chk "índice AUSENTE => stdout vazio" "$(printf '%s' "$out" | wc -c)" "0"

# 3) índice 0 BYTE -> ERRO (era "presente" p/ o `[[ -f ]]`, nunca regenerava)
: > "$IDX"
out="$(owners_merged 2>/dev/null)"; rc=$?
chk "índice 0-byte => rc != 0"      "$([[ $rc -ne 0 ]] && echo sim || echo nao)" "sim"

# 4) índice QUEBRADO (JSON inválido) -> ERRO
printf '{"problems":[' > "$IDX"
out="$(owners_merged 2>/dev/null)"; rc=$?
chk "índice quebrado => rc != 0"    "$([[ $rc -ne 0 ]] && echo sim || echo nao)" "sim"

# 5) overlay QUEBRADO + índice bom -> o índice PREVALECE (o overlay é só visibilidade imediata)
printf '{"problems":[{"id":"o#p","owner":"tester","public":false}]}\n' > "$IDX"
printf 'lixo{{{' > "$OVL"
out="$(owners_merged)"; rc=$?
chk "overlay quebrado => rc 0"      "$rc" "0"
chk "overlay quebrado => índice vale" "$(jq -r '.problems|length' <<<"$out")" "1"

# 6) overlay BOM -> mescla (overlay vence campo-a-campo, sem apagar o que só o índice calcula)
printf '{"problems":[{"id":"o#p","owner":"tester","public":false,"tl_checksum":"abc"}]}\n' > "$IDX"
printf '{"o#p":{"id":"o#p","owner":"tester","public":true},"o#q":{"id":"o#q","owner":"tester","public":false}}\n' > "$OVL"
out="$(owners_merged)"
chk "mescla => 2 problemas"          "$(jq -r '.problems|length' <<<"$out")" "2"
chk "overlay vence (public)"         "$(jq -r 'first(.problems[]|select(.id=="o#p")).public' <<<"$out")" "true"
chk "índice sobrevive (tl_checksum)" "$(jq -r 'first(.problems[]|select(.id=="o#p")).tl_checksum' <<<"$out")" "abc"

printf '\n%s ok, %s falha(s)\n' "$ok" "$bad"
(( bad == 0 ))
