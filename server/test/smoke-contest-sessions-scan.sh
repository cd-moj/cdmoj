#!/bin/bash
# smoke-contest-sessions-scan.sh — as varreduras de sessão POR CONTEST (sess_files_of, lib/session-index.sh)
# só leem as sessões DAQUELE contest.
#
# XIV Maratona UnB (25/09/2026): o painel de Sessões do admin (GET /contest/admin/sessions, que pola) fazia
# `source` das 21.606 sessões do diretório GLOBAL — a sessão não expira — p/ achar as 60 do contest: 1,2 s por
# chamada. Agora um grep pela linha `CONTEST=` escolhe os arquivos e só eles são lidos. Prende:
#   · a resposta é a mesma de antes (contagem, nomes com espaço, UA decodificado, alerta de 2 máquinas);
#   · NENHUMA sessão de outro contest é lida (cada uma, se lida, deixa marca num arquivo) — nem a de contest
#     com prefixo igual (`sx2`), nem a que tem `CONTEST=sx` dentro do NOME, nem o dotfile;
#   · a varredura ainda SEMEIA o índice por login, só com os tokens do contest;
#   · logout-all (competidores) e logout-mismatch apagam só sessões do contest.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; MARK="$(mktemp)"; trap 'rm -rf "$FIX" "$SESS" "$MARK"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
C="$FIX/sx"; mkdir -p "$C/var"
NOW=$EPOCHSECONDS
printf 'CONTEST_ID=sx\nCONTEST_MODULES=sedes,maquinas,baloes,coortes,inscricoes\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nUSER_STORE=v2\n' "$((NOW-3600))" "$((NOW+3600))" > "$C/conf"
fx_user "$C" sx.admin p "Admin"; for u in team001 team002 team003; do fx_user "$C" $u x "Time $u"; done
jq -n '{mode:"enforce", fallback:"MLinux"}' > "$C/ua-gate.json"
b64(){ printf '%s' "$1" | base64 -w0; }
# mkses <token> <contest> <login> <nome> <loginat> <ip> <ua> — como o create_session grava (%q)
mkses(){ { printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\nIP=%q\nUA_B64=%q\n' "$2" "$3" "$4" "$5" "$6" "$(b64 "$7")"
           [[ -n "${8:-}" ]] && printf '%s\n' "$8"; } > "$SESS/$1"; }
mkses adm   sx sx.admin "Admin do SX"    "$((NOW-500))" 10.0.0.9 "Mozilla Chrome"
mkses t1a   sx team001  "Time Um da Silva" "$((NOW-400))" 10.0.0.1 "Mozilla (MLinux/26aa/x/1) Firefox"
mkses t1b   sx team001  "Time Um da Silva" "$((NOW-300))" 10.0.0.2 "Mozilla (MLinux/26aa/y/2) Firefox"
mkses t2    sx team002  "Time 2"         "$((NOW-200))" 10.0.0.3 "Mozilla (MLinux/26aa/z/3) Firefox"
mkses t3    sx team003  "Time 3"         "$((NOW-100))" 10.0.0.4 "Chrome sem imagem"
# sessões ALHEIAS: cada uma, se lida por `source`, deixa um x no $MARK
LEAK=": \$(printf x >> $MARK)"
for i in $(seq 1 150); do mkses "o$i" treino "aluno$i" "Aluno $i" "$NOW" 10.1.0.1 "UA" "$LEAK"; done
mkses pre   sx2 team001 "Prefixo igual"  "$NOW" 10.2.0.1 "UA" "$LEAK"
mkses nome  treino evil "CONTEST=sx"     "$NOW" 10.2.0.2 "UA" "$LEAK"
mkses .dot  sx team002  "Dotfile"        "$NOW" 10.2.0.3 "UA" "$LEAK"
NFOREIGN=152   # o dotfile nem o laço antigo lia (glob)

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-adm}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:-${BODY:0:300}}"; ((fail++)); fi; }
J(){ printf '%s' "$BODY" | jq -r "$1" 2>/dev/null; }
leaks(){ tr -cd x < "$MARK" | wc -c; }

echo "== GET /contest/admin/sessions =="
: > "$MARK"; call /contest/admin/sessions GET '' adm 'contest=sx'; DBG=""
ck "5 sessões do contest, as mais novas primeiro" '[[ "$(J .count)" == 5 && "$(J "[.sessions[].login]|join(\",\")")" == "team003,team002,team001,team001,sx.admin" ]]'
ck "nome com espaço e UA decodificado" '[[ "$(J ".sessions[]|select(.login==\"team003\")|.user_agent")" == "Chrome sem imagem" && "$(J "[.sessions[]|select(.login==\"team001\")|.name]|unique|.[0]")" == "Time Um da Silva" ]]'
ck "alerta: team001 em 2 IPs e 2 UAs (e só ele)" '[[ "$(J "[.alerts[]|.login+\":\"+(.multi_ip|tostring)+\":\"+(.multi_ua|tostring)]|join(\",\")")" == "team001:true:true" ]]'
DBG="$(leaks) sessões alheias lidas"
ck "NENHUMA sessão de outro contest foi lida (eram $NFOREIGN de $((NFOREIGN+5)) aqui; 21.606 na produção)" '[[ "$(leaks)" == 0 ]]'
DBG=""
IDX="$SESS/.idx/sx"
ck "a varredura semeou o índice (.seeded) só com os tokens do contest" '[[ -e "$IDX/.seeded" && "$(cat "$IDX"/team001 | sort | tr "\n" " ")" == "t1a t1b " && "$(cat "$IDX"/* 2>/dev/null | sort | tr "\n" " ")" == "adm t1a t1b t2 t3 " ]]'

echo "== logout-mismatch (gate: UA precisa de MLinux) =="
: > "$MARK"; call /contest/admin/logout-mismatch POST '{}' adm 'contest=sx'
ck "derrubou só a sessão de UA errado do contest (team003)" '[[ "$(J .sessions_removed)" == 1 && ! -e "$SESS/t3" && -e "$SESS/t2" && -e "$SESS/o1" && -e "$SESS/nome" ]]'
DBG="$(leaks) lidas"; ck "sem ler sessão alheia" '[[ "$(leaks)" == 0 ]]'; DBG=""

echo "== logout-all dos competidores =="
: > "$MARK"; call /contest/admin/logout-all POST '{"scope":"competitors"}' adm 'contest=sx'
ck "3 sessões de competidor do contest apagadas; admin, alheias e dotfile ficam" '[[ "$(J .competitors)" == 3 && "$(J .staff)" == 0 ]] && [[ ! -e "$SESS/t1a" && ! -e "$SESS/t1b" && ! -e "$SESS/t2" && -e "$SESS/adm" && -e "$SESS/pre" && -e "$SESS/nome" && -e "$SESS/.dot" && -e "$SESS/o150" ]]'
DBG="$(leaks) lidas"; ck "sem ler sessão alheia" '[[ "$(leaks)" == 0 ]]'; DBG=""

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
