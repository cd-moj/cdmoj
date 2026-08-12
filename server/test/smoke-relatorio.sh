#!/bin/bash
# Smoke do relatório periódico de submissões (mojinho → grupo): POST /ops/relatorio
# (gate por telegram_id → conta .admin do treino), gerador score/relatorio-gen.sh,
# agendador de quartis no GET /ops/alerts e o item de outbox "só grupo" (alert_group).
#
# Os totais esperados são CALCULADOS aqui com as mesmas regras de janela do gerador
# (o teste roda em qualquer época do ano — nada de contagem hardcoded dependente da data).
set -u
export TZ="${MOJ_TZ:-America/Sao_Paulo}"
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"   # .../server
ROUTER="$ROOT/api/v1/router.sh"

FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; SPOOL="$(mktemp -d)"; NEWS="$(mktemp -d)"; RUN="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$SPOOL" "$NEWS" "$RUN"' EXIT
mkdir -p "$RUN"; printf 'mojb_smoketoken' > "$RUN/bot.token"

pass=0; fail=0
check(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; echo "      out: ${OUT:0:400}"; ((fail++)); fi; }
bcall(){ # <path> <method> <auth-header> [body-json]  (BUDGET simula base fria: ver abaixo)
  OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="" \
    HTTP_AUTHORIZATION="$3" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" SPOOLDIR="$SPOOL" NEWSDIR="$NEWS" RUNDIR="$RUN" \
    BOT_TOKEN_FILE="$RUN/bot.token" RELATORIO_SWEEP_THROTTLE=0 REL_SYNC_BUDGET="${BUDGET:-50}" \
    bash "$ROUTER" <<<"${4:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
okstatus(){ [[ "$OUT" == *"Status: 200"* ]]; }
html(){ printf '%s' "$BODY" | jq -r '.html // empty'; }

# ---------------------------------------------------------------------------
# Fixture: treino + lista1 + lista2, vínculos Telegram, history nas 4 janelas
# ---------------------------------------------------------------------------
source "$(dirname "$(readlink -f "$0")")/fixture.sh"

for c in treino lista1 lista2; do
  mkdir -p "$FIX/$c/var"
  { printf 'CONTEST_ID=%s\n' "$c"
    printf 'CONTEST_NAME="Contest %s"\n' "$c"
    printf 'CONTEST_TYPE=lista-publica\nUSER_STORE=v2\n'; } > "$FIX/$c/conf"
done
fx_user "$FIX/treino" x.admin  a "Admin X"
fx_user "$FIX/treino" bob      b "Bob Aluno"
fx_user "$FIX/lista1" u1       c "User Um"
fx_user "$FIX/lista1" u2       d "User Dois"
fx_user "$FIX/lista2" u3       e "User Tres"
fx_user "$FIX/lista2" y.cstaff f "Staff Y"

# vínculo Telegram: 999 -> x.admin (admin de verdade), 111 -> bob (conta comum)
mkdir -p "$FIX/treino/var/telegram/by-tgid" "$FIX/treino/var/telegram/by-login"
jq -cn '{telegram_id:999, login:"x.admin"}' > "$FIX/treino/var/telegram/by-tgid/999.json"
printf '999\n' > "$FIX/treino/var/telegram/by-login/x.admin"
jq -cn '{telegram_id:111, login:"bob"}' > "$FIX/treino/var/telegram/by-tgid/111.json"
printf '111\n' > "$FIX/treino/var/telegram/by-login/bob"

# semestre: [120 dias atrás, 60 dias à frente] — quartis de 45d: Q1 e Q2 vencidos, agora
# estamos no quartil 3. Datas p/ o comando config:
now="$EPOCHSECONDS"
SEM_INI_D="$(date -d "@$(( now - 120*86400 ))" +%F)"
SEM_FIM_D="$(date -d "@$(( now + 60*86400 ))" +%F)"
sem_ini="$(date -d "$SEM_INI_D 00:00:00" +%s)"

# epochs das submissões (todas a dias de qualquer fronteira):
year_ago(){ date -d "$(date -d "@$1" +'%Y-%m-%d %H:%M:%S') 1 year ago" +%s; }
e_win=$(( now - 10*86400 ))            # dentro da janela do semestre
e_pw="$(year_ago "$e_win")"            # mesma janela, ano anterior
e_jan="$(date -d "$(date -d "@$now" +%Y)-01-15 12:00:00" +%s)"        # YTD deste ano
e_pjan="$(date -d "$(( $(date -d "@$now" +%Y) - 1 ))-01-20 12:00:00" +%s)"  # YTD anterior

H(){ printf '%s:col#p:C:%s:%s:s%s\n' "$1" "${3:-Accepted}" "$1" "${2}$RANDOM"; }
# janela: lista1=3 (u1×2, u2×1), lista2=2 (u3; UMA com verdict contendo ':'), treino=2 (bob)
{ H "$e_win" a; H "$((e_win+60))" b; } >> "$FIX/lista1/users/u1/history"
H "$((e_win+120))" c >> "$FIX/lista1/users/u2/history"
H "$((e_win+180))" d >> "$FIX/lista2/users/u3/history"
H "$((e_win+240))" e 'Accepted,100p. Pontos | 100 |' >> "$FIX/lista2/users/u3/history"
{ H "$((e_win+300))" f; H "$((e_win+360))" g; } >> "$FIX/treino/users/bob/history"
# privilegiados NA janela — não podem contar:
H "$((e_win+420))" h >> "$FIX/treino/users/x.admin/history"
H "$((e_win+480))" i >> "$FIX/lista2/users/y.cstaff/history"
# ano anterior (mesma janela): 2 (bob no treino, u1 na lista1)
H "$e_pw" j >> "$FIX/treino/users/bob/history"
H "$((e_pw+60))" k >> "$FIX/lista1/users/u1/history"
# YTDs
H "$e_jan" l >> "$FIX/treino/users/bob/history"
H "$e_pjan" m >> "$FIX/treino/users/bob/history"

# totais esperados, com as MESMAS regras de janela do gerador:
ALL=( "$e_win" $((e_win+60)) $((e_win+120)) $((e_win+180)) $((e_win+240)) $((e_win+300)) $((e_win+360)) "$e_pw" $((e_pw+60)) "$e_jan" "$e_pjan" )
jan1="$(date -d "$(date -d "@$now" +%Y)-01-01 00:00:00" +%s)"
cnt(){ local lo="$1" hi="$2" e n=0; for e in "${ALL[@]}"; do (( e >= lo && e <= hi )) && n=$((n+1)); done; printf '%s' "$n"; }
WIN=$(cnt "$sem_ini" "$now"); PW=$(cnt "$(year_ago "$sem_ini")" "$(year_ago "$now")"); YTD=$(cnt "$jan1" "$now")

AUTH="Bearer mojb_smoketoken"
J(){ jq -cn --argjson id "$1" --argjson a "${2:-[]}" '{telegram_id:$id, args:$a}'; }

echo "== gate =="
bcall /ops/relatorio POST "Bearer errado" "$(J 999)"
check "sem bot-token -> 401" '[[ "$OUT" == *"Status: 401"* ]]'
bcall /ops/relatorio POST "$AUTH" "$(J 111)"
check "tgid de conta comum -> 403 admin_required" '[[ "$OUT" == *"Status: 403"* && "$OUT" == *admin_required* ]]'
bcall /ops/relatorio POST "$AUTH" '{"args":[]}'
check "sem telegram_id -> 400" '[[ "$OUT" == *"Status: 400"* ]]'
bcall /ops/relatorio POST "$AUTH" "$(J 999)"
check "sem semestre configurado -> 409 not_configured" '[[ "$OUT" == *"Status: 409"* && "$OUT" == *not_configured* ]]'

echo "== config =="
bcall /ops/relatorio POST "$AUTH" "$(J 999 '["config","2026-02-30","2026-07-01"]')"
check "config data inválida (30/fev) -> 422" '[[ "$OUT" == *"Status: 422"* ]]'
bcall /ops/relatorio POST "$AUTH" "$(J 999 "[\"config\",\"$SEM_FIM_D\",\"$SEM_INI_D\"]")"
check "config início>fim -> 422" '[[ "$OUT" == *"Status: 422"* && "$OUT" == *bad_range* ]]'
bcall /ops/relatorio POST "$AUTH" "$(J 999 "[\"config\",\"$SEM_INI_D\",\"$SEM_FIM_D\"]")"
check "config ok -> 200 com quartis" 'okstatus && [[ "$(html)" == *"Q1:"* && "$(html)" == *"Q4:"* ]]'
check "config marca vencidos sem reenvio" '[[ "$(html)" == *"já vencido"* ]]'
CJ="$FIX/treino/var/relatorio.json"
check "relatorio.json gravado; Q1/Q2 pré-marcados (0), Q3 não" \
  '[[ -f "$CJ" ]] && jq -e ".sent[\"1\"]==0 and .sent[\"2\"]==0 and (.sent|has(\"3\")|not) and .configured_by==\"x.admin\"" "$CJ" >/dev/null'

echo "== relatório on-demand =="
bcall /ops/relatorio POST "$AUTH" "$(J 999)"
check "relatorio -> 200" 'okstatus && [[ -n "$(html)" ]]'
check "estamos no quartil 3/4" '[[ "$(html)" == *"quartil <b>3/4</b>"* ]]'
check "painel: treino em linha própria" '[[ "$(html)" == *"treino livre: <b>2</b>"* ]]'
check "painel: total e usuários ativos" '[[ "$(html)" == *"Σ <b>$WIN</b> submissões"* && "$(html)" == *"<b>4</b> usuários ativos"* ]]'
check "painel: comparações (ano anterior / YTD)" '[[ "$(html)" == *"mesmo período de"* && "$(html)" == *"até agora: <b>$YTD</b>"* ]]'
CACHE="$FIX/treino/var/relatorio-cache.json"
check "cache: top ordenado (lista1=3 > lista2=2), treino FORA do top" \
  'jq -e ".window.top[0].contest==\"lista1\" and .window.top[0].count==3 and .window.top[1].contest==\"lista2\" and .window.top[1].count==2 and ([.window.top[].contest]|index(\"treino\")|not)" "$CACHE" >/dev/null'
check "cache: privilegiados excluídos + verdict com ':' conta 1" \
  'jq -e ".window.total=='"$WIN"' and .window.treino==2 and .window.users==4" "$CACHE" >/dev/null'
check "cache: prev_window/ytd" \
  'jq -e ".prev_window.total=='"$PW"' and .ytd.total=='"$YTD"'" "$CACHE" >/dev/null'
check "cache: nome do contest veio do conf" 'jq -e ".window.top[0].name==\"Contest lista1\"" "$CACHE" >/dev/null'

echo "== override de data e erros =="
OVR="$(date -d "@$(( e_win - 86400 ))" +%F)"     # um dia antes das submissões da janela
bcall /ops/relatorio POST "$AUTH" "$(J 999 "[\"$OVR\"]")"
check "override AAAA-MM-DD -> 200 sem rótulo de quartil" 'okstatus && [[ "$(html)" != *quartil* ]]'
bcall /ops/relatorio POST "$AUTH" "$(J 999 '["3000-01-01"]')"
check "data futura -> 400" '[[ "$OUT" == *"Status: 400"* ]]'
bcall /ops/relatorio POST "$AUTH" "$(J 999 '["banana"]')"
check "subcomando desconhecido -> 400" '[[ "$OUT" == *"Status: 400"* && "$OUT" == *bad_args* ]]'

echo "== base fria: orçamento síncrono estourado -> background + retry =="
# orçamento de 1 ms mata o gerador (rc 124) e o handler relança em background devolvendo
# "pending". Data de override nova ⇒ o cache existente (outro since) não serve.
OVR2="$(date -d "@$e_pjan" +%F)"
BUDGET=0.001 bcall /ops/relatorio POST "$AUTH" "$(J 999 "[\"$OVR2\"]")"
check "orçamento estourado -> 200 pending com aviso" \
  'okstatus && (printf "%s" "$BODY" | jq -e ".pending==true" >/dev/null) && [[ "$(html)" == *"segundo plano"* ]]'
ok2=""
for _ in $(seq 1 30); do
  sleep 0.5
  bcall /ops/relatorio POST "$AUTH" "$(J 999 "[\"$OVR2\"]")"
  if printf '%s' "$BODY" | jq -e '.pending != true' >/dev/null 2>&1; then ok2=1; break; fi
done
check "retry após o background -> painel de verdade" \
  '[[ -n "$ok2" ]] && [[ "$(html)" == *"submissões"* ]]'

echo "== status =="
bcall /ops/relatorio POST "$AUTH" "$(J 999 '["status"]')"
check "status -> 200 com quartis e pré-marcados" \
  'okstatus && [[ "$(html)" == *"pré-marcado"* && "$(html)" == *"Q4"* ]]'

echo "== agendador (sweep no /ops/alerts) =="
# config sintética: len=8000s, b1=now-2000 e b2=now vencidos, nada sent ⇒ devido = 2 (o MAIOR)
jq -cn --argjson i "$(( now - 4000 ))" --argjson f "$(( now + 4000 ))" \
   '{inicio:$i, fim:$f, configured_by:"x.admin", configured_at:$i, sent:{}}' > "$CJ"
bcall /ops/alerts GET "$AUTH"
check "quartil vencido -> UM item só-grupo (chats vazio, group:true, loud)" \
  '(printf "%s" "$BODY" | jq -e "[.items[] | select(.text | contains(\"Relatório\"))] | length==1 and (.[0].chats==[]) and (.[0].group==true) and (.[0].loud==true)" >/dev/null)'
check "relatório do quartil 2/4 (o maior vencido; um só, não dois)" \
  '(printf "%s" "$BODY" | jq -e "[.items[].text] | any(contains(\"quartil <b>2/4</b>\"))" >/dev/null)'
check "Q1 e Q2 marcados enviados (epoch, não 0)" \
  'jq -e "(.sent[\"1\"]>0) and (.sent[\"2\"]>0)" "$CJ" >/dev/null'
bcall /ops/alerts GET "$AUTH"
check "poll seguinte: sem repetição" \
  '(printf "%s" "$BODY" | jq -e "[.items[].text // empty] | any(contains(\"Relatório\")) | not" >/dev/null)'

echo "== outbox: DM sem destino continua descartada =="
jq -cn '{text:"dm perdida", chats:[], loud:false, group:false}' > "$RUN/alerts/outbox/1-dm-XXXX.json"
bcall /ops/alerts GET "$AUTH"
check "item chats:[] com group:false não vaza pro grupo" \
  '(printf "%s" "$BODY" | jq -e "[.items[].text // empty] | any(contains(\"dm perdida\")) | not" >/dev/null)'
check "e foi consumido (não trava a fila)" '[[ ! -e "$RUN/alerts/outbox/1-dm-XXXX.json" ]]'

echo ""
echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
