#!/bin/bash
# RECONCILE DE BALÃO EM LOTE + DESTACADO (15/10/2026, ensaio de escrita de 800 times). O reconcile criava cada balão
# com ~10 processos (36 ms) e lia o metrics do contest INTEIRO a cada rodada, DENTRO da consulta do staff que caísse
# na hora (p95 da fila 0,5 → 1,5 s). Agora: ids num processo, as contas num jq, um bloco de `seq`, o mapa "primeiro
# da sede" só das sedes dos candidatos, e a fila só DISPARA o reconcile (pr_reconcile_balloons_bg). Prende:
#   · o id NUNCA muda (python em lote == o md5sum|cut de sempre) — id diferente duplicaria balão já criado;
#   · time/universidade/nome da tarefa == pr_resolve_team/pr_resolve_univ/user_fullname (a implementação em bash
#     segue viva no pedido de impressão), com USERS_FROM, teams-meta.json, "null" literal, regex inválida e
#     teams-meta corrompido;
#   · o `seq` do lote é um bloco seguido, na ordem do sub_epoch;
#   · o mapa restrito às sedes dos candidatos dá as MESMAS linhas que o mapa do contest inteiro p/ essas sedes;
#   · a fila sem MOJ_JOBS_SYNC dispara o reconcile destacado (o balão nasce, auditado com o login do staff), um
#     disparo por janela de 5 s, a falha dele vai p/ run/balloon-reconcile.err, e com o módulo desligado só anda o
#     carimbo.
set -u
export BALLOON_RECONCILE_FLOOR_S=0
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
unset MOJ_JOBS_SYNC
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN"
C="$FIX/bb"; F="$FIX/fonte"; mkdir -p "$C/var" "$C/print-requests" "$F/var"
NOW="$(date +%s)"; T0=$((NOW-3600))
conf(){ { printf 'CONTEST_ID=bb\nCONTEST_MODULES=%s\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nUSERS_FROM=fonte\n' \
            "${1:-sedes,baloes}" "$T0" "$((NOW+3600))"
          printf 'PROBS=( cdmoj apc#p1 Um A apc#p1 )\n'; } > "$C/conf"; }
conf
printf 'CONTEST_ID=fonte\nCONTEST_TYPE=lista-publica\n' > "$F/conf"
fx_user "$C" bb.admin p "Admin" >/dev/null; fx_user "$C" s1.staff p "Staff" >/dev/null
acct(){ mkdir -p "$1/users/$2"; printf '%s\n' "$3" > "$1/users/$2/account.json"; }
# t1: tudo local · t2: só fullname local + escola pelo teams-meta · t3: dir local SEM account.json (compartilhado),
# tudo da fonte · t4: vazio em todo lugar + escola "null" literal · t5: univ_full da fonte vence o univ_short local
acct "$C" t1 '{"login":"t1","fullname":"Fulano Um","team":{"name":"Equipe Um","univ_full":"Universidade Um","region":"Sede A"}}'
acct "$C" t2 '{"login":"t2","fullname":"Time Dois","team":{"region":"Sede A"}}'
mkdir -p "$C/users/t3"
acct "$F" t3 '{"login":"t3","fullname":"Fonte Três","team":{"univ_short":"FT","region":"Sede B"}}'
acct "$C" t4 '{"login":"t4","fullname":"","team":{"name":"","region":"Sede B"}}'
acct "$C" t5 '{"login":"t5","fullname":"Cinco","team":{"univ_short":"U5L","region":"Sede A"}}'
acct "$F" t5 '{"login":"t5","fullname":"Cinco F","team":{"univ_full":"U5F"}}'
printf '{"rules":[{"regex":"^t2","school_full":"Escola Dois"},{"regex":"^t4","school":"null"}]}\n' > "$C/teams-meta.json"
_DIR="$ROOT/api/v1"; source "$_DIR/lib/sources.sh"; source "$_DIR/lib/print.sh"; set +o noglob
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; ((fail++)); fi; }
# AC de cada um, em ordem de sub_epoch PROPOSITALMENTE fora da ordem alfabética
i=0; for u in t3 t1 t5 t2 t4; do i=$((i+1))
  printf '%s:apc#p1:c:Accepted:%s:s%s\n' "$((i*60))" "$((T0+i*60))" "$u" > "$C/users/$u/history"; metrics_recompute bb "$u"; done
