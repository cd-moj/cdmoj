#!/bin/bash
# smoke-porteiro.sh — o porteiro (caminho rápido Python) de ponta a ponta, com FastCGI real:
# fixture própria (contests/sessões/caches), porteiro num socket temporário, cliente FCGI
# embutido (python). O que se prova:
#   - serve cache FRESCO com a VARIANTE certa (papel da nav, pub/priv das rodadas);
#   - placar: anônimo, .gz por Accept-Encoding, X-MOJ-Frozen;
#   - DECLINA (conexão fecha sem resposta ⇒ 502⇒bash) tudo fora do feliz: cache frio,
#     token inválido, contest secreto sem sessão, POST, traversal, scope=mine.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."
T="$(mktemp -d)"; trap 'rm -rf "$T"; [[ -n "${PPID_P:-}" ]] && kill "$PPID_P" 2>/dev/null' EXIT
pass=0; failn=0
ok(){ echo "  ok: $1"; pass=$((pass+1)); }
bad(){ echo "  FALHOU: $1"; failn=$((failn+1)); }

# ── fixture ───────────────────────────────────────────────────────────────────
export CONTESTSDIR="$T/contests" RUNDIR="$T/run" SESSIONDIR="$T/run/sessions"
C="$CONTESTSDIR/fx"; mkdir -p "$C/var" "$C/users/eq1" "$C/users/x.admin" "$SESSIONDIR" "$RUNDIR/tl"
printf 'CONTEST_NAME=Fixture\nCONTEST_START=1\nCONTEST_END=99999999999\nFREEZE_TIME=2\n' > "$C/conf"
printf '{"login":"eq1"}' > "$C/users/eq1/account.json"
printf '{"login":"x.admin"}' > "$C/users/x.admin/account.json"
printf 'CONTEST=fx\nLOGIN=eq1\n' > "$SESSIONDIR/tk-eq1"
printf 'CONTEST=fx\nLOGIN=x.admin\n' > "$SESSIONDIR/tk-adm"
printf 'icpc\nlinha-frozen\n' > "$C/var/placar.txt"
printf 'icpc\nlinha-full\n' > "$C/var/placar-full.txt"
gzip -kf "$C/var/placar.txt"
printf '{"success":true,"nav":"time"}'  > "$C/var/nav-cache.time.json"
printf '{"success":true,"nav":"admin"}' > "$C/var/nav-cache.admin.json"
printf '{"success":true,"r":"pub"}'  > "$C/var/rounds-cache.pub.json"
printf '{"success":true,"r":"priv"}' > "$C/var/rounds-cache.priv.json"
# secreto p/ o teste do gate
S="$CONTESTSDIR/sx"; mkdir -p "$S/var"
printf 'CONTEST_NAME=Secreto\nSECRET=1\n' > "$S/conf"
printf 'icpc\n' > "$S/var/placar.txt"

# ── porteiro no ar ────────────────────────────────────────────────────────────
SOCK="$T/p.sock"
# orçamentos PINADOS (o deploy pode alargá-los por env; o teste fixa o contrato base)
SCORE_SERVE_FLOOR_S=8 BASIC_CACHE_TTL=20 NAV_CACHE_TTL=20 ROUNDS_CACHE_TTL=30 \
python3 porteiro/moj-porteiro.py -s "$SOCK" -c 2 -b 8 2> "$T/p.err" &
PPID_P=$!
for i in $(seq 40); do [[ -S "$SOCK" ]] && break; sleep 0.1; done
[[ -S "$SOCK" ]] || { echo "porteiro não subiu"; cat "$T/p.err"; exit 1; }

