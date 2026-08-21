#!/bin/bash
# Cache do /contest/problems: a rota monta o MESMO payload p/ todos os times (~77 processos com
# 12 problemas) e 2000 deles a pedem no segundo em que a prova abre. O cache é por VARIANTE, e a
# variante existe por um motivo de SEGURANÇA: o AUTOR do problema só aparece com a prova
# encerrada ou p/ quem organiza — durante a prova o nome do autor é pista.
#
# O teste que importa é o de ENVENENAMENTO: um GET do juiz enche o cache com o autor dentro; o
# competidor NÃO pode receber esse corpo. Cobre também a invalidação por escrita do admin, por
# conf, por override de linguagem e o teto de idade.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; PKG="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$PKG"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"

C="$FIX/pc"; mkdir -p "$C/var" "$C/enunciados"
T0=$(( $(date +%s) - 3600 ))
{ printf 'CONTEST_ID=pc\nCONTEST_TYPE=icpc\nCONTEST_NAME=Prova\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$T0" "$((T0+18000))"
  printf 'PROBS=( x col#pa Alfa A col#pa x col#pb Beta B col#pb )\n'; } > "$C/conf"
fx_user "$C" pc.admin p "Admin"; fx_user "$C" pc.judge p "Juiz"
fx_user "$C" pc.cjudge p "Chefe"; fx_user "$C" time01 t "Time 01"
printf '<html><body>A</body></html>' > "$C/enunciados/col#pa.html"
printf '<html><body>B</body></html>' > "$C/enunciados/col#pb.html"
# pacote com AUTOR — é o dado que não pode vazar durante a prova
mkdir -p "$PKG/col/pa" "$PKG/col/pb"
printf 'Bruno Ribas\n' > "$PKG/col/pa/author"; printf 'Maria da Silva\n' > "$PKG/col/pb/author"
for u in pc.admin pc.judge pc.cjudge time01; do
  printf 'CONTEST=pc\nLOGIN=%s\nUSERFULLNAME=X\nLOGINAT=1\n' "$u" > "$SESS/$u"
