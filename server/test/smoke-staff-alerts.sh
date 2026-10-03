#!/bin/bash
# smoke-staff-alerts.sh — GET /contest/staff-alerts (o alerta global de juiz/chefe/admin/.mon) e o espelho
# dele no porteiro (r_staff_alerts): mesmas contagens, papel a papel, nas duas implementações.
#
#   bash server/test/smoke-staff-alerts.sh
#
# O que se prova:
#   - quem recebe o quê: time 403; .mon só clarifications (review:null); juiz sem `conflicts`;
#     chefe e admin com tudo;
#   - clarifications: abertas, sem dono (reserva ausente OU vencida), a mais nova; respondida não conta;
#   - fila de revisão: `needing`, `mine_todo` POR LOGIN (já votou ⇒ não; vagas cheias ⇒ não; avaliando ⇒
#     sim), conflitos (o MESMO número do review/conflicts), MANUAL_VERDICT desligado zera a fila de voto
#     mas não os conflitos;
#   - arquivo corrompido não zera a contagem (o resto continua contando) e diretório ausente dá zero;
#   - nenhum login de quem perguntou ou votou na resposta;
#   - o porteiro devolve O MESMO corpo (fora o `now`) e declina o que é do bash (time, JSON inválido).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; SPOOL="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$SPOOL"; [[ -n "${PPID_P:-}" ]] && kill "$PPID_P" 2>/dev/null' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
C="$FIX/sa"; mkdir -p "$C/review" "$C/clarifications" "$C/var"
NOW="$(date +%s)"; FUT=$(( NOW + 600 )); PAST=$(( NOW - 600 ))
printf 'CONTEST_ID=sa\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nMANUAL_VERDICT=1\nREVIEW_JUDGES=2\n' "$((NOW-3600))" "$((NOW+3600))" > "$C/conf"
for u in sa.admin j1.judge j2.judge j3.judge cj.cjudge m1.mon aluno1; do fx_user "$C" "$u" p "$u"; done
for s in adm:sa.admin j1:j1.judge j2:j2.judge cj:cj.cjudge mon:m1.mon alu:aluno1; do
  printf 'CONTEST=sa\nLOGIN=%s\nUSERFULLNAME=x\nLOGINAT=1\n' "${s#*:}" > "$SESS/${s%%:*}"
done
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD=GET QUERY_STRING="contest=sa" HTTP_AUTHORIZATION="Bearer $2" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" SPOOLDIR="$SPOOL" bash "$ROUTER" </dev/null 2>"$FIX/err")"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:240}"; ((fail++)); fi; }
J(){ jq -c "$1" <<<"$BODY"; }

# clarifications: aberta sem dono (100), aberta reservada VIVA (200), aberta com reserva VENCIDA (300),
# respondida (400 — não conta)
cl(){ printf '%s' "$2" > "$C/clarifications/$1.json"; }
cl c1 '{"id":"c1","time":100,"login":"aluno1","question":"q","answer":"","answered_at":0}'
cl c2 "{\"id\":\"c2\",\"time\":200,\"login\":\"aluno1\",\"question\":\"q\",\"answer\":\"\",\"answer_claim\":{\"by\":\"j1.judge\",\"at\":$NOW,\"expires_at\":$FUT}}"
cl c3 "{\"id\":\"c3\",\"time\":300,\"login\":\"aluno1\",\"question\":\"q\",\"answer\":\"\",\"answer_claim\":{\"by\":\"j2.judge\",\"at\":$PAST,\"expires_at\":$PAST}}"
cl c4 '{"id":"c4","time":400,"login":"aluno1","question":"q","answer":"sim","answered_at":450}'
: > "$C/clarifications/c1.lock"

