#!/bin/bash
# smoke-problem-judgeable.sh — "NÃO JULGÁVEL com os juízes de hoje" no /problems/status (Painel da gestão e
# selo "Pronto" do editor). Incidente de 30/09/2026: 15 problemas com MEMLIMITMB=262144 (256 GB) eram
# impossíveis desde o escalonador por largura, uma lista travou mais de 24 h e nada os apontava. Afirma, com
# um juiz do tamanho do de produção (27 slots de 1 CPU, nós de 14/13, ~252 GB):
#   • memória acima da máquina ⇒ not_judgeable:memory,<pedido>,<teto>; CPUNEEDED acima da máquina ⇒ cpus;
#     SAMENUMA com mais CPUs que o maior nó ⇒ numa; nenhuma linguagem declarada roda em juiz ⇒ langs;
#   • o problema comum segue julgável (sem pendência nova); a razão entra em review_reasons (needs_review) e
#     no `pending` (não fica PRONTO); counts.not_judgeable conta;
#   • judge_capacity no topo (p/ o aviso do editor): teto de memória da máquina e de UM slot, CPUs;
#   • só conta juiz visto nos últimos 7 dias e não desabilitado; sem juiz nenhum, não se afirma nada.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; RUN="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$RUN" "$SESS"' EXIT
export CONTESTSDIR="$FIX" RUNDIR="$RUN" SESSIONDIR="$SESS" MOJ_PROBLEMS_DIR="$FIX/problems" REGISTRYDIR="$RUN/registry"
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
T="$FIX/treino"; mkdir -p "$T/var" "$REGISTRYDIR" "$MOJ_PROBLEMS_DIR/col"
NOW="$EPOCHSECONDS"
printf 'CONTEST_ID=treino\nCONTEST_END=%s\n' "$((NOW+86400))" > "$T/conf"
echo '{"col":{"members":["autor"],"admins":[],"public_allowed":true,"title":"Col"}}' > "$T/var/orgs.json"
fx_user "$T" autor s "Autor"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino autor Autor "$NOW" > "$SESS/aut"
mkp(){ mkdir -p "$MOJ_PROBLEMS_DIR/col/$1"; printf '%s\n' "$2" > "$MOJ_PROBLEMS_DIR/col/$1/conf"; }
mkp ok 'MEMLIMITMB=1024'; mkp huge 'MEMLIMITMB=262144'; mkp wide 'CPUNEEDED=40'; mkp numa $'CPUNEEDED=20\nSAMENUMA=y'; mkp pddl ''
jq -cn '{problems:[ {id:"col#ok"}, {id:"col#huge"}, {id:"col#wide"}, {id:"col#numa"}, {id:"col#pddl", languages:["pddl"]} ]
        | map(. + {owner:"autor", repo:"col", prob:(.id|split("#")[1]), title:(.id|split("#")[1]), public:false, collaborators:[], collections:[]})}' \
  > "$T/var/problem-owners.json"
judge(){ # <host> <last_seen> [status]
  jq -cn --arg h "$1" --argjson ls "$2" --arg st "${3:-ok}" '{host:$h, last_seen:$ls, status:$st, total_slots:27, slot_cpus:1,
     slots_by_node:{"0":14,"1":13}, mem_kb:264118904, langs:["c","cpp","py3"]}' > "$REGISTRYDIR/$1.json"; }
get(){ OUT="$(PATH_INFO=/problems/status REQUEST_METHOD=GET QUERY_STRING="${1:-}" HTTP_AUTHORIZATION="Bearer aut" bash "$ROUTER" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
row(){ jq -c --arg id "col#$1" '.problems[] | select(.id == $id)' <<<"$BODY"; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:0:300}"; ((fail++)); fi; }

echo "== juiz de produção (27 slots, nós 14/13, ~252 GB) =="
judge j1 "$NOW"; get; DBG="$BODY"
ck "200 e 4 não julgáveis"                          '[[ "$OUT" == *"Status: 200"* && "$(jq -r .counts.not_judgeable <<<"$BODY")" == 4 ]]'
DBG="$(row huge)"
ck "MEMLIMITMB=262144: not_judgeable:memory com o pedido e o teto da máquina (252 GB − 4 GB − 64 MB)" '[[ "$(jq -r ".pending[0]" <<<"$DBG")" == "not_judgeable:memory,262144,253768" && "$(jq -r .judgeable.ok <<<"$DBG")" == false ]]'
ck "…e vira motivo de revisão (Painel: precisa revisar)" '[[ "$(jq -r .needs_review <<<"$DBG")" == true && "$(jq -c .review_reasons <<<"$DBG")" == *not_judgeable:memory* ]]'
DBG="$(row wide)"; ck "CPUNEEDED=40 num juiz de 27: cpus,40,27"        '[[ "$(jq -r ".pending[0]" <<<"$DBG")" == "not_judgeable:cpus,40,27" ]]'
DBG="$(row numa)"; ck "CPUNEEDED=20 + SAMENUMA com nó de 14: numa,20,14" '[[ "$(jq -r ".pending[0]" <<<"$DBG")" == "not_judgeable:numa,20,14" ]]'
DBG="$(row pddl)"; ck "só pddl, que juiz nenhum roda: langs"          '[[ "$(jq -r ".pending[0]" <<<"$DBG")" == "not_judgeable:langs,pddl," ]]'
DBG="$(row ok)";   ck "MEMLIMITMB=1024: julgável, sem pendência nova" '[[ "$(jq -r .judgeable.ok <<<"$DBG")" == true && "$(jq -c .pending <<<"$DBG")" != *not_judgeable* ]]'
DBG="$(jq -c .judge_capacity <<<"$BODY")"
ck "judge_capacity: máquina 253768 MB, 1 slot 9337 MB, 27 CPUs, nó de 14" '[[ "$DBG" == "{\"judges\":1,\"max_mem_mb\":253768,\"slot_mem_mb\":9337,\"max_cpus\":27,\"max_node_cpus\":14}" ]]'

echo "== quais juízes contam =="
judge j1 $(( NOW - 8 * 86400 )); get; DBG="$(jq -c '[.counts.not_judgeable, .judge_capacity.judges]' <<<"$BODY")"
ck "juiz sumido há 8 dias não conta: sem juiz não se afirma memória/CPU (sobra só a linguagem)" '[[ "$DBG" == "[1,0]" ]]'
judge j1 "$NOW" disabled; get; DBG="$(jq -c '[.counts.not_judgeable, .judge_capacity.judges]' <<<"$BODY")"
ck "juiz desabilitado também não"                 '[[ "$DBG" == "[1,0]" ]]'

echo; echo "RESULT: $pass passed, $fail failed"; exit $(( fail > 0 ? 1 : 0 ))