touch "$C/var/.score-dirty"
task(){ jq -c --arg l "$1" 'select(.login == $l)' "$C"/print-requests/bln*.json 2>/dev/null | head -1; }

echo "== lote (síncrono): ids, contas, seq"
MOJ_JOBS_SYNC=1 pr_reconcile_balloons bb
ck "5 tarefas de balão" '[[ "$(ls "$C"/print-requests/bln*.json 2>/dev/null | wc -l)" == 5 ]]'
bad=0; for u in t1 t2 t3 t4 t5; do
  [[ -f "$C/print-requests/$(pr_balloon_id bb "$u" 'apc#p1').json" ]] || { echo "    id de $u != md5sum|cut"; bad=1; }; done
ck "o id do lote (python) == o md5sum|cut de sempre, nos 5" '(( bad == 0 ))'
bad=0; for u in t1 t2 t3 t4 t5; do
  t="$(task "$u")"; want_t="$(pr_resolve_team bb "$u")"; want_u="$(pr_resolve_univ bb "$u")"
  want_f="$(user_fullname bb "$u")"; [[ -n "$want_f" ]] || want_f="$u"
  got="$(jq -r '[.team, .univ, .fullname] | join("|")' <<<"$t")"
  [[ "$got" == "$want_t|$want_u|$want_f" ]] || { echo "    $u: lote=[$got] bash=[$want_t|$want_u|$want_f]"; bad=1; }; done
ck "time/universidade/nome == pr_resolve_team/pr_resolve_univ/user_fullname (USERS_FROM, teams-meta, \"null\")" '(( bad == 0 ))'
ck "valores esperados de fato (t2 escola, t3 fonte, t4 vazio→login, t5 univ_full da fonte)" \
   '[[ "$(jq -r .univ <<<"$(task t2)")" == "Escola Dois" && "$(jq -r .team <<<"$(task t3)")" == "Fonte Três"
      && "$(jq -r "[.team,.univ,.fullname]|join(\"|\")" <<<"$(task t4)")" == "||t4" && "$(jq -r .univ <<<"$(task t5)")" == U5F ]]'
ck "seq em bloco seguido, na ordem do sub_epoch (t3 t1 t5 t2 t4)" \
   '[[ "$(for u in t3 t1 t5 t2 t4; do jq -r .seq <<<"$(task "$u")"; done | tr "\n" " ")" == "1 2 3 4 5 " ]]'
ck ".seq do contest avançou o bloco inteiro" '[[ "$(cat "$C/print-requests/.seq")" == 5 ]]'
ck "auditado um balloon-task por tarefa" '[[ "$(grep -c "balloon-task" "$C/var/admin-audit.log")" == 5 ]]'

echo "== teams-meta torto não derruba o lote"
rm -f "$C"/print-requests/bln*.json; rm -f "$C/print-requests/.balloon-stamp" "$C/print-requests/.balloon-prev"
printf '{"rules":[{"regex":"(","school":"X"},{"regex":"^t2","school_full":"Escola Dois"}]}\n' > "$C/teams-meta.json"
touch "$C/var/.score-dirty"; MOJ_JOBS_SYNC=1 pr_reconcile_balloons bb
ck "regex inválida: as 5 tarefas nascem e t2 sai sem escola (= pr_resolve_univ)" \
   '[[ "$(ls "$C"/print-requests/bln*.json | wc -l)" == 5 && "$(jq -r .univ <<<"$(task t2)")" == "$(pr_resolve_univ bb t2)" ]]'
rm -f "$C"/print-requests/bln*.json "$C/print-requests/.balloon-stamp" "$C/print-requests/.balloon-prev"
printf 'lixo{' > "$C/teams-meta.json"
touch "$C/var/.score-dirty"; MOJ_JOBS_SYNC=1 pr_reconcile_balloons bb
ck "teams-meta corrompido: as 5 nascem, t2 sem escola" '[[ "$(ls "$C"/print-requests/bln*.json | wc -l)" == 5 && "$(jq -r .univ <<<"$(task t2)")" == "" ]]'
rm -f "$C/teams-meta.json"

