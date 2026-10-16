#!/bin/bash
# ensaio-fixture.sh <contest> [n_times=800] [n_sedes=20] — o PALCO do ENSAIO DE ESCRITA (15/10/2026, véspera da
# Maratona de 8/11: ~800 times, 20 sedes com um .staff cada). Diferente do teste de carga de 27/08 (TESTE-CARGA.md,
# só LEITURA), aqui as ESCRITAS são o teste: submissão real (/submit) → spool → judged (shards) → fila → JUÍZES REAIS
# → /judge/result → history/metrics → placar e balões. Por isso o palco nasce VAZIO (sem history pré-fabricado).
#
# O que cria (idempotente; recusa se o contest já existir e não for DEMO):
#   • contest DEMO=1 + SECRET=1 (fora da home), dono `ribas.admin` — o problema trivial `ribas.admin#teste-juiz`
#     (A+B, 4 testes de milissegundos) é privado dele; prioridade `lista-publica` = a banda MAIS BAIXA do escalonador
#     (SCHED_BANDS: super › prova › lista-privada › rejulgar › lista-publica — `lista-privada` furaria a fila das listas
#     e do treino reais); na mesma banda, ordem de chegada com os usuários. Início há 1 min, fim em +6 h;
#   • N times `eNNtMMM` (sede NN, time MMM) com `.team.region` = "Sede NN"; regions.json por regex do login;
#   • um `eNN.staff` por sede com escopo `region:Sede NN` (staff-filters) — a fila de impressão/balões de cada sede;
#   • módulos sedes + baloes (o balão nasce no 1º AC: é escrita também);
#   • uma sessão por conta, prefixo `ze` (limpeza por glob) → /tmp/ensaio-tokens-{times,staff}.txt.
# O contest é criado pelo ENDPOINT oficial (/treino/contest-create/create) com uma sessão TEMPORÁRIA do ribas.admin,
# apagada no fim — o mesmo caminho (problems_denied_for, owner) de quem cria pela web.
#
# RODA DENTRO DO CONTAINER da API (podman exec -i systemd-moj-api bash -s <contest> … < ensaio-fixture.sh); local
# (ensaio a seco) com APIDIR/CONTESTSDIR/RUNDIR/ENSAIO_TMP apontados p/ a fixture.
set -u
export CONTESTSDIR="${CONTESTSDIR:-/data/contests}" RUNDIR="${RUNDIR:-/data/run}"
: "${APIDIR:=/opt/moj/cdmoj/server/api/v1}"
: "${ENSAIO_TMP:=/tmp}"
: "${ENSAIO_OWNER:=ribas.admin}"
: "${ENSAIO_PROBLEM:=ribas.admin#teste-juiz}"
C="${1:?uso: ensaio-fixture.sh <contest zz-…> [n_times] [n_sedes]}"; NT="${2:-800}"; NS="${3:-20}"
[[ "$C" == zz-* ]] || { echo "ABORTO: o contest do ensaio começa com zz- (é o que a limpeza e as guardas conferem)"; exit 1; }
cd "$APIDIR" || exit 1
export _DIR="$APIDIR"; source lib/sources.sh >/dev/null 2>&1 || source lib/common.sh
set +o noglob; shopt -s nullglob
CD="$CONTESTSDIR/$C"
SESSIONDIR="${SESSIONDIR:-$RUNDIR/sessions}"

call(){ # <path> <method> <body> <token> → corpo
  PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="" HTTP_AUTHORIZATION="Bearer $4" \
    bash "$APIDIR/router.sh" <<<"$3" 2>/dev/null | awk 'f{print} /^\r?$/{f=1}'; }

# ---- 1. o contest (pelo endpoint, como o dono) ------------------------------------------------------------------
if [[ -d "$CD" ]]; then
  grep -q '^DEMO=1' "$CD/conf" || { echo "ABORTO: $C existe e NÃO é DEMO"; exit 1; }
  echo "contest $C já existe (DEMO) — reaproveitando"
