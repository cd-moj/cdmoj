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
# TÍTULO: o overlay NÃO PODE ATROPELAR O TÍTULO BOM DO ÍNDICE COM O SLUG.
# O upsert antigo, com título vazio (o caso NORMAL de todo chamador que lê `.display_title // ""`
# de um pacote migrado sem o campo — set-public, set-collections, move, upload, import, retag),
# gravava `title = <prob>`. Como o overlay vence a mescla e o authored_prune trata divergência como
# "não podar", o Painel mostrava `obi2023f2pj_pizza` no lugar de "Pizza da OBI" — 21 problemas, e
# para sempre (relato do Ribas, 21/09/2026).
echo "-- título: overlay não inventa, e o slug nunca vence o índice --"
printf '{"problems":[{"id":"o#p","repo":"o","prob":"p","owner":"tester","public":true,"title":"Pizza da OBI","tl_checksum":"abc"}]}\n' > "$IDX"
printf '{"o#p":{"id":"o#p","repo":"o","prob":"p","owner":"tester","public":true,"title":"p"}}\n' > "$OVL"
out="$(owners_merged)"
chk "overlay com título=slug PERDE"  "$(jq -r 'first(.problems[]|select(.id=="o#p")).title' <<<"$out")" "Pizza da OBI"
printf '{"o#p":{"id":"o#p","repo":"o","prob":"p","owner":"tester","public":true,"title":""}}\n' > "$OVL"
chk "overlay com título VAZIO perde" "$(jq -r 'first(.problems[]|select(.id=="o#p")).title' <<<"$(owners_merged)")" "Pizza da OBI"
printf '{"o#p":{"id":"o#p","repo":"o","prob":"p","owner":"tester","public":true,"title":"Nome do autor"}}\n' > "$OVL"
chk "overlay com título DE VERDADE vence" "$(jq -r 'first(.problems[]|select(.id=="o#p")).title' <<<"$(owners_merged)")" "Nome do autor"
# título legítimo IGUAL ao slug (o índice concorda) continua aparecendo
printf '{"problems":[{"id":"o#p","repo":"o","prob":"p","owner":"tester","public":true,"title":"p"}]}\n' > "$IDX"
printf '{"o#p":{"id":"o#p","repo":"o","prob":"p","owner":"tester","public":true,"title":"p"}}\n' > "$OVL"
chk "slug legítimo (índice concorda) fica" "$(jq -r 'first(.problems[]|select(.id=="o#p")).title' <<<"$(owners_merged)")" "p"

echo "-- authored_upsert: título vazio NÃO vira slug --"
rm -f "$OVL"
authored_upsert "o#p" tester o p "" true '["o"]' "Autor"
chk "sem título => a chave não entra"  "$(jq -r '.["o#p"]|has("title")' "$OVL")" "false"
authored_upsert "o#p" tester o p "Pizza da OBI" true '["o"]' "Autor"
chk "com título => grava"              "$(jq -r '.["o#p"].title' "$OVL")" "Pizza da OBI"
authored_upsert "o#p" tester o p "" true '["o"]' "Autor"
chk "título anterior é preservado"     "$(jq -r '.["o#p"].title' "$OVL")" "Pizza da OBI"
# veneno velho no overlay (title==prob) não é preservado num upsert seguinte
printf '{"o#p":{"id":"o#p","repo":"o","prob":"p","owner":"tester","public":true,"title":"p"}}\n' > "$OVL"
authored_upsert "o#p" tester o p "" true '["o"]' "Autor"
chk "veneno (title=slug) é descartado" "$(jq -r '.["o#p"]|has("title")' "$OVL")" "false"

echo "-- read_problem_source: título do editor nunca vem em branco --"
# pacote SEM display_title (todo o acervo OBI é assim): o editor abria com o campo vazio, o autor
# salvava esse vazio e era ele que envenenava o overlay. Deriva do enunciado, como o gen-problem-json.
PK="$MOJ_PROBLEMS_DIR/o/p"; mkdir -p "$PK/docs"
printf '{"owner":"tester","public":true}\n' > "$PK/.moj-meta.json"
printf '%% Pizza da OBI\n\nO prof. Carlos comprou pizzas...\n' > "$PK/docs/enunciado.md"
chk "título derivado do enunciado"     "$(read_problem_source "$PK" | jq -r .title)" "Pizza da OBI"
jq -c '. + {display_title:"Nome do autor"}' "$PK/.moj-meta.json" > "$PK/.m.t" && mv -f "$PK/.m.t" "$PK/.moj-meta.json"
chk "display_title do pacote vence"    "$(read_problem_source "$PK" | jq -r .title)" "Nome do autor"
printf '{"owner":"tester","public":true}\n' > "$PK/.moj-meta.json"
printf 'Sem linha de título aqui.\n' > "$PK/docs/enunciado.md"
chk "sem título em lugar nenhum => slug" "$(read_problem_source "$PK" | jq -r .title)" "p"

