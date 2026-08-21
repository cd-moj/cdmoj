#!/bin/bash
# Cache preguiçoso de placar e estatísticas (regenera só quando a fonte muda; gera
# na hora se nada existe) + arquivo completo de contests encerrados (/index/contests?all=1).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; SPOOL="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$SPOOL"' EXIT
# o que se testa aqui é o GATILHO (.score-dirty/conf), não o piso anti-estampida de produção
# (SCORE_SERVE_FLOOR_S=8 faria o handler nem tentar regen com placar mais novo que 8s)
export SCORE_SERVE_FLOOR_S=0
source "$(dirname "$(readlink -f "$0")")/fixture.sh"

# --- contest (store por-usuário) com history mas SEM placar ---
C="$FIX/lazy"; mkdir -p "$C/var"
{ printf 'CONTEST_ID=lazy\nCONTEST_TYPE=icpc\nCONTEST_NAME=Lazy\nCONTEST_START=1000\nCONTEST_END=2000\n'
  printf 'USER_STORE=v2\n'
  printf "PROBS=(f0 p/um Um A k0 f1 p/dois Dois B k1)\n"; } > "$C/conf"
fx_user "$C" lazy.admin p Admin
fx_user "$C" alice a          # sem nome => fullname = login (o placar espera "alice")
fx_user "$C" bob   b
printf '5:p#um:C:Accepted,100p:1718000000:h1\n' > "$C/users/alice/history"
{ printf '3:p#um:CPP:Wrong Answer:1718000010:h2\n'
  printf '2:p#dois:PY:Accepted,100p:1718000020:h3\n'; } > "$C/users/bob/history"
printf 'CONTEST=lazy\nLOGIN=lazy.admin\nLOGINAT=1\n' > "$SESS/adm"

# 22 contests encerrados extras p/ provar a paginação/arquivo (>20)
for i in $(seq -w 1 22); do d="$FIX/zz$i"; mkdir -p "$d"
  printf 'CONTEST_ID=zz%s\nCONTEST_NAME=Closed %s\nCONTEST_START=1000\nCONTEST_END=2000\n' "$i" "$i" > "$d/conf"; done

# ⚠ RUNDIR no fixture: sem ele o handler cai no default do common.conf e o teste ESCREVE no
# run/ de verdade (o cache do /index/contests vive lá). Foi o que aconteceu ao criar este bloco.
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-adm}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" SPOOLDIR="$SPOOL" SCOREDIR="$ROOT/score" RUNDIR="$FIX/run" \
    bash "$ROUTER" <<<"${3:-}" 2>&1)"; \
    BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:160}"; ((fail++)); fi; }
mt(){ stat -c %Y "$1" 2>/dev/null || echo 0; }

echo "== placar: geração preguiçosa =="
placar="$C/var/placar.txt"
ck "placar não existe antes" '[[ ! -f "$placar" ]]'
call /contest/score GET '' '' 'contest=lazy'
ck "score 200" '[[ "$OUT" == *"Status: 200"* ]]'
ck "1ª linha = modo icpc" '[[ "$(head -1 <<<"$BODY")" == icpc ]]'
ck "placar foi gerado na hora" '[[ -s "$placar" ]]'
ck "tem ao menos uma linha de equipe (alice)" '[[ "$BODY" == *alice* ]]'

echo "== placar: cache estável e invalidação =="
T1="$(mt "$placar")"; sleep 1; call /contest/score GET '' '' 'contest=lazy'; T2="$(mt "$placar")"
ck "2ª chamada NÃO regerou (cache)" '[[ "$T1" == "$T2" ]]'
sleep 1; touch "$C/var/.score-dirty"; call /contest/score GET '' '' 'contest=lazy'; T3="$(mt "$placar")"
ck "history mudou (.score-dirty) -> placar regerado" '[[ "$T3" != "$T2" ]]'

echo "== estatísticas: cache preguiçoso =="
cache="$C/var/statistics.cache.json"
ck "cache de stats não existe antes" '[[ ! -f "$cache" ]]'
call /contest/statistics GET '' adm 'contest=lazy'
ck "stats 200" '[[ "$OUT" == *"Status: 200"* ]]'
ck "cache de stats criado" '[[ -s "$cache" ]]'
ck "stats: users=2 (privilegiado fora), problema A letra=A" '[[ "$(jq -r .totals.users <<<"$BODY")" == 2 && "$(jq -r ".problems[0].short_name" <<<"$BODY")" == A ]]'
S1="$(mt "$cache")"; sleep 1; call /contest/statistics GET '' adm 'contest=lazy'; S2="$(mt "$cache")"
ck "2ª chamada serviu do cache" '[[ "$S1" == "$S2" ]]'
sleep 1; touch "$C/var/.score-dirty"; call /contest/statistics GET '' adm 'contest=lazy'; S3="$(mt "$cache")"
ck "history mudou (.score-dirty) -> cache regerado" '[[ "$S3" != "$S2" ]]'