else
  ttok="zeowner$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
  printf 'CONTEST=treino\nLOGIN=%q\nUSERFULLNAME=ensaio\nLOGINAT=%s\n' "$ENSAIO_OWNER" "$EPOCHSECONDS" > "$SESSIONDIR/$ttok"
  NOW="$EPOCHSECONDS"
  spec="$(jq -cn --arg id "$C" --arg p "$ENSAIO_PROBLEM" --argjson s "$((NOW - 60))" --argjson e "$((NOW + 6*3600))" \
    '{id:$id, name:"Ensaio de escrita (teste)", mode:"icpc", priority:"lista-publica", secret:true, demo:true,
      start:$s, end:$e, languages:["c","cpp","java","py"],
      admin:{login:"zzensaio.admin", password:"ensaio-'"$RANDOM$RANDOM"'"},
      problems:[{bank_id:$p, name:"Soma", letter:"A"}]}')"
  r="$(call /treino/contest-create/create POST "$spec" "$ttok")"
  rm -f "$SESSIONDIR/$ttok"
  [[ "$(jq -r '.success // false' <<<"$r")" == true ]] || { echo "ABORTO: criação falhou: ${r:0:300}"; exit 1; }
  echo "contest criado: $(jq -c '{contest_id, admin_login, modules_skipped}' <<<"$r")"
fi
grep -q '^DEMO=1' "$CD/conf" || { echo "ABORTO: sem DEMO=1"; exit 1; }

# ---- 2. sedes, times e staff ------------------------------------------------------------------------------------
per=$(( (NT + NS - 1) / NS ))
seq 1 "$NS" | jq -R -s -c 'split("\n") | map(select(length>0) | tonumber)
  | map({name: ("Sede " + (if . < 10 then "0" else "" end) + tostring),
         regex: ("^e" + (if . < 10 then "0" else "" end) + tostring + "t")})' > "$CD/regions.json"
n=0
for (( s=1; s<=NS; s++ )); do
  for (( t=1; t<=per && n<NT; t++ )); do
    L="$(printf 'e%02dt%03d' "$s" "$t")"; n=$((n+1))
    [[ -f "$CD/users/$L/account.json" ]] && continue
    user_create "$C" "$L" "Time $L" "x$RANDOM$RANDOM" >/dev/null 2>&1 || { echo "falhou criar $L"; continue; }
    account_merge "$C" "$L" '.team={univ_short:"ENS", region:$r}' --arg r "$(printf 'Sede %02d' "$s")" >/dev/null 2>&1
  done
  S="$(printf 'e%02d.staff' "$s")"
  [[ -f "$CD/users/$S/account.json" ]] || user_create "$C" "$S" "Staff sede $s" "x$RANDOM$RANDOM" >/dev/null 2>&1
done
mkdir -p "$CD/print-requests"
seq 1 "$NS" | awk '{ printf "%s\"e%02d.staff\": [\"region:Sede %02d\"]", (NR>1?",":""), $1, $1 }' \
  | awk '{ print "{" $0 "}" }' > "$CD/print-requests/staff-filters.json"
jq -e . "$CD/print-requests/staff-filters.json" >/dev/null || { echo "staff-filters inválido"; exit 1; }
rm -f "$CD/print-requests/.staff-exists" "$CD/print-requests/.scope-cache/"* 2>/dev/null
declare -F mod_enable >/dev/null && mod_enable "$C" sedes baloes >/dev/null 2>&1
mkdir -p "$CD/var"; touch "$CD/var/.score-dirty"
echo "times: $(find "$CD/users" -mindepth 1 -maxdepth 1 -name 'e[0-9][0-9]t[0-9]*' | wc -l) · staff: $(find "$CD/users" -mindepth 1 -maxdepth 1 -name 'e*.staff' | wc -l) · sedes: $NS"

# ---- 3. sessões (prefixo ze; recria) ----------------------------------------------------------------------------
rm -f "$SESSIONDIR"/ze[0-9a-f]*
: > "$ENSAIO_TMP/ensaio-tokens-times.txt"; : > "$ENSAIO_TMP/ensaio-tokens-staff.txt"
mk(){ local tok="ze$(od -An -N15 -tx1 /dev/urandom | tr -d ' \n')"
  printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' "$C" "$1" "$1" "$EPOCHSECONDS" > "$SESSIONDIR/$tok"
  printf '%s\t%s\n' "$tok" "$1" >> "$2"; }
for d in "$CD"/users/e[0-9][0-9]t[0-9]*/; do u="${d%/}"; mk "${u##*/}" "$ENSAIO_TMP/ensaio-tokens-times.txt"; done
for d in "$CD"/users/e[0-9][0-9].staff/; do u="${d%/}"; mk "${u##*/}" "$ENSAIO_TMP/ensaio-tokens-staff.txt"; done
wc -l "$ENSAIO_TMP/ensaio-tokens-times.txt" "$ENSAIO_TMP/ensaio-tokens-staff.txt"
grep -E '^(DEMO|SECRET|CONTEST_PRIORITY|CONTEST_MODULES|LANGUAGES)=' "$CD/conf"
