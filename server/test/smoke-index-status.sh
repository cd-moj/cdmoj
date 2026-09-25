#!/bin/bash
# smoke-index-status.sh — GET /index/status (página pública de saúde): os agregados dos juízes num jq SÓ.
#
# XIV Maratona UnB (25/09/2026): a rota levava 1,6 s — 4–5 jq POR registro de juiz (.last_seen, slots, ncpu,
# GPU). Prende as REGRAS (os números abaixo são os que o laço antigo calcula sobre este diretório — o
# gabarito): online no TTL; slots só inteiros (string de dígitos vale), senão `state` busy = 1 de 1; ncpu
# inteiro (ou total_slots×slot_cpus do agente com slot_cpus); GPU só nvidia/amd com nomes e sem mensagem
# de erro; total = nº de ARQUIVOS (inclusive vazio). E o nº de jq, que não cresce por registro; com um
# registro CORROMPIDO, o laço antigo (mesmo resultado).
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"
FIX="$(mktemp -d)"; RUN="$(mktemp -d)"; SHIM="$(mktemp -d)"; trap 'rm -rf "$FIX" "$RUN" "$SHIM"' EXIT
export CONTESTSDIR="$FIX" RUNDIR="$RUN" REGISTRYDIR="$RUN/registry" SPOOLDIR="$RUN/spool" QUEUEDIR="$RUN/queue"
mkdir -p "$RUN/registry" "$RUN/spool" "$RUN/queue"; NOW=$EPOCHSECONDS
python3 - "$RUN/registry" "$NOW" <<'PY'
import json, sys
d, now = sys.argv[1], int(sys.argv[2]); n = 0
def w(o, raw=None):
    global n; n += 1; open('%s/h%03d.json' % (d, n), 'w').write(raw if raw is not None else json.dumps(o))
for i in range(40): w({"last_seen": now - 3, "free_slots": i % 4, "total_slots": 4, "ncpu": 12, "state": "idle"})
for i in range(10): w({"last_seen": str(now - 5), "free_slots": "1", "total_slots": "3", "ncpu": "8"})
w({"last_seen": now, "state": "busy", "ncpu": 4}); w({"last_seen": now, "state": "idle"})
w({"last_seen": now - 500, "free_slots": 0, "total_slots": 8, "ncpu": 16, "state": "busy"})
w({"last_seen": now + 0.5}); w({"free_slots": 1, "total_slots": 2}); w({"last_seen": now, "free_slots": 5, "total_slots": 2})
w({"last_seen": now, "free_slots": 1.5, "total_slots": 2, "state": "busy"})
w({"last_seen": now, "gpu": {"vendor": "nvidia", "names": "RTX 4090"}, "ncpu": 32})
w({"last_seen": now, "gpu": {"vendor": "amd", "names": "MI100"}}); w({"last_seen": now, "gpu": {"vendor": "other", "names": "VGA"}})
w({"last_seen": now, "gpu": {"vendor": "nvidia", "names": "NVIDIA-SMI has failed because it couldn't communicate"}})
w({"last_seen": now, "gpu": {"vendor": "nvidia", "names": ""}}); w(None, raw="")
# agente com slots de VÁRIAS cpus: conta total_slots×slot_cpus (a reserva não julga); slot_cpus 0 = o ncpu
w({"last_seen": now, "free_slots": 1, "total_slots": 3, "slot_cpus": 2, "ncpu": 12})
w({"last_seen": now, "free_slots": 2, "total_slots": 2, "slot_cpus": 0, "ncpu": 8})
PY
printf '#!/bin/bash\necho x >> "%s/n"\nexec "%s" "$@"\n' "$SHIM" "$(command -v jq)" > "$SHIM/jq"; chmod +x "$SHIM/jq"
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:-}"; ((fail++)); fi; }
run(){ rm -f "$RUN/status.json"; : > "$SHIM/n"
  OUT="$(PATH="$SHIM:$PATH" PATH_INFO=/index/status REQUEST_METHOD=GET QUERY_STRING= bash "$ROOT/api/v1/router.sh" </dev/null 2>/dev/null)"
  JUDGE="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}' | command jq -cS .judge)"; NJ=$(wc -l < "$SHIM/n"); DBG="$JUDGE ($NJ jq)"; }
echo "== registros variados =="
run
ck "online 61 · slots 205 · ocupados 121 · cpus 610 · gpus 2 · total 65" '[[ "$JUDGE" == "{\"busy\":121,\"cpus_online\":610,\"gpus_online\":2,\"healthy\":true,\"online\":61,\"slots\":205,\"total\":65}" ]]'
ck "o nº de jq não cresce por registro (≤ 4; eram 257 com 65 registros) [$NJ]" '(( NJ <= 4 ))'
echo "== registro corrompido: o laço antigo, mesmo resultado =="
printf '{"last_seen": %s, "free_slots": 1, "tot' "$NOW" > "$RUN/registry/z-corrupto.json"
run
ck "mesmos agregados, total 66 (o corrompido conta como arquivo, offline)" '[[ "$JUDGE" == "{\"busy\":121,\"cpus_online\":610,\"gpus_online\":2,\"healthy\":true,\"online\":61,\"slots\":205,\"total\":66}" ]]'
echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
