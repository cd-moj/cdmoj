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
import socket, struct, sys, os
sock, path, qs, auth, method, ae = sys.argv[1:7]
def nv(n, v):
    n, v = n.encode(), v.encode()
    def L(x): return bytes([len(x)]) if len(x) < 128 else struct.pack(">I", len(x) | 0x80000000)
    return L(n) + L(v) + n + v
def rec(t, c): return struct.pack(">BBHHBB", 1, t, 1, len(c), 0, 0) + c
params = nv("PATH_INFO", path) + nv("QUERY_STRING", qs) + nv("REQUEST_METHOD", method)
if auth: params += nv("HTTP_AUTHORIZATION", auth)
if ae:   params += nv("HTTP_ACCEPT_ENCODING", ae)
if os.environ.get("RADDR"): params += nv("REMOTE_ADDR", os.environ["RADDR"])
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
# SCORE_FULL_USERS com DOIS logins, gravado como o settings grava (%q ⇒ `livre1\ livre2`): os dois recebem o full
# — com o escape cru o .split() dava ['livre1\\', 'livre2'] e só o último valia (auditoria do painel, 03/10/2026)
for u in livre1 livre2; do mkdir -p "$C/users/$u"; printf '{"login":"%s"}' "$u" > "$C/users/$u/account.json"
  printf 'CONTEST=fx\nLOGIN=%s\n' "$u" > "$SESSIONDIR/tk-$u"; done
printf 'SCORE_FULL_USERS=%q\n' "livre1 livre2" >> "$C/conf"
r="$(req /contest/score contest=fx "Bearer tk-livre1")"
[[ "$r" == *linha-full* && "$r" == *'X-MOJ-Frozen: 0'* ]] && ok "SCORE_FULL_USERS: o 1º de dois logins recebe o full" || bad "score livre1: ${r:0:120}"
r="$(req /contest/score contest=fx "Bearer tk-livre2")"
[[ "$r" == *linha-full* ]] && ok "SCORE_FULL_USERS: o 2º também" || bad "score livre2: ${r:0:120}"
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
# trava de sede: IP preso ⇒ o bash decide (403 site_locked / papel isento) — auditoria 03/10/2026
mkdir -p "$RUNDIR/site-lock"; printf 'outro\t9999999999\n' > "$RUNDIR/site-lock/9.8.7.6"
d "IP preso pela trava de sede" "$(RADDR=9.8.7.6 req /contest/rounds contest=fx "Bearer tk-eq1")"
touch "$C/var/rounds-cache.pub.json" "$C/var/rounds-cache.priv.json"   # o conf mudou acima (SCORE_FULL_USERS)
r="$(RADDR=9.8.7.7 req /contest/rounds contest=fx "Bearer tk-eq1")"
[[ "$r" == *'"r":"pub"'* ]] && ok "IP livre segue servido" || bad "ip livre: ${r:0:80}"
# papel de conta SÓ da fonte (USERS_FROM): o _shared_role_ok é do bash ⇒ declina
mkdir -p "$CONTESTSDIR/fonte/users/sx.judge" "$CONTESTSDIR/sh/var"; printf '{"login":"sx.judge"}' > "$CONTESTSDIR/fonte/users/sx.judge/account.json"
printf 'CONTEST_NAME=Sh\nCONTEST_START=1\nCONTEST_END=99999999999\nUSERS_FROM=fonte\n' > "$CONTESTSDIR/sh/conf"
printf '{"success":true,"r":"pub"}' > "$CONTESTSDIR/sh/var/rounds-cache.pub.json"; printf '{"success":true,"r":"priv"}' > "$CONTESTSDIR/sh/var/rounds-cache.priv.json"
printf 'CONTEST=sh\nLOGIN=sx.judge\n' > "$SESSIONDIR/tk-sxj"
d "papel de conta só da fonte" "$(req /contest/rounds contest=sh "Bearer tk-sxj")"
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
r="$(req /contest/staff/queue contest=fx "Bearer tk-adm")"
n="$(printf '%s' "$r" | sed -n '/^{/,$p' | jq '[.requests[] | select((.id // "") == "")] | length' 2>/dev/null)"
[[ "$n" == 0 && "$r" == *'"id":"t1"'* ]] && ok "admin: staff-filters.json NÃO vira linha fantasma (espelho do PICK do bash)" || bad "fantasma: n=$n ${r:0:200}"
d "escopo sem scope-cache fresco" "$(req /contest/staff/queue contest=fx "Bearer tk-stf")"
printf 'eq1\n' > "$C/print-requests/.scope-cache/s1.staff"
touch "$C/print-requests/staff-filters.json" -d "-1 hour"   # cache mais novo que filters
r="$(req /contest/staff/queue contest=fx "Bearer tk-stf")"
[[ "$r" == *'"id":"t1"'* && "$r" != *'"id":"t3"'* ]] && ok "escopo recorta (vê eq1, não vê outro)" || bad "escopo: ${r:0:200}"
touch "$C/var/.score-dirty"
d "reconcile devido (dirty > stamp fora do piso)" "$(touch -d '-30 seconds' "$C/print-requests/.balloon-stamp"; req /contest/staff/queue contest=fx "Bearer tk-adm")"
rm -f "$C/var/.score-dirty" "$C/print-requests/staff-filters.json"; touch "$C/print-requests/.balloon-stamp"

