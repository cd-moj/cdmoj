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

# ---------------------------------------------------------------------------------------------
# REGEN EM BACKGROUND TEM DE SER BACKGROUND DE VERDADE.
# O `ensure_owners_index` dispara a varredura da base (medida em produção: 39,8 s) quando o índice
# passa do TTL. Ela é `setsid ... &` — mas o `>/dev/null 2>&1` estava DENTRO do `bash -c`, então o
# setsid herdava a saída do CGI, e sob fcgiwrap a resposta só termina quando TODO descritor do
# socket fecha: quem chegasse primeiro depois do TTL esperava a varredura INTEIRA. Medido em
# produção antes do conserto: 39,6 s numa rota que já tinha o dado pronto para responder.
# Aqui o "gerador" é um stub que dorme — se o chamador esperar por ele, o teste percebe.
# ⚠ TEM DE PASSAR PELO ROUTER, com a saída capturada por `$(…)`: é a substituição de comando
# que espera o stdout FECHAR — exatamente o que o fcgiwrap faz com o socket. Chamando a função
# direto, o filho vazado não segura ninguém e o teste passa COM o bug presente (tentei).
echo "-- regen por TTL não pode segurar o chamador --"
STUB="$T/stubtools"; mkdir -p "$STUB"
printf '#!/bin/bash\nsleep 5\n' > "$STUB/gen-problem-owners.sh"; chmod +x "$STUB/gen-problem-owners.sh"
printf '{"problems":[{"id":"o#p","repo":"o","prob":"p","owner":"tester","collaborators":[],"public":true,"collections":["o"],"tl_checksum":"abc"}]}' > "$CONTESTSDIR/treino/var/problem-owners.json"
rm -f "$CONTESTSDIR/treino/var/authored.json"
rmdir "$CONTESTSDIR/treino/var/problem-owners.json.lock" 2>/dev/null
mkdir -p "$RUNDIR/sessions"; printf 'CONTEST=treino\nLOGIN=tester\nUSERFULLNAME=T\nLOGINAT=1\n' > "$RUNDIR/sessions/tk"
chmod 600 "$RUNDIR/sessions/tk"
# a sessão MORRE COM A CONTA (_session_account_alive): sem o account.json a rota dá 401 e o
# teste passa por não chegar ao índice — que foi o que aconteceu na 1ª tentativa
mkdir -p "$CONTESTSDIR/treino/users/tester"
printf '{"login":"tester","password":"x","fullname":"T","status":"active"}' > "$CONTESTSDIR/treino/users/tester/account.json"
touch -d '-90 minutes' "$CONTESTSDIR/treino/var/problem-owners.json"
t0=$(date +%s%N)
RESP="$(env PATH_INFO=/problems/mine REQUEST_METHOD=GET QUERY_STRING="" \
   HTTP_AUTHORIZATION="Bearer tk" CONTESTSDIR="$CONTESTSDIR" RUNDIR="$RUNDIR" \
   SESSIONDIR="$RUNDIR/sessions" MOJ_PROBLEMS_DIR="$MOJ_PROBLEMS_DIR" MOJTOOLS_DIR="$STUB" \
   PROBLEM_OWNERS_TTL_MIN=30 bash "$API/router.sh" </dev/null 2>/dev/null)"
ms=$(( ($(date +%s%N) - t0) / 1000000 ))
chk "responde sem esperar a varredura (< 2s)" "$( (( ms < 2000 )) && echo sim || echo "NAO(${ms}ms)" )" "sim"
chk "e respondeu de verdade"                  "$(grep -c '"success":true' <<<"$RESP")" "1"
sleep 6; rmdir "$CONTESTSDIR/treino/var/problem-owners.json.lock" 2>/dev/null

printf '\n%s ok, %s falha(s)\n' "$ok" "$bad"
(( bad == 0 ))