echo "== mapa 'primeiro da sede' restrito às sedes dos candidatos"
printf 't1\n' > "$FIX/so"
all="$(pr_site_first_map bb | grep '^S' | grep -P '^S\tSede A\t' | sort)"
sub="$(pr_site_first_map bb "$FIX/so" | grep '^S' | sort)"
ck "restrito (sede de t1) == as linhas da Sede A do mapa inteiro" '[[ -n "$all" && "$all" == "$sub" ]]'
ck "e não lê a Sede B" '! pr_site_first_map bb "$FIX/so" | grep -q "Sede B"'

echo "== a FILA dispara o reconcile DESTACADO"
printf 'CONTEST=bb\nLOGIN=s1.staff\nUSERFULLNAME=Staff\nLOGINAT=1\n' > "$SESS/stf"
queue(){ PATH_INFO=/contest/staff/queue REQUEST_METHOD=GET QUERY_STRING=contest=bb HTTP_AUTHORIZATION="Bearer stf" \
         bash "$ROUTER" </dev/null >/dev/null 2>&1; }
espera(){ local k; for k in $(seq 1 50); do [[ -f "$1" ]] && return 0; sleep 0.2; done; return 1; }
fx_user "$C" t6 x "Time Seis" >/dev/null
printf '1:apc#p1:c:Accepted:%s:s6\n' "$((T0+900))" > "$C/users/t6/history"; metrics_recompute bb t6
touch -d '-30 seconds' "$C/print-requests/.balloon-stamp"; touch "$C/var/.score-dirty"
queue
ck "a consulta deixa o marcador do disparo" '[[ -f "$C/print-requests/.balloon-kick" ]]'
ck "o balão de t6 nasce no reconcile destacado" 'espera "$C/print-requests/$(pr_balloon_id bb t6 "apc#p1").json"'
sleep 0.5
ck "auditado com o login do staff que consultou" 'grep -P "\ts1\.staff\tballoon-task\t.*login=t6" "$C/var/admin-audit.log" >/dev/null'
fx_user "$C" t7 x "Time Sete" >/dev/null
printf '1:apc#p1:c:Accepted:%s:s7\n' "$((T0+960))" > "$C/users/t7/history"; metrics_recompute bb t7
touch -d '-30 seconds' "$C/print-requests/.balloon-stamp"; touch "$C/var/.score-dirty"
queue; sleep 1.5
ck "um disparo por janela de 5 s: o 2º dentro dela não dispara" '[[ ! -f "$C/print-requests/$(pr_balloon_id bb t7 "apc#p1").json" ]]'
touch -d '-10 seconds' "$C/print-requests/.balloon-kick"; queue
ck "passada a janela, dispara e o balão de t7 nasce" 'espera "$C/print-requests/$(pr_balloon_id bb t7 "apc#p1").json"'
sleep 0.5
# reconcile destacado que FALHA deixa rastro em run/balloon-reconcile.err (o lock virou DIRETÓRIO: o `9>` dele falha e
# derruba o subshell do reconcile — vale também como root, que ignoraria um chmod 000; destacado, o erro antes sumia)
rm -f "$C/print-requests/.balloon.lock"; mkdir "$C/print-requests/.balloon.lock"
touch -d '-30 seconds' "$C/print-requests/.balloon-stamp"; sleep 1
touch "$C/var/.score-dirty"; touch -d '-10 seconds' "$C/print-requests/.balloon-kick"; queue
ck "falha do reconcile destacado vai p/ run/balloon-reconcile.err" 'espera "$RUN/balloon-reconcile.err" && sleep 0.5 && grep -q "bb: pr_reconcile_balloons rc=" "$RUN/balloon-reconcile.err"'
rmdir "$C/print-requests/.balloon.lock"
conf "sedes"; touch -d '-30 seconds' "$C/print-requests/.balloon-stamp"; sleep 1; touch "$C/var/.score-dirty"
touch -d '-10 seconds' "$C/print-requests/.balloon-kick"; queue
ck "módulo baloes desligado: o carimbo anda na própria consulta, sem disparo" \
   '[[ ! "$C/var/.score-dirty" -nt "$C/print-requests/.balloon-stamp" && -z "$(find "$C/print-requests/.balloon-kick" -newermt "-5 seconds" 2>/dev/null)" ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
