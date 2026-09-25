#!/bin/bash
# smoke-judge-warm.sh — JUIZ QUENTE × FRIO por problema (lib/judge-warm.sh): o item `judges_warm` do
# preflight e o POST /contest/admin/warm-judges (botão "🔥 Aquecer juízes" da Central).
#
# XIV Maratona UnB (25/09/2026): o TL é por máquina e o juiz frio baixa+calibra na 1ª submissão, que
# espera — 7,3 min no super-dash do judge-sp1. O preflight dizia OK porque UM juiz tinha o problema.
# Prende, juiz a juiz:
#   · QUENTE = run/tl/<id>.json com o host na versão do run/tl/<id>.pkv; versão velha = FRIO; sem
#     run/tl = FRIO; run/tl ilegível = FRIO (e não derruba os outros); tl_checksum do índice divergente
#     do run/tl = pacote mudou ⇒ FRIO em todos;
#   · só juiz ONLINE e não DESABILITADO entra; pool por problema (problem-judges.json) restringe;
#   · `calibrate` na fila = AQUECENDO (não é pedido de novo);
#   · o POST manda calibrate dirigido SÓ aos frios; o 2º POST não manda nada; competidor = 403;
#   · o item é bilíngue (label_en/detail_en) e traz action warm_judges enquanto há frio;
#   · nenhuma das rotas abre o pacote (MOJ_PROBLEMS_DIR aponta p/ um diretório que não existe).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" MOJ_PROBLEMS_DIR="$RUN/nao-existe" TL_STORE_DIR="$RUN/tl"
C="$FIX/pv"; mkdir -p "$C/var" "$FIX/treino/var" "$RUN/registry" "$RUN/tl" "$RUN/commands" "$RUN/updates/inprogress"
NOW=$EPOCHSECONDS
{ printf 'CONTEST_ID=pv\nCONTEST_NAME="Prova"\nCONTEST_TYPE=icpc\nUSER_STORE=v2\nLANGUAGES="c"\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW+3600))" "$((NOW+7200))"
  printf "PROBS=( a col/pa 'Alfa' A 'col#pa' b col/pb 'Beta' B 'col#pb' c col/pc 'Gama' C 'col#pc' d col/pd 'Delta' D 'col#pd' e col/pe 'Eta' E 'col#pe' )\n"
} > "$C/conf"
fx_user "$C" pv.admin p "Admin"; fx_user "$C" time01 x "Time 1"
printf 'CONTEST=pv\nLOGIN=pv.admin\nLOGINAT=1\n' > "$SESS/adm"
printf 'CONTEST=pv\nLOGIN=time01\nLOGINAT=1\n' > "$SESS/comp"
reg(){ jq -cn --arg h "$1" --argjson t "$2" '{host:$h, state:"free", last_seen:$t, langs:["c"], problems:{}}' > "$RUN/registry/$1.json"; }
reg h1 "$NOW"; reg h2 "$NOW"; reg h3 $((NOW-3600)); reg h4 "$NOW"                      # h3 offline
echo '{"h4":{"disabled":true}}' > "$FIX/treino/var/judges-config.json"                  # h4 desabilitado
# tl <id> <narrow> <pkv-atual> <host>=<versão>… — run/tl/<id>.json + o memo .pkv
tl(){ local id="$1" n="$2" v="$3" hs='{}' kv; shift 3
  for kv in "$@"; do hs="$(jq -c --arg h "${kv%%=*}" --arg v "${kv#*=}" '. + {($h):{tl:{c:"1"}, at:1, pkg_version:$v}}' <<<"$hs")"; done
  jq -cn --arg id "$id" --arg n "$n" --argjson hs "$hs" '{id:$id, checksum:$n, hosts:$hs}' > "$RUN/tl/$id.json"
  [[ -n "$v" ]] && printf 'sig\t%s' "$v" > "$RUN/tl/$id.pkv"; }
tl 'col#pa' aa11 a0a0 h1=a0a0 h2=a0a0 h4=a0a0      # A: quente em h1 e h2
tl 'col#pb' bb11 b1b1 h1=b1b1 h2=b0b0              # B: h2 calibrou a versão VELHA
                                                   # C: sem run/tl — ninguém calibrou
tl 'col#pd' dd11 d0d0 h1=d0d0 h2=d0d0              # D: o índice diz que o pacote mudou (abaixo)
printf '{"hosts": {"h1": {' > "$RUN/tl/col#pe.json"   # E: run/tl corrompido
printf '%s' '{"problems":[{"id":"col#pa","tl_checksum":"aa11"},{"id":"col#pd","tl_checksum":"dd22"}]}' > "$FIX/treino/var/problem-owners.json"
mkdir -p "$RUN/commands/h1"; echo '{"cmdid":"q1","action":"calibrate","id":"col#pc","by":"x","at":1}' > "$RUN/commands/h1/q1.json"   # C em h1: na fila

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="contest=pv" HTTP_AUTHORIZATION="Bearer ${3:-adm}" \
    bash "$ROUTER" <<<"${4:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:-${BODY:0:400}}"; ((fail++)); fi; }
WJ(){ printf '%s' "$BODY" | jq -r ".checks[] | select(.id==\"judges_warm\") | $1" 2>/dev/null; }