done
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="${3:-GET}" QUERY_STRING="contest=pc" \
    HTTP_AUTHORIZATION="Bearer $2" CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$FIX/run" \
    PROBLEMS_CACHE_TTL="${PROBLEMS_CACHE_TTL:-}" \
    MOJ_PROBLEMS_DIR="$PKG" bash "$ROUTER" <<<"${4:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
autor(){ printf '%s' "$BODY" | jq -r '[.problems[]?|.author//empty]|join(",")'; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:180}"; ((fail++)); fi; }

echo "== o AUTOR não vaza pelo cache (o teste que motiva a variante) =="
call /contest/problems pc.judge
ck "juiz VÊ o autor"                 '[[ "$(autor)" == *"Bruno Ribas"* ]]'
ck "e o cache do juiz foi gravado"   '[[ -s "$C/var/problems-cache.author.json" ]]'
# agora o competidor pede — se a variante fosse ignorada, ele receberia o corpo do juiz
call /contest/problems time01
ck "competidor NÃO vê autor nenhum"  '[[ -z "$(autor)" ]]'
ck "e tem sua própria variante"      '[[ -s "$C/var/problems-cache.noauthor.json" ]]'
ck "os dois arquivos DIFEREM"        '! diff -q "$C/var/problems-cache.author.json" "$C/var/problems-cache.noauthor.json" >/dev/null'
ck "o de competidor não cita autor"  '! grep -q "Bruno Ribas" "$C/var/problems-cache.noauthor.json"'
# e na ordem inversa: competidor primeiro, juiz depois
rm -f "$C/var/problems-cache."*.json
call /contest/problems time01; ck "competidor primeiro: sem autor" '[[ -z "$(autor)" ]]'
call /contest/problems pc.judge; ck "juiz depois: COM autor"       '[[ "$(autor)" == *"Bruno Ribas"* ]]'
call /contest/problems pc.cjudge; ck "chefe também vê"             '[[ "$(autor)" == *"Bruno Ribas"* ]]'
call /contest/problems time01;   ck "competidor segue sem autor"   '[[ -z "$(autor)" ]]'

echo "== o cache é usado (mesma resposta, sem remontar) =="
call /contest/problems time01; A="$BODY"
call /contest/problems time01; ck "2ª chamada idêntica" '[[ "$BODY" == "$A" ]]'
ck "e veio do arquivo"        '[[ -s "$C/var/problems-cache.noauthor.json" ]]'

echo "== o ADMIN mexe na lista: invalida e regenera =="
call /contest/admin/problems pc.admin POST '{"action":"rename","letter":"A","name":"Alfa Renomeado"}'
ck "rename aceito"                '[[ "$(jq -r .saved <<<"$BODY")" == true ]]'
ck "carimbo de invalidação criado" '[[ -f "$C/var/.problems-dirty" ]]'
call /contest/problems time01
ck "o time JÁ vê o nome novo"     '[[ "$(jq -r ".problems[]|select(.short_name==\"A\").full_name" <<<"$BODY")" == "Alfa Renomeado" ]]'
call /contest/admin/problems pc.admin POST '{"action":"remove","letter":"B"}'
call /contest/problems time01
ck "remoção também aparece"       '[[ "$(jq -r "[.problems[].short_name]|join(\",\")" <<<"$BODY")" == "A" ]]'

echo "== invalida por ENTRADA, mesmo sem carimbo (rede de segurança) =="
rm -f "$C/var/.problems-dirty"
call /contest/problems time01 >/dev/null
sleep 1; printf 'PROBS=( x col#pa Alfa A col#pa x col#pb Beta B col#pb )\n' >> "$C/conf"
call /contest/problems time01
ck "conf mais novo => regenerou"  '[[ "$(jq -r "[.problems[].short_name]|join(\",\")" <<<"$BODY")" == "A,B" ]]'
rm -f "$C/var/.problems-dirty"
call /contest/problems time01 >/dev/null
sleep 1; printf '{"col#pa":["c"]}' > "$C/problem-langs.json"
call /contest/problems time01
ck "problem-langs novo => regenerou" '[[ "$(jq -r ".problems[]|select(.short_name==\"A\").languages|join(\",\")" <<<"$BODY")" == "c" ]]'

echo "== a versão comprimida do cache =="
callz(){ OUT="$(PATH_INFO=/contest/problems REQUEST_METHOD=GET QUERY_STRING="contest=pc" \
    HTTP_AUTHORIZATION="Bearer $1" HTTP_ACCEPT_ENCODING="gzip, deflate" CONTESTSDIR="$FIX" \
    SESSIONDIR="$SESS" RUNDIR="$FIX/run" MOJ_PROBLEMS_DIR="$PKG" bash "$ROUTER" </dev/null 2>/dev/null)"; }
call /contest/problems time01 >/dev/null      # popula o cache
ck "o .gz foi gravado"            '[[ -s "$C/var/problems-cache.noauthor.json.gz" ]]'
ck "e é gzip de verdade"          'gzip -t "$C/var/problems-cache.noauthor.json.gz" 2>/dev/null'
ck "descomprime no MESMO corpo"   'diff -q <(gzip -dc "$C/var/problems-cache.noauthor.json.gz") "$C/var/problems-cache.noauthor.json" >/dev/null'
callz time01
ck "cliente com gzip: Content-Encoding" '[[ "$OUT" == *"Content-Encoding: gzip"* ]]'
ck "e manda Vary (senão cache burro erra)" '[[ "$OUT" == *"Vary: Accept-Encoding"* ]]'
call /contest/problems time01
ck "cliente SEM gzip: corpo cru"  '[[ "$OUT" != *"Content-Encoding"* && "$(jq -r ".problems|length" <<<"$BODY")" -ge 1 ]]'
ck "o .gz do JUIZ é outro arquivo" 'call /contest/problems pc.judge >/dev/null; [[ -s "$C/var/problems-cache.author.json.gz" ]] && ! diff -q "$C/var/problems-cache.author.json.gz" "$C/var/problems-cache.noauthor.json.gz" >/dev/null'
ck "e o .gz do competidor não tem autor" '! gzip -dc "$C/var/problems-cache.noauthor.json.gz" | grep -q "Bruno Ribas"'

echo "== o cache NÃO serve quem não pode ver problema =="
# antes do início a lista é vazia + locked (o cache não pode servir a lista cheia p/ ele)
sed -i "s/^CONTEST_START=.*/CONTEST_START=$(( $(date +%s) + 3600 ))/" "$C/conf"
call /contest/problems time01
ck "antes do início: lista vazia"  '[[ "$(jq -r ".problems|length" <<<"$BODY")" == 0 ]]'
ck "e diz o motivo (locked)"       '[[ "$(jq -r .locked <<<"$BODY")" == not_started ]]'

echo "== o TL vem do ÍNDICE, não de reabrir o pacote =="
# quem conhece o problema é a gestão de problemas, e ela já carimba o tl_checksum no índice —
# a mesma comparação de dois checksums materializados que o /problems/status faz. Reabrir o
# pacote aqui custava 112,8 MB lidos por regeração, só p/ mostrar tempo-limite na tela.
T_VAR="$FIX/treino/var"; mkdir -p "$T_VAR" "$FIX/run/tl"
sed -i "s/^CONTEST_START=.*/CONTEST_START=$T0/" "$C/conf"
printf '{"checksum":"deadbeef","hosts":{"j1":{"tl":{"c":"1.5","py":"4.0"},"at":1}}}' > "$FIX/run/tl/col#pa.json"
mkidx(){ jq -cn --arg c "$1" '{problems:[{id:"col#pa", tl_checksum:$c}]}' > "$T_VAR/problem-owners.json"; }
mkidx deadbeef
rm -f "$C/var/problems-cache."* "$FIX/run/tl/col#pa.cks"
call /contest/problems time01
ck "TL do store aparece"          '[[ "$(jq -r ".problems[]|select(.short_name==\"A\").time_limits.c" <<<"$BODY")" == 1.5 ]]'
# o sidecar do hash só nasce quando alguém REABRE o pacote — com o índice respondendo, ninguém
# reabre. (O col#pb, que não está no índice de mentira, cai no caminho lento de propósito.)
ck "e sem reabrir o pacote"       '[[ ! -e "$FIX/run/tl/col#pa.cks" ]]'
# índice com checksum DIFERENTE = pacote mudou desde a calibração: o TL velho NÃO pode ser servido
sleep 1; mkidx outrocoisa; rm -f "$C/var/problems-cache."*
call /contest/problems time01
ck "checksum divergente => sem TL" '[[ "$(jq -r ".problems[]|select(.short_name==\"A\").time_limits|length" <<<"$BODY")" == 0 ]]'
sleep 1; mkidx deadbeef; rm -f "$C/var/problems-cache."*
call /contest/problems time01
ck "volta a bater => TL de novo"  '[[ "$(jq -r ".problems[]|select(.short_name==\"A\").time_limits.py" <<<"$BODY")" == 4.0 ]]'

echo "== o checksum do pacote é MEMOIZADO (era 112 MB de teste hasheados por regeração) =="
# o tl-checksum.sh LÊ o conteúdo de tests/*; sem cache, cada regeração do /contest/problems
# re-hasheava o pacote inteiro — 1,3 s em 14 problemas, medido em produção
mkdir -p "$PKG/col/pa/tests/input" "$PKG/col/pa/sols/good"
printf '1 2\n' > "$PKG/col/pa/tests/input/01"; printf 'int main(){}\n' > "$PKG/col/pa/sols/good/a.c"
printf 'TIMELIMIT=1\n' > "$PKG/col/pa/conf"
export RUNDIR="$FIX/run"; mkdir -p "$RUNDIR/tl"
( export MOJ_PROBLEMS_DIR="$PKG" MOJTOOLS_DIR="$(cd "$ROOT/../../mojtools" 2>/dev/null && pwd)"
  export TL_STORE_DIR="$RUNDIR/tl" CONTESTSDIR="$FIX"
  source "$ROOT/api/v1/lib/problems.sh" 2>/dev/null; source "$ROOT/api/v1/lib/tl-store.sh" 2>/dev/null
  A="$(pkg_tl_checksum "$PKG/col/pa" 'col#pa')"
  B="$(pkg_tl_checksum "$PKG/col/pa" 'col#pa')"
  printf '%s\n%s\n' "$A" "$B" > "$FIX/cks.txt" )
CK1="$(sed -n 1p "$FIX/cks.txt")"; CK2="$(sed -n 2p "$FIX/cks.txt")"
ck "o checksum sai"               '[[ -n "$CK1" && "$CK1" =~ ^[0-9a-f]+$ ]]'
ck "2ª chamada dá o MESMO"        '[[ "$CK1" == "$CK2" ]]'
ck "e gravou o sidecar"           '[[ -s "$FIX/run/tl/col#pa.cks" ]]'
ck "o sidecar é <assinatura>TAB<checksum>" 'grep -qP "^[0-9]+\.[0-9]+\t[0-9a-f]+$" "$FIX/run/tl/col#pa.cks"'
# mudar o TESTE tem de invalidar (senão o TL velho seria servido para sempre)
sleep 1; printf '9 9\n' > "$PKG/col/pa/tests/input/01"
( export MOJ_PROBLEMS_DIR="$PKG" MOJTOOLS_DIR="$(cd "$ROOT/../../mojtools" 2>/dev/null && pwd)"
  export TL_STORE_DIR="$RUNDIR/tl" CONTESTSDIR="$FIX"
  source "$ROOT/api/v1/lib/problems.sh" 2>/dev/null; source "$ROOT/api/v1/lib/tl-store.sh" 2>/dev/null
  pkg_tl_checksum "$PKG/col/pa" 'col#pa' > "$FIX/cks2.txt" )
ck "teste novo => checksum novo"  '[[ "$(cat "$FIX/cks2.txt")" != "$CK1" ]]'

echo "== o cache velho é SERVIDO enquanto outro regenera (anti-estampida) =="
# a seção anterior empurrou o início p/ o futuro (teste do `locked`): desfaz
sed -i "s/^CONTEST_START=.*/CONTEST_START=$T0/" "$C/conf"
rm -f "$C/var/.problems-dirty" "$C/var/problems-cache."*
call /contest/problems time01 >/dev/null           # popula
OLD="$(cat "$C/var/problems-cache.noauthor.json")"
sleep 1; printf 'PROBS=( x col#pa OUTRONOME A col#pa )\n' >> "$C/conf"   # invalida
# alguém já está regenerando: segura o lock por fora
mkdir -p "$C/var"; exec 8>>"$C/var/.problems.lock"; flock -n 8
call /contest/problems time01
ck "serve o cache VELHO, sem travar" '[[ "$(jq -r ".problems[0].full_name" <<<"$BODY")" != OUTRONOME ]]'
ck "e não reescreveu o arquivo"      '[[ "$(cat "$C/var/problems-cache.noauthor.json")" == "$OLD" ]]'
exec 8>&-                                            # solta o lock
call /contest/problems time01
ck "solto o lock, regenera"          '[[ "$(jq -r ".problems[0].full_name" <<<"$BODY")" == OUTRONOME ]]'

echo "== prazo vencido: serve na hora e regenera DESTACADO (ninguém espera) =="
# a distinção que importa: ENTRADA mudou (admin renomeou) => regenera na hora, o time vê já;
# só o TETO DE IDADE venceu => nada que importe mudou, serve o que tem e refaz por fora.
# ⚠ NÃO envelheça o cache com `touch -d`: isso deixa as ENTRADAS mais novas que ele e o
# handler cai — corretamente — no caminho SÍNCRONO. O cenário de verdade é o contrário: o cache
# é o arquivo mais novo de todos e só o TETO DE IDADE venceu. Reproduz-se com um teto curto.
rm -f "$C/var/problems-cache."* "$C/var/.problems-dirty"
PROBLEMS_CACHE_TTL=1 call /contest/problems time01 >/dev/null
SNAP="$(cat "$C/var/problems-cache.noauthor.json")"; M0="$(stat -c %Y "$C/var/problems-cache.noauthor.json")"
sleep 2                                   # só o prazo vence; nenhuma entrada mudou
# PROVA DE QUE O PAI NÃO ESPERA: com o lock segurado por fora, o filho destacado não consegue
# regenerar e desiste. Se o caminho fosse síncrono, o pai é que ficaria preso no `flock -w`.
exec 7>>"$C/var/.problems.lock"; flock -n 7
T_ANTES=$(date +%s%N)
PROBLEMS_CACHE_TTL=1 call /contest/problems time01
T_MS=$(( ($(date +%s%N) - T_ANTES) / 1000000 ))
ck "responde o cache que tem"         '[[ "$BODY" == "$SNAP" ]]'
ck "sem esperar (< 1 s, e o lock está preso)" '[[ '"$T_MS"' -lt 1000 ]]'
sleep 1
ck "o filho desistiu do lock"         '[[ "$(stat -c %Y "$C/var/problems-cache.noauthor.json")" == "$M0" ]]'
exec 7>&-                                  # solta: agora o filho consegue
RGOK=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  PROBLEMS_CACHE_TTL=1 call /contest/problems time01 >/dev/null
  [[ "$(stat -c %Y "$C/var/problems-cache.noauthor.json")" != "$M0" ]] && { RGOK=1; break; }; sleep 0.5
done
ck "com o lock livre, regenera"       '[[ "$RGOK" == 1 ]]'
ck "e o corpo continua íntegro"       'jq -e ".problems|length >= 1" "$C/var/problems-cache.noauthor.json" >/dev/null'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