echo "-- authored_prune: entrada sem título poda quando o índice já a reflete --"
printf '{"problems":[{"id":"o#p","repo":"o","prob":"p","owner":"tester","public":true,"title":"Pizza da OBI","collections":["o"],"collaborators":[]}]}\n' > "$IDX"
printf '{"o#p":{"id":"o#p","repo":"o","prob":"p","owner":"tester","public":true,"collections":["o"],"collaborators":[],"author":"Autor"}}\n' > "$OVL"
touch -d '-1 minute' "$OVL"; touch "$IDX"
authored_prune
chk "overlay sem título é podado"      "$(jq -r 'length' "$OVL")" "0"
# o VENENO que ficou no disco (title = slug) também tem de poder sair — senão as 21 entradas de
# produção viveriam para sempre, mesmo com a mescla já as ignorando
printf '{"o#p":{"id":"o#p","repo":"o","prob":"p","owner":"tester","public":true,"title":"p","collections":["o"],"collaborators":[],"author":"Autor"}}\n' > "$OVL"
touch -d '-1 minute' "$OVL"; touch "$IDX"
authored_prune
chk "overlay com título=slug é podado"  "$(jq -r 'length' "$OVL")" "0"
# … mas um título de verdade que o índice ainda não tem SEGURA a entrada (é p/ isso que ela existe)
printf '{"o#p":{"id":"o#p","repo":"o","prob":"p","owner":"tester","public":true,"title":"Nome novo","collections":["o"],"collaborators":[],"author":"Autor"}}\n' > "$OVL"
touch -d '-1 minute' "$OVL"; touch "$IDX"
authored_prune
chk "título novo do autor NÃO é podado"  "$(jq -r 'length' "$OVL")" "1"

echo "-- /problems/status: 'untitled' só quando não há título em lugar nenhum --"
# o Painel marca o problema POR NOMEAR (hoje o índice carimba o slug no lugar do título, e um
# problema sem nome ficava indistinguível de um com nome)
mkdir -p "$RUNDIR/sessions" "$CONTESTSDIR/treino/users/tester"
printf 'CONTEST=treino\nLOGIN=tester\nUSERFULLNAME=T\nLOGINAT=1\n' > "$RUNDIR/sessions/tk"; chmod 600 "$RUNDIR/sessions/tk"
printf '{"login":"tester","password":"x","fullname":"T","status":"active"}' > "$CONTESTSDIR/treino/users/tester/account.json"
jq -cn '{generated_at:0, count:2, problems:[
   {id:"o#p", repo:"o", prob:"p", owner:"tester", collaborators:[], public:true, title:"Pizza da OBI", collections:["o"]},
   {id:"o#q", repo:"o", prob:"q", owner:"tester", collaborators:[], public:true, title:"q", collections:["o"]}]}' > "$IDX"
rm -f "$OVL"; touch "$IDX"
STRESP="$(env PATH_INFO=/problems/status REQUEST_METHOD=GET QUERY_STRING="" \
   HTTP_AUTHORIZATION="Bearer tk" CONTESTSDIR="$CONTESTSDIR" RUNDIR="$RUNDIR" \
   SESSIONDIR="$RUNDIR/sessions" MOJ_PROBLEMS_DIR="$MOJ_PROBLEMS_DIR" MOJTOOLS_DIR="$MOJTOOLS_DIR" \
   PROBLEM_OWNERS_TTL_MIN=30 bash "$API/router.sh" </dev/null 2>/dev/null)"
STBODY="$(printf '%s' "$STRESP" | awk 'f{print} /^\r?$/{f=1}')"
chk "com título => untitled false" "$(jq -r 'first(.problems[]|select(.id=="o#p")).untitled' <<<"$STBODY")" "false"
chk "título = slug => untitled true" "$(jq -r 'first(.problems[]|select(.id=="o#q")).untitled' <<<"$STBODY")" "true"
chk "e o título continua saindo"     "$(jq -r 'first(.problems[]|select(.id=="o#p")).title' <<<"$STBODY")" "Pizza da OBI"

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