# cliente FCGI: fala uma requisição e ecoa a resposta crua (vazio = DECLINE)
req(){ # req PATH QS [AUTH] [METHOD] [ACCEPT_ENC]
  python3 - "$SOCK" "$1" "$2" "${3:-}" "${4:-GET}" "${5:-}" <<'PY'
import socket, struct, sys
sock, path, qs, auth, method, ae = sys.argv[1:7]
def nv(n, v):
    n, v = n.encode(), v.encode()
    def L(x): return bytes([len(x)]) if len(x) < 128 else struct.pack(">I", len(x) | 0x80000000)
    return L(n) + L(v) + n + v
def rec(t, c): return struct.pack(">BBHHBB", 1, t, 1, len(c), 0, 0) + c
params = nv("PATH_INFO", path) + nv("QUERY_STRING", qs) + nv("REQUEST_METHOD", method)
if auth: params += nv("HTTP_AUTHORIZATION", auth)
if ae:   params += nv("HTTP_ACCEPT_ENCODING", ae)
s = socket.socket(socket.AF_UNIX); s.settimeout(5); s.connect(sock)
s.sendall(rec(1, struct.pack(">HB5x", 1, 0)) + rec(4, params) + rec(4, b"") + rec(5, b""))
out = b""
try:
    while True:
        h = s.recv(8)
        if len(h) < 8: break
        _, t, _, cl, pl, _ = struct.unpack(">BBHHBB", h)
        c = b""
        while len(c) < cl + pl: c += s.recv(cl + pl - len(c))
        if t == 6: out += c[:cl]
        if t == 3: break
except Exception: pass
sys.stdout.buffer.write(out)
PY
}

echo "== serve com variante certa"
r="$(req /contest/rounds contest=fx "Bearer tk-eq1")"
[[ "$r" == *'"r":"pub"'* ]] && ok "rounds pub p/ time" || bad "rounds eq1: $r"
r="$(req /contest/rounds contest=fx "Bearer tk-adm")"
[[ "$r" == *'"r":"priv"'* ]] && ok "rounds priv p/ admin" || bad "rounds adm: $r"
r="$(req /contest/navbuttons contest=fx "Bearer tk-adm")"
[[ "$r" == *'"nav":"admin"'* ]] && ok "nav do papel admin" || bad "nav adm: $r"
r="$(req /contest/navbuttons contest=fx "Bearer tk-eq1")"
[[ "$r" == *'"nav":"time"'* ]] && ok "nav do papel time" || bad "nav eq1: $r"

echo "== placar"
r="$(req /contest/score contest=fx)"
[[ "$r" == *linha-frozen* && "$r" == *'X-MOJ-Frozen: 1'* ]] && ok "anônimo: congelado + header 1" || bad "score anon: ${r:0:120}"
r="$(req /contest/score contest=fx "Bearer tk-adm")"
[[ "$r" == *linha-full* && "$r" == *'X-MOJ-Frozen: 0'* ]] && ok "admin: full + header 0" || bad "score adm: ${r:0:120}"
r="$(req /contest/score contest=fx "" GET gzip)"
[[ "$r" == *'Content-Encoding: gzip'* ]] && ok "gz servido com Accept-Encoding" || bad "score gz: ${r:0:120}"

echo "== declina tudo fora do feliz"
d(){ [[ -z "$2" ]] && ok "$1" || bad "$1 (respondeu: ${2:0:60})"; }
d "token inexistente"        "$(req /contest/rounds contest=fx "Bearer NAOEXISTE")"
d "secreto sem sessão"       "$(req /contest/score contest=sx)"
d "POST"                     "$(req /contest/score contest=fx "" POST)"
d "traversal"                "$(req /contest/score "contest=../../etc")"
d "scope=mine"               "$(req /contest/score "contest=fx&scope=mine" "Bearer tk-adm")"
d "cache frio (basic sem cache)" "$(req /contest/basic contest=fx "Bearer tk-eq1")"
rm "$C/var/rounds-cache.pub.json"
d "cache ausente"            "$(req /contest/rounds contest=fx "Bearer tk-eq1")"
touch "$C/conf"
d "cache mais velho que o conf" "$(req /contest/rounds contest=fx "Bearer tk-adm")"