echo "== submission/summary: '{}' constante sob log oculto (o poll mais quente da prova)"
r="$(req /submission/summary "contest=fx&ids=0123456789abcdef0123456789abcdef" "Bearer tk-eq1")"
[[ "$r" == *'{}'* ]] && ok "time + icpc sem SHOWLOG ⇒ {}" || bad "summary time: ${r:0:120}"
d "juiz no summary"           "$(req /submission/summary "contest=fx&ids=0123456789abcdef0123456789abcdef" "Bearer tk-adm")"
d "summary sem ids"           "$(req /submission/summary contest=fx "Bearer tk-eq1")"
printf 'SHOWLOG=1\n' >> "$C/conf"
d "SHOWLOG=1 ⇒ resumo real é do bash" "$(req /submission/summary "contest=fx&ids=0123456789abcdef0123456789abcdef" "Bearer tk-eq1")"
sed -i '/^SHOWLOG=1$/d' "$C/conf"

echo "== módulo desligado desliga a regra (03/10/2026): coortes e prorrogação por sede, igual ao bash"
M="$CONTESTSDIR/mf"; mkdir -p "$M/var" "$M/users/eq1" "$M/users/conv1"
printf '{"login":"eq1"}' > "$M/users/eq1/account.json"; printf '{"login":"conv1"}' > "$M/users/conv1/account.json"
printf 'CONTEST=mf\nLOGIN=eq1\n' > "$SESSIONDIR/tk-mfe"; printf 'CONTEST=mf\nLOGIN=conv1\n' > "$SESSIONDIR/tk-mfc"
printf '{"cohorts":[{"id":"oficial","default":true,"public":true},{"id":"conv","regex":"^conv","public":false}]}' > "$M/cohorts.json"
printf '[{"regex":"^eq","end":4100000000}]' > "$M/time-overrides.json"
mfconf(){ printf 'CONTEST_NAME=Mf\nCONTEST_START=1\nCONTEST_END=4000000000\nFREEZE_TIME=2\nCONTEST_MODULES=%s\n' "$1" > "$M/conf"
  sleep 1
  for f in placar placar-full placar-view-conv placar-view-conv-full; do printf 'icpc\nlinha-%s\n' "$f" > "$M/var/$f.txt"; done
  printf '{"v":"prorrogado"}' > "$M/var/basic-cache.u.4100000000.oficial.public.json"
  printf '{"v":"conf"}' > "$M/var/basic-cache.u.4000000000._.public.json"; }
mfconf coortes,sedes
r="$(req /contest/score contest=mf "Bearer tk-mfc")"
[[ "$r" == *linha-placar-view-conv* ]] && ok "coortes ligado: o convidado recebe o placar da coorte" || bad "mf conv on: ${r:0:120}"
r="$(req /contest/basic contest=mf "Bearer tk-mfe")"
[[ "$r" == *prorrogado* ]] && ok "sedes ligado: a variante do basic leva o fim prorrogado" || bad "mf basic on: ${r:0:120}"
mfconf ""
r="$(req /contest/score contest=mf "Bearer tk-mfc")"
[[ "$r" == *linha-placar* && "$r" != *conv* ]] && ok "coortes desligado: o convidado recebe o placar PÚBLICO" || bad "mf conv off: ${r:0:120}"
r="$(req /contest/basic contest=mf "Bearer tk-mfe")"
[[ "$r" == *'"v":"conf"'* ]] && ok "sedes desligado: a variante do basic volta ao fim do conf" || bad "mf basic off: ${r:0:120}"

echo "== placar ANÔNIMO (SCORE_ANON=1): fora da organização só o agregado, igual ao bash (03/10/2026)"
A="$CONTESTSDIR/an"; mkdir -p "$A/var" "$A/users/eqa" "$A/users/ma.mon"
printf '{"login":"eqa"}' > "$A/users/eqa/account.json"; printf '{"login":"ma.mon"}' > "$A/users/ma.mon/account.json"
printf 'CONTEST=an\nLOGIN=eqa\n' > "$SESSIONDIR/tk-ana"; printf 'CONTEST=an\nLOGIN=ma.mon\n' > "$SESSIONDIR/tk-anm"
printf 'CONTEST_NAME=An\nCONTEST_START=1\nCONTEST_END=99999999999\nSCORE_ANON=1\nSCORE_FULL_USERS=eqa\n' > "$A/conf"
sleep 1; printf 'icpc\nlinha-com-eqa\n' > "$A/var/placar.txt"; printf '{"anon":true,"n":7}' > "$A/var/placar-anon.json"
r="$(req /contest/score contest=an "Bearer tk-ana")"
[[ "$r" == *'X-MOJ-Anon: 1'* && "$r" == *'"n":7'* && "$r" != *linha-com-eqa* ]] && ok "anônimo: o time (mesmo na SCORE_FULL_USERS) recebe só o agregado" || bad "anon time: ${r:0:120}"
r="$(req /contest/score contest=an)"
[[ "$r" == *'X-MOJ-Anon: 1'* && "$r" != *linha-com-eqa* ]] && ok "anônimo: sem sessão, agregado" || bad "anon anon: ${r:0:120}"
r="$(req /contest/score contest=an "Bearer tk-anm")"
[[ "$r" == *linha-com-eqa* && "$r" != *X-MOJ-Anon* ]] && ok "anônimo: .mon (organização) recebe o TXT" || bad "anon mon: ${r:0:120}"
touch -d "+2 seconds" "$A/var/placar.txt"
d "anônimo: agregado mais velho que o placar declina (o bash refaz)" "$(req /contest/score contest=an "Bearer tk-ana")"

echo "== placar velho fora do piso declina"
touch -d "-30 seconds" "$C/var/placar.txt" "$C/var/placar.txt.gz" "$C/var/placar-full.txt"
touch "$C/var/.score-dirty"
d "score sujo além do piso"  "$(req /contest/score contest=fx)"

echo
echo "RESULT: $pass passed, $failn failed"
(( failn == 0 ))