# fila de revisão (quórum 2)
rv(){ printf '%s' "{\"id\":\"$1\",\"login\":\"aluno1\",\"problem_id\":\"p#a\",\"lang\":\"C\",\"computed_verdict\":\"Wrong Answer\",\"status\":\"${2}\",\"conflict\":false,\"created_at\":$3,\"sub_epoch\":$3,\"claimants\":$4,\"votes\":$5}" > "$C/review/$1.json"; }
V(){ printf '{"by":"%s","label":"x","verdict":"%s","at":1}' "$1" "$2"; }
K(){ printf '{"by":"%s","at":1,"expires_at":%s}' "$1" "$2"; }
rv r1 open     10 '[]' '[]'                                                     # ninguém pegou
rv r2 voting   20 '[]' "[$(V j1.judge 'Wrong Answer')]"                        # j1 já votou
rv r3 conflict 30 '[]' "[$(V j1.judge Accepted),$(V j2.judge 'Wrong Answer')]" # conflito
rv r4 agreed   40 '[]' "[$(V j1.judge Accepted),$(V j2.judge Accepted)]"       # unânime (fora)
rv r5 released 50 '[]' "[$(V j1.judge Accepted)]"                              # liberado (fora)
rv r6 claimed  60 "[$(K j2.judge "$FUT"),$(K cj.cjudge "$FUT")]" '[]'          # 2 avaliando: sem vaga
rv r7 claimed  70 "[$(K j1.judge "$FUT")]" '[]'                               # j1 avaliando
rv r8 claimed  80 "[$(K j3.judge "$PAST"),$(K j2.judge "$PAST")]" '[]'         # reservas VENCIDAS: vaga

echo "== papéis =="
call /contest/staff-alerts alu
ck "time: 403"                           '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/staff-alerts mon
ck ".mon: só clarifications"             '[[ "$(J .review)" == null && "$(J .clar.open)" == 3 ]]'
call /contest/staff-alerts j1
ck "juiz: sem conflitos (null)"          '[[ "$(J .review.conflicts)" == null ]]'
ck "juiz: nenhum login na resposta"      '[[ "$BODY" != *aluno1* && "$BODY" != *j2.judge* ]]'

echo "== clarifications =="
call /contest/staff-alerts j1
ck "abertas = 3 (respondida fora)"       '[[ "$(J .clar.open)" == 3 ]]'
ck "sem dono = 2 (reserva vencida conta)" '[[ "$(J .clar.unclaimed)" == 2 ]]'
ck "a aberta mais nova = 300"            '[[ "$(J .clar.last)" == 300 ]]'

echo "== fila de revisão =="
ck "needing = r1 r2 r6 r7 r8 (5)"        '[[ "$(J .review.needing)" == 5 ]]'
ck "j1: mine_todo = r1 r7 r8 (já votou r2; r6 sem vaga)" '[[ "$(J .review.mine_todo)" == 3 && "$(J .review.mine_last)" == 80 ]]'
call /contest/staff-alerts j2
ck "j2: mine_todo = r1 r2 r6 r7 r8 (5)"  '[[ "$(J .review.mine_todo)" == 5 ]]'
call /contest/staff-alerts cj
ck "chefe: conflitos = 1"                '[[ "$(J .review.conflicts)" == 1 ]]'
ck "chefe: mine_todo = r1 r2 r6 r7 r8"   '[[ "$(J .review.mine_todo)" == 5 ]]'
CONF_N="$(PATH_INFO=/contest/review/conflicts REQUEST_METHOD=GET QUERY_STRING=contest=sa HTTP_AUTHORIZATION="Bearer adm" \
  CONTESTSDIR="$FIX" SESSIONDIR="$SESS" SPOOLDIR="$SPOOL" bash "$ROUTER" </dev/null 2>/dev/null | awk 'f{print} /^\r?$/{f=1}' | jq -r .n)"
call /contest/staff-alerts adm
ck "admin: conflitos = o n do review/conflicts" '[[ "$(J .review.conflicts)" == "$CONF_N" && "$CONF_N" == 1 ]]'
ck "quórum e manual expostos"            '[[ "$(J .review.quorum)" == 2 && "$(J .review.manual)" == true ]]'

