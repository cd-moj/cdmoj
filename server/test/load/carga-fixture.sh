#!/bin/bash
# carga-fixture.sh <contest> [n_times=2000] [n_staff=550] — o PALCO do teste de carga realista.
#
# Fabrica, num contest **DEMO=1** já criado, o estado que existiria no meio de uma prova:
# N times com account (sede em `.team.region`, 40 sedes), history plausível, metrics e placar;
# M staff `sNNN.staff` com escopo `region:` no staff-filters. NÃO pré-materializa balões: eles
# nascem ORGANICAMENTE pelo carga-injetor.sh durante o teste (aprendido em 27/08/2026 — o
# pré-reconcile de milhares levava 30+ min e um backlog instantâneo gigante não é realista).
#
# RODA DENTRO DO CONTAINER da API (podman exec systemd-moj-api), depois de `podman cp` deste
# arquivo p/ /tmp de lá. Ver TESTE-CARGA.md, passo 2. Idempotente: conta que já existe é pulada.
#
# ⚠ ARMADILHAS PAGAS (não remova):
#   - `set +o noglob` DEPOIS de sourcear common.sh (ele liga noglob; sem isto todo glob vira
#     literal e laços de eq-*/ rodam UMA vez em cima de lixo — mordeu DUAS vezes em 27/08);
#   - metrics em PARALELO (xargs -P12): 10k contas seriais = 4+ min; paralelo = ~30 s;
#   - o /tmp do container MORRE em todo `make deploy` — reenviar os scripts após deploy.
set -u
# APIDIR/CARGA_TMP: defaults de PRODUÇÃO (container) — a BANCADA local (bancada.sh) os
# aponta p/ o checkout e um workdir próprio; nenhum call-site de produção muda.
export CONTESTSDIR="${CONTESTSDIR:-/data/contests}" RUNDIR="${RUNDIR:-/data/run}"
: "${APIDIR:=/opt/moj/cdmoj/server/api/v1}"
: "${CARGA_TMP:=/tmp}"
cd "$APIDIR"
source lib/common.sh 2>/dev/null; source lib/verdict.sh; source lib/users.sh
set +o noglob; shopt -s nullglob

C="${1:?uso: carga-fixture.sh <contest-DEMO> [n_times] [n_staff]}"
NT="${2:-2000}"; NS="${3:-550}"
CD="$CONTESTSDIR/$C"
[[ -f "$CD/conf" ]] || { echo "sem conf em $CD"; exit 1; }
grep -q '^DEMO=1' "$CD/conf" || { echo "ABORTO: $C não é DEMO=1 — fixture nunca roda em prova real"; exit 1; }
T0=$EPOCHSECONDS

mapfile -t CANON < <(bash -c 'set +u; source "'"$CD"'/conf" 2>/dev/null; for ((i=4;i<${#PROBS[@]};i+=5)); do echo "${PROBS[$i]}"; done')
NP=${#CANON[@]}; (( NP > 0 )) || { echo "conf sem PROBS"; exit 1; }
START=$(( $(sed -n 's/^CONTEST_START=//p' "$CD/conf" | tr -cd 0-9) ))
NOW=$EPOCHSECONDS; SPAN=$(( NOW - START - 300 )); (( SPAN > 0 )) || SPAN=3600
echo "== $C: $NT times + $NS staff sobre $NP problemas =="

# plano inteiro num awk (determinístico, srand fixo); o bash só materializa
awk -v n="$NT" -v np="$NP" -v start="$START" -v span="$SPAN" 'BEGIN{
  srand(42)
  for (t=1; t<=n; t++) {
    printf "A\teq-%04d\tSede %02d\n", t, (t%40)+1
    ns=int(rand()*5)                        # 0..4 submissões; AC ~25% (backlog de AC realista)
    for (s=0; s<ns; s++) {
      p=int(rand()*np); ep=start+300+int(rand()*span)
      v=(rand()<0.25) ? "Accepted,100p" : ((rand()<0.5) ? "Wrong Answer" : "Time Limit Exceeded")
      printf "H\teq-%04d\t%d\t%d\t%s\t%08d%04d\n", t, p, ep, v, t, s
    }
  }
}' > "$CARGA_TMP/carga-plan.tsv"
i=0
while IFS=$'\t' read -r k a b c d e; do
  case "$k" in
    A) [[ -f "$CD/users/$a/account.json" ]] && continue
       user_create "$C" "$a" "Equipe $a" "x$RANDOM" >/dev/null 2>&1
       account_merge "$C" "$a" '.team={univ_short:"UTC", region:$r, flag:"br-pr"}' --arg r "$b" >/dev/null 2>&1
       i=$((i+1)); (( i % 1000 == 0 )) && echo "  $i contas…" ;;
    H) [[ -s "$CD/users/$a/history" ]] || printf '%s:%s:C:%s:%s:%s\n' "$c" "${CANON[$b]}" "$d" "$c" "$e" >> "$CD/users/$a/history" ;;
  esac
done < "$CARGA_TMP/carga-plan.tsv"
echo "  contas novas: $i"

echo "== metrics (12 workers em paralelo)…"
find "$CD/users" -mindepth 2 -maxdepth 2 -name history -printf '%h\n' \
  | xargs -P 12 -n 100 bash -c '
      export CONTESTSDIR="'"$CONTESTSDIR"'"
      cd "'"$APIDIR"'"
      source lib/common.sh 2>/dev/null; source lib/verdict.sh; source lib/users.sh
      for d; do metrics_recompute "'"$C"'" "${d##*/}"; done' _
touch "$CD/var/.metrics-stamp"

echo "== $NS staff com escopo de sede…"
for s in $(seq 1 "$NS"); do
  L="$(printf 's%03d.staff' "$s")"
  [[ -f "$CD/users/$L/account.json" ]] || user_create "$C" "$L" "Staff $s" "x$RANDOM" >/dev/null 2>&1
done
mkdir -p "$CD/print-requests"
seq 1 "$NS" | awk '{ printf "%s\"s%03d.staff\": [\"region:Sede %02d\"]", (NR>1?",":""), $1, ($1%40)+1 }' \
  | awk '{ print "{" $0 "}" }' > "$CD/print-requests/staff-filters.json"
jq -e . "$CD/print-requests/staff-filters.json" >/dev/null || { echo "filters inválido"; exit 1; }
rm -f "$CD/print-requests/.staff-exists" "$CD/print-requests/.scope-cache/"* 2>/dev/null

echo "== placar…"
bash "$APIDIR/../../score/build.sh" "$C" >/dev/null 2>&1
wc -c "$CD/var/placar.txt"
echo "fixture pronta em $(( EPOCHSECONDS - T0 ))s — agora: carga-sessoes.sh $C"
