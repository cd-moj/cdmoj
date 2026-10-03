#!/usr/bin/env bash
# warm-judges.sh <contest> [quem]
# "🔥 Aquecer juízes" fora do clique (TCP 2026, 03/10/2026: o organizador não achava o botão, que só existia num
# item da Central, e a oficial começou com juízes frios). Manda um `calibrate` DIRIGIDO a cada par juiz×problema
# FRIO — o MESMO núcleo da rota POST /contest/admin/warm-judges (jw_warm, lib/judge-warm.sh). Quem chama:
#   · a promoção de rodada (handlers/contest/admin/rounds.sh), DESTACADO — a promoção nunca espera nem falha
#     por causa do aquecimento; `quem` = promote:<login>;
#   · o judged (prestart_warm_sweep), ~15 min antes do CONTEST_START; `quem` = auto-inicio.
# Idempotente: par quente ou já aquecendo não recebe nada. Vai ao audit do contest (warm-judges).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_DIR="$HERE/../api/v1"; _LIBDIR="$_DIR/lib"
source "$_DIR/lib/common.sh"
source "$HERE/../judge-gw/sched-lib.sh"; source "$_DIR/lib/tl-store.sh"; source "$_DIR/lib/judge-warm.sh"
c="${1:-}"; by="${2:-auto}"; SESSION_LOGIN="$by"   # autor no audit
valid_id "$c" && [[ -f "$CONTESTSDIR/$c/conf" ]] || { echo "uso: warm-judges.sh <contest> [quem]" >&2; exit 1; }
CONTEST_JUDGES=""; PROBS=()
load_contest_conf "$c"
out="$(mktemp)"; trap 'rm -f "$out"' EXIT
counts="$(jw_warm "$c" "$by" "$out")"; rc=$?
(( rc == 2 )) && { echo "$c: outro aquecimento em andamento" >&2; exit 0; }
(( rc == 0 )) && [[ -n "$counts" ]] || { echo "$c: falha ao montar o mapa de juízes" >&2; exit 1; }
n="$(grep -c . "$out" 2>/dev/null)"; n="${n//[^0-9]/}"; n="${n:-0}"
audit_log_to "$c" warm-judges "sent=$n by=$by $(jq -r '"cold=\(.cold) warming=\(.warming) warm=\(.warm)"' <<<"$counts")"
echo "$c: $n calibração(ões) enviada(s) — antes: $(jq -r '"\(.warm) quente(s), \(.warming) aquecendo, \(.cold) frio(s)"' <<<"$counts")"