echo "== porteiro: o mesmo corpo, papel a papel =="
SOCK="$FIX/p.sock"
CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$FIX/run" python3 "$ROOT/porteiro/moj-porteiro.py" -s "$SOCK" -c 2 -b 8 2> "$FIX/p.err" &
PPID_P=$!
for i in $(seq 40); do [[ -S "$SOCK" ]] && break; sleep 0.1; done
preq(){ python3 - "$SOCK" "$1" <<'PY'
import socket, struct, sys
sock, tok = sys.argv[1:3]
def nv(n, v):
    n, v = n.encode(), v.encode()
    def L(x): return bytes([len(x)]) if len(x) < 128 else struct.pack(">I", len(x) | 0x80000000)
    return L(n) + L(v) + n + v
def rec(t, c): return struct.pack(">BBHHBB", 1, t, 1, len(c), 0, 0) + c
params = nv("PATH_INFO", "/contest/staff-alerts") + nv("QUERY_STRING", "contest=sa") + nv("REQUEST_METHOD", "GET")
params += nv("HTTP_AUTHORIZATION", "Bearer " + tok)
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
pbody(){ preq "$1" | awk 'f{print} /^\r?$/{f=1}'; }
same(){ # papel: corpo do bash == corpo do porteiro (sem o `now`)
  local b p; call /contest/staff-alerts "$1"; b="$(jq -cS 'del(.now)' <<<"$BODY")"
  p="$(pbody "$1" | jq -cS 'del(.now)' 2>/dev/null)"
  [[ -n "$p" && "$b" == "$p" ]] || { echo "     bash:     $b"; echo "     porteiro: ${p:-(declinou)}"; return 1; }; }
if [[ -S "$SOCK" ]]; then
  for r in mon j1 j2 cj adm; do ck "porteiro = bash p/ $r" "same $r"; done
  ck "porteiro declina o time (o 403 é do bash)" '[[ -z "$(preq alu)" ]]'
  # conta de papel só na FONTE (USERS_FROM): o porteiro não tem o _shared_role_ok do bash ⇒ declina
  mkdir -p "$FIX/src/users/sj.judge"; printf 'CONTEST_ID=src\n' > "$FIX/src/conf"; printf '{"login":"sj.judge"}' > "$FIX/src/users/sj.judge/account.json"
  printf 'USERS_FROM=src\n' >> "$C/conf"; printf 'CONTEST=sa\nLOGIN=sj.judge\n' > "$SESS/sj"
  ck "porteiro declina papel de conta não-local" '[[ -z "$(preq sj)" ]]'
  sed -i '/^USERS_FROM=/d' "$C/conf"
else
  echo "  FAIL: porteiro não subiu"; cat "$FIX/p.err"; ((fail++))
fi

echo "== MANUAL_VERDICT desligado: fila de voto zera, conflito não =="
sed -i 's/^MANUAL_VERDICT=1/MANUAL_VERDICT=0/' "$C/conf"
call /contest/staff-alerts cj
ck "needing/mine_todo = 0, conflitos = 1" '[[ "$(J .review.needing)" == 0 && "$(J .review.mine_todo)" == 0 && "$(J .review.conflicts)" == 1 && "$(J .review.manual)" == false ]]'
[[ -S "$SOCK" ]] && ck "porteiro = bash (manual off)" "same cj"
sed -i 's/^MANUAL_VERDICT=0/MANUAL_VERDICT=1/' "$C/conf"

echo "== arquivo corrompido e diretório ausente =="
printf 'lixo{' > "$C/clarifications/c9.json"
call /contest/staff-alerts j1
ck "clarification corrompida: as outras seguem contando" '[[ "$(J .clar.open)" == 3 ]]'
ck "…e o aviso vai ao error.log"         'grep -q "rv_scan" "$FIX/err"'
[[ -S "$SOCK" ]] && ck "porteiro declina (o bash decide)" '[[ -z "$(preq j1)" ]]'
rm -f "$C/clarifications/c9.json"
mv "$C/review" "$C/review.off"; mv "$C/clarifications" "$C/clar.off"
call /contest/staff-alerts adm
ck "sem diretórios (rodada arquivada): zeros, 200" '[[ "$OUT" != *"Status: 4"* && "$OUT" != *"Status: 5"* && "$(J .clar.open)" == 0 && "$(J .review.needing)" == 0 && "$(J .review.conflicts)" == 0 ]]'
[[ -S "$SOCK" ]] && ck "porteiro = bash (sem diretórios)" "same adm"

echo
echo "smoke-staff-alerts: $pass ok, $fail falha(s)"
(( fail == 0 ))