echo "== preflight: quem está frio =="
call /contest/admin/preflight GET; DBG="$(WJ 'tojson')"
ck "judges_warm = warn, bilíngue, com o botão warm_judges" '[[ "$(WJ .level) $(WJ .action)" == "warn warm_judges" && -n "$(WJ .label_en)" && -n "$(WJ .detail_en)" ]]'
ck "6 pares frios: h2 em B (versão velha), C, D (índice mudou) e E (run/tl ilegível); h1 em D e E" '[[ "$(WJ .detail)" == "6 par(es)"* && "$(WJ .detail)" == *"h1: D, E · h2: B, C, D, E"* ]]'
ck "C em h1 está AQUECENDO (comando na fila), não frio" '[[ "$(WJ .detail)" == *"Aquecendo: h1: C."* ]]'
ck "h3 (offline) e h4 (desabilitado) não entram" '[[ "$(WJ .detail)" != *h3* && "$(WJ .detail)" != *h4* ]]'
ck "o item antigo 'fora do cache' saiu" '! printf "%s" "$BODY" | grep -q "fora do cache"'

echo "== pool por problema =="
echo '{"col#pb":["h1"]}' > "$C/problem-judges.json"
call /contest/admin/preflight GET; DBG="$(WJ .detail)"
ck "B só no h1 (pool): h2 deixa de contar p/ B" '[[ "$(WJ .detail)" == "5 par(es)"* && "$(WJ .detail)" == *"h2: C, D, E"* ]]'
rm -f "$C/problem-judges.json"

echo "== aquecer =="
call /contest/admin/warm-judges POST comp '{}'
ck "competidor → 403" '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/admin/warm-judges POST adm '{}'; DBG="$BODY"
ck "manda 6 calibrates (só os frios) e devolve a contagem de antes" '[[ "$(jq -r ".sent|length" <<<"$BODY") $(jq -c .before <<<"$BODY")" == "6 {\"warm\":3,\"warming\":1,\"cold\":6}" ]]'
L="$(for f in "$RUN"/commands/*/*.json; do h="${f%/*}"; printf '%s@%s\n' "$(jq -r .id "$f")" "${h##*/}"; done | sort | tr '\n' ' ')"; DBG="$L"
ck "a fila dos juízes tem exatamente os 6 frios + o C/h1 que já estava" '[[ "$L" == "col#pb@h2 col#pc@h1 col#pc@h2 col#pd@h1 col#pd@h2 col#pe@h1 col#pe@h2 " ]]'
ck "nada p/ h3/h4 nem p/ quem já estava quente (A)" '[[ ! -d "$RUN/commands/h3" && ! -d "$RUN/commands/h4" && "$L" != *"col#pa"* ]]'
DBG="$(cat "$C/var/admin-audit.log" 2>/dev/null)"; ck "auditado no contest" 'grep -q "warm-judges.*sent=6" "$C/var/admin-audit.log"'
call /contest/admin/warm-judges POST adm '{}'; DBG="$BODY"
ck "2º clique: nada novo (tudo aquecendo)" '[[ "$(jq -r ".sent|length" <<<"$BODY") $(jq -r .before.cold <<<"$BODY")" == "0 0" ]]'
call /contest/admin/preflight GET; DBG="$(WJ tojson)"
ck "preflight: 'Juízes aquecendo', sem botão" '[[ "$(WJ .level)" == warn && "$(WJ .label)" == "Juízes aquecendo" && "$(WJ ".action // \"\"")" == "" ]]'

echo "== o juiz pega o comando no heartbeat =="
mkdir -p "$RUN/secrets"; printf 'mojw_smoketest' > "$RUN/secrets/worker.token"
HB="$(PATH_INFO=/judge/heartbeat REQUEST_METHOD=POST QUERY_STRING= HTTP_AUTHORIZATION="Bearer mojw_smoketest" bash "$ROUTER" \
      <<<'{"host":"h2","state":"free","free_slots":2,"total_slots":2,"inv_hash":"","status":"ok"}' 2>/dev/null | awk 'f{print} /^\r?$/{f=1}')"
DBG="$HB"; ck "o heartbeat do h2 entrega um calibrate dirigido" '[[ "$(jq -r .command.action <<<"$HB")" == calibrate ]]'
call /contest/admin/preflight GET; DBG="$(WJ tojson)"
ck "…e o par entregue segue AQUECENDO (marcador em execução), não volta a frio" '[[ "$(WJ .label)" == "Juízes aquecendo" && "$(WJ .detail)" == "7 calibração(ões)"* ]]'

echo "== os juízes reportam =="
# o que o tl-report faz: host na versão atual + índice alcança; a fila esvazia
tl 'col#pb' bb11 b1b1 h1=b1b1 h2=b1b1; tl 'col#pc' cc11 c1c1 h1=c1c1 h2=c1c1
tl 'col#pd' dd22 d1d1 h1=d1d1 h2=d1d1; tl 'col#pe' ee11 e1e1 h1=e1e1 h2=e1e1
rm -f "$RUN"/commands/*/*.json "$RUN"/updates/inprogress/*/cmd-*.json
call /contest/admin/preflight GET; DBG="$(WJ tojson)"
ck "preflight: 'Juízes aquecidos' (ok)" '[[ "$(WJ .level)" == ok && "$(WJ .label_en)" == "Judges warmed up" ]]'
call /contest/admin/warm-judges POST adm '{}'; DBG="$BODY"
ck "aquecer com tudo quente não manda nada" '[[ "$(jq -r ".sent|length" <<<"$BODY")" == 0 && -z "$(ls "$RUN"/commands/*/*.json 2>/dev/null)" ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