echo "== updates COMPUTADO (news + clars com visibilidade)"
printf '[{"date":100,"title":"a"},{"date":200,"title":"b"}]' > "$C/news.json"
mkdir -p "$C/clarifications"
printf '{"login":"eq1","answer":"sim","answered_at":150}'  > "$C/clarifications/c1.json"
printf '{"login":"zz","public":true,"answer":"ok","answered_at":250}' > "$C/clarifications/c2.json"
printf '{"login":"zz","answer":"privada","answered_at":300}' > "$C/clarifications/c3.json"
printf '{"login":"zz","public":true,"answer":""}' > "$C/clarifications/c4.json"
r="$(req /contest/updates "contest=fx&news_since=150&clar_since=200" "Bearer tk-eq1")"
[[ "$r" == *'"news":{"last":200,"count":2,"unread":1}'* ]] && ok "news agregado" || bad "news: $r"
[[ "$r" == *'"clar":{"last":250,"count":2,"unread":1}'* ]] && ok "clar do time (própria+pública, respondidas)" || bad "clar eq1: $r"
r="$(req /contest/updates "contest=fx&clar_since=0" "Bearer tk-adm")"
[[ "$r" == *'"count":3'* && "$r" == *'"last":300'* ]] && ok "admin vê todas as respondidas" || bad "clar adm: $r"
printf 'lixo{' > "$C/clarifications/c5.json"
d "clar com JSON inválido"    "$(req /contest/updates contest=fx "Bearer tk-eq1")"
rm "$C/clarifications/c5.json"

echo "== staff/queue COMPUTADA (escopo, ordenação, gate do reconcile)"
printf 'CONTEST=fx\nLOGIN=s1.staff\n' > "$SESSIONDIR/tk-stf"
mkdir -p "$C/users/s1.staff" "$C/print-requests/.scope-cache"
printf '{"login":"s1.staff"}' > "$C/users/s1.staff/account.json"
printf '{"id":"t1","seq":2,"login":"eq1","status":"pending","kind":"print"}' > "$C/print-requests/t1.json"
printf '{"id":"t2","seq":1,"login":"eq1","status":"delivered"}' > "$C/print-requests/t2.json"
printf '{"id":"t3","seq":3,"login":"outro","status":"pending"}' > "$C/print-requests/t3.json"
touch "$C/print-requests/.balloon-stamp"   # reconcile não-devido (stamp fresco, sem dirty novo)
r="$(req /contest/staff/queue contest=fx "Bearer tk-adm")"
[[ "$r" == *'"id":"t1"'* && "$r" == *'"id":"t3"'* && "$r" == *'"balloons_frozen":0'* ]] && ok "admin vê tudo + envelope" || bad "queue adm: ${r:0:200}"
[[ "$r" == *'"t1"'*'"t3"'*'"t2"'* ]] && ok "ordenação pending(seq)→delivered" || bad "ordem: ${r:0:200}"
printf '{"s1.staff":["region:Sede 01"]}' > "$C/print-requests/staff-filters.json"
d "escopo sem scope-cache fresco" "$(req /contest/staff/queue contest=fx "Bearer tk-stf")"
printf 'eq1\n' > "$C/print-requests/.scope-cache/s1.staff"
touch "$C/print-requests/staff-filters.json" -d "-1 hour"   # cache mais novo que filters
r="$(req /contest/staff/queue contest=fx "Bearer tk-stf")"
[[ "$r" == *'"id":"t1"'* && "$r" != *'"id":"t3"'* ]] && ok "escopo recorta (vê eq1, não vê outro)" || bad "escopo: ${r:0:200}"
touch "$C/var/.score-dirty"
d "reconcile devido (dirty > stamp fora do piso)" "$(touch -d '-30 seconds' "$C/print-requests/.balloon-stamp"; req /contest/staff/queue contest=fx "Bearer tk-adm")"
rm -f "$C/var/.score-dirty" "$C/print-requests/staff-filters.json"; touch "$C/print-requests/.balloon-stamp"

echo "== placar velho fora do piso declina"
touch -d "-30 seconds" "$C/var/placar.txt" "$C/var/placar.txt.gz" "$C/var/placar-full.txt"
touch "$C/var/.score-dirty"
d "score sujo além do piso"  "$(req /contest/score contest=fx)"

echo
echo "RESULT: $pass passed, $failn failed"
(( failn == 0 ))