echo "== arquivo de encerrados: /index/contests?all=1 =="
call /index/contests GET '' '' ''
TOTAL="$(jq -r .closed.total <<<"$BODY")"
ck "default pagina em 20 (per_page)" '[[ "$(jq -r .closed.per_page <<<"$BODY")" == 20 ]]'
ck "há mais de 20 encerrados no fixture" '[[ "$TOTAL" -gt 20 ]]'
ck "default devolve só 20 itens" '[[ "$(jq -r ".closed.items|length" <<<"$BODY")" == 20 ]]'
call /index/contests GET '' '' 'all=1'
ck "all=1 devolve TODOS (items==total)" '[[ "$(jq -r ".closed.items|length" <<<"$BODY")" == "$(jq -r .closed.total <<<"$BODY")" ]]'

echo "== /index/contests: o TSV é cacheado, e o cache NÃO congela o relógio =="
# O laço que lê os 1482 conf custava 1.455 ms — era a rota INTEIRA (2,2 s), na página inicial,
# a cada visita. O TSV virou cache invalidado por EVENTO (conf mais novo / contest criado), e
# p/ isso teve de ficar independente da hora: quem classifica aberto/por vir/encerrado é o jq.
# É essa independência que este bloco prova — sem ela, cache e relógio brigam em silêncio.
TSVC="$FIX/run/index-contests.tsv"
call /index/contests GET '' '' ''
ck "o cache do TSV foi gravado"       '[[ -s "$TSVC" ]]'
M0="$(mt "$TSVC")"
sleep 1; call /index/contests GET '' '' ''
ck "2ª chamada NÃO refaz a varredura"  '[[ "$(mt "$TSVC")" == "$M0" ]]'

# contest que COMEÇA daqui a 2s: o cache nasce com ele "por vir" e, sem tocar em nada,
# a resposta tem de virar "aberto" sozinha
FUT="$FIX/vira"; mkdir -p "$FUT/var"
NOW=$(date +%s)
printf 'CONTEST_ID=vira
CONTEST_TYPE=icpc
CONTEST_NAME=Vira
CONTEST_START=%s
CONTEST_END=%s
PROBS=( x c#a A A c#a )
'   "$(( NOW + 2 ))" "$(( NOW + 9999 ))" > "$FUT/conf"
call /index/contests GET '' '' ''
ck "nasce em 'por vir'"                '[[ "$(jq -r "[.upcoming[].id]|index(\"vira\")" <<<"$BODY")" != null ]]'
ck "e sem revelar nº de problemas"     '[[ "$(jq -r ".upcoming[]|select(.id==\"vira\").problems_count" <<<"$BODY")" == 0 ]]'
M1="$(mt "$TSVC")"
sleep 3                                   # só o RELÓGIO anda; nenhum conf muda
call /index/contests GET '' '' ''
ck "vira 'aberto' sozinho"             '[[ "$(jq -r "[.open[].id]|index(\"vira\")" <<<"$BODY")" != null ]]'
ck "aí sim mostra o nº de problemas"   '[[ "$(jq -r ".open[]|select(.id==\"vira\").problems_count" <<<"$BODY")" == 1 ]]'
ck "e NÃO refez a varredura p/ isso"   '[[ "$(mt "$TSVC")" == "$M1" ]]'

# invalidação por EVENTO: editar um conf refaz; a resposta acompanha
sleep 1; sed -i 's/^CONTEST_NAME=.*/CONTEST_NAME=ViraRenomeado/' "$FUT/conf"
call /index/contests GET '' '' ''
ck "conf editado => varredura refeita" '[[ "$(mt "$TSVC")" != "$M1" ]]'
ck "e o nome novo aparece"             '[[ "$(jq -r ".open[]|select(.id==\"vira\").title" <<<"$BODY")" == ViraRenomeado ]]'
M2="$(mt "$TSVC")"
sleep 1; mkdir -p "$FIX/novo/var"
printf 'CONTEST_ID=novo
CONTEST_TYPE=icpc
CONTEST_NAME=Novo
CONTEST_START=1
CONTEST_END=2
PROBS=()
' > "$FIX/novo/conf"
# `all=1` de propósito: `novo` começa em 1 (o mais antigo) e cai na ÚLTIMA página do arquivo
call /index/contests GET '' '' 'all=1'
ck "contest NOVO também invalida"      '[[ "$(mt "$TSVC")" != "$M2" ]] && [[ "$(jq -r "[.closed.items[].id]|index(\"novo\")" <<<"$BODY")" != null ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
