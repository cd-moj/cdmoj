#!/bin/bash
# PARTICIPAÇÃO VIRTUAL (lib/virtual.sh + handlers/treino/virtual/* + /submit virtual:<cid>):
# ciclo de vida da run, regra de desistência (≤15 min OU 0 AC; máx. 2; 3ª largada definitiva),
# uma-vez-por-conta, etiqueta de submissão, feed dos fantasmas, snapshot imune a rejulgamento,
# rename, moderação — e a garantia de que o placar OFICIAL não muda um byte.
# A matriz anti-vazamento mora em smoke-virtual-leak.sh.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$HERE/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" MOJ_JOBS_SYNC=1 \
       SPOOLDIR="$RUN/spool/submissions" SPOOLDONEDIR="$RUN/spool/submissions-done"
mkdir -p "$SPOOLDIR" "$SPOOLDONEDIR"
NOW="$EPOCHSECONDS"; S0=$((NOW-20000)); E0=$((NOW-10000))     # prova de 10000 s, encerrada

T="$FIX/treino"; mkdir -p "$T/var/jsons"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\nCONTEST_END=%s\n' "$((NOW+86400))" > "$T/conf"
for p in pa pb; do printf '{"id":"col#%s","title":"%s","public":true,"languages":["c","py"],"statement_langs":["pt"]}' "$p" "$p" > "$T/var/jsons/col#$p.json"; done
printf '{"problems":[{"id":"col#pa","owner":"dona","public":true},{"id":"col#pb","owner":"dona","public":true}]}' > "$T/var/problem-owners.json"
for u in ana beto caio x.admin; do fx_user "$T" "$u" s "Nome $u"
  printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino "$u" "$u" "$NOW" > "$SESS/tok-$u"; done

C="$FIX/v1"; mkdir -p "$C/var"
{ printf 'CONTEST_ID=v1\nCONTEST_NAME=%q\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\n' "Prova Um" "$S0" "$E0"
  printf 'CONTEST_MODULES=virtual\nLANGUAGES=%q\nPROBS=( x col/pa Alfa A col#pa x col/pb Beta B col#pb )\n' "c"; } > "$C/conf"
fx_user "$C" t1 s "Time Um"; fx_user "$C" t2 s "Time Dois"; fx_user "$C" v1.admin s "Adm"
printf 'CONTEST=v1\nLOGIN=v1.admin\nUSERFULLNAME=Adm\nLOGINAT=1\n' > "$SESS/tok-adm"
h(){ printf '%s:%s:C:%s:%s:%s\n' "$3" "$2" "$4" "$3" "$5" >> "$C/users/$1/history"; }
h t1 'col#pa' $((S0+600))  'Wrong Answer'       a1; h t1 'col#pa' $((S0+1200)) 'Accepted' a2
h t1 'col#pb' $((S0+3000)) 'Compilation Error'  a3; h t1 'col#pb' $((S0+3600)) 'Accepted' a4
h t2 'col#pa' $((S0+5000)) 'Accepted' b1

call(){ # <tok|-> <rota> <GET|POST> <query> [body]
  local auth=(); [[ "$1" != - ]] && auth=(HTTP_AUTHORIZATION="Bearer tok-$1")
  OUT="$(env "${auth[@]}" PATH_INFO="$2" REQUEST_METHOD="$3" QUERY_STRING="$4" HTTP_ACCEPT_ENCODING="" bash "$ROUTER" <<<"${5:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${OUT:0:300}"; ((fail++)); fi; }
code(){ jq -r '.error.code // empty' <<<"$BODY"; }
st(){ jq -r '.me.state' <<<"$BODY"; }
B64="$(printf 'int main(){return 0;}' | base64 -w0)"
vsub(){ call "$1" /submit POST contest=treino "{\"problem_id\":\"$2\",\"filename\":\"${3:-a.c}\",\"code_b64\":\"$B64\",\"virtual\":\"${4:-v1}\"}"; SID="$(jq -r '.submission_id // empty' <<<"$BODY")"; }
verdict(){ sed -i "s/:Not Answered Yet:\([0-9]*\):$2\$/:$3:\1:$2/" "$T/users/$1/history"; }   # <login> <subid> <veredicto>
# envelhece a run: janela E submissões etiquetadas recuam <s> segundos
age(){ local f="$T/users/$1/virtual/v1.json" s="$2" id
  jq -c --argjson s "$s" '.start-=$s | .end-=$s' "$f" > "$f.n" && mv "$f.n" "$f"
  while read -r id; do [[ -n "$id" ]] && awk -F: -v OFS=: -v id="$id" -v s="$s" '$NF==id{$(NF-1)-=s; $1-=s} 1' "$T/users/$1/history" > "$T/users/$1/history.n" && mv "$T/users/$1/history.n" "$T/users/$1/history"
  done < "$T/users/$1/virtual/v1.subs"; }

echo "== info / largada =="
call ana /treino/virtual/info GET contest=v1
ck "info 200 com título e duração"         '[[ "$(jq -r .title <<<"$BODY")" == "Prova Um" && "$(jq -r .duration <<<"$BODY")" == 10000 && "$(st)" == none ]]'
call - /treino/virtual/info GET contest=v1;  ck "sem Bearer: 401" '[[ "$OUT" == *"Status: 401"* ]]'
call ana /treino/virtual/problems GET contest=v1; ck "problemas antes de largar: 403 virtual_not_started" '[[ "$(code)" == virtual_not_started ]]'
vsub ana 'col#pa';                           ck "submit sem run: 403 virtual_not_running" '[[ "$(code)" == virtual_not_running ]]'
call ana /treino/virtual/run POST "" '{"contest":"v1","action":"start"}'; ck "start sem aceitar regras: 422" '[[ "$(code)" == terms_required ]]'
call x.admin /treino/virtual/run POST "" '{"contest":"v1","action":"start","accept":true}'; ck "conta de papel: 403" '[[ "$(code)" == role_forbidden ]]'
call ana /treino/virtual/run POST "" "{\"contest\":\"v1\",\"action\":\"start\",\"accept\":true,\"at\":$((NOW+999999))}"; ck "agendar além de 7 dias: 422" '[[ "$(code)" == virtual_at_invalid ]]'
call ana /treino/virtual/run POST "" "{\"contest\":\"v1\",\"action\":\"start\",\"accept\":true,\"at\":$((NOW+3600))}"
ck "agendada"                                '[[ "$(st)" == scheduled ]]'
call ana /treino/virtual/run POST "" '{"contest":"v1","action":"cancel"}'
ck "cancelar agendamento NÃO gasta desistência" '[[ "$(st)" == discarded && "$(jq -r .me.discards <<<"$BODY")" == 0 ]]'
call ana /treino/virtual/run POST "" '{"contest":"v1","action":"start","accept":true}'
ck "largou"                                  '[[ "$(st)" == running && "$(jq -r .me.can_discard <<<"$BODY")" == true ]]'
call ana /treino/virtual/run POST "" '{"contest":"v1","action":"start","accept":true}'; ck "2ª largada com run viva: 409 virtual_already" '[[ "$(code)" == virtual_already ]]'
call ana /treino/virtual/problems GET contest=v1
ck "problemas: letras + linguagens do CONTEST" '[[ "$(jq -r ".problems|map(.letter)|join(\"\")" <<<"$BODY")" == AB && "$(jq -c ".problems[0].languages" <<<"$BODY")" == "[\"c\"]" ]]'

echo "== submissão etiquetada =="
vsub ana 'col#pa' a.py;                      ck "linguagem banida NO CONTEST: 400 lang_not_allowed" '[[ "$(code)" == lang_not_allowed ]]'
vsub ana 'col#zz';                           ck "problema fora da prova: recusa" '[[ "$(code)" == virtual_problem || "$(code)" == problem_notfound ]]'
vsub ana 'col#pa'; A1="$SID";                ck "submissão aceita e etiquetada" '[[ -n "$A1" ]] && grep -qx "$A1" "$T/users/ana/virtual/v1.subs"'
call ana /submit POST contest=treino "{\"problem_id\":\"col#pa\",\"filename\":\"a.c\",\"code_b64\":\"$B64\"}"; PLAIN="$(jq -r .submission_id <<<"$BODY")"
ck "submissão NORMAL do treino não entra na run" '! grep -qx "$PLAIN" "$T/users/ana/virtual/v1.subs"'
verdict ana "$A1" 'Wrong Answer'; verdict ana "$PLAIN" 'Accepted'
call ana /treino/virtual/run GET contest=v1
ck "run deriva só das etiquetadas (1 N, 0 AC)" '[[ "$(jq -r ".me.runs|length" <<<"$BODY")" == 1 && "$(jq -r ".me.runs[0][2]" <<<"$BODY")" == N && "$(jq -r .me.solved <<<"$BODY")" == 0 ]]'

echo "== desistência: ≤15 min OU 0 AC; máx 2; 3ª definitiva =="
age ana 3000
call ana /treino/virtual/run GET contest=v1; ck "50 min, 0 AC: ainda pode desistir" '[[ "$(jq -r .me.can_discard <<<"$BODY")" == true ]]'
vsub ana 'col#pa'; A2="$SID"; verdict ana "$A2" 'Accepted'
call ana /treino/virtual/run GET contest=v1
ck "50 min + 1 AC: NÃO pode mais"            '[[ "$(jq -r .me.can_discard <<<"$BODY")" == false && "$(jq -r .me.solved <<<"$BODY")" == 1 ]]'
ck "penalidade = minuto do AC + 20×N"        '[[ "$(jq -r .me.penalty <<<"$BODY")" == $(( 3000/60 + 20 )) ]]'
call ana /treino/virtual/run POST "" '{"contest":"v1","action":"discard"}'; ck "discard travado: 409 virtual_locked" '[[ "$(code)" == virtual_locked ]]'
# beto: desiste 2×, a 3ª é definitiva
for i in 1 2; do
  call beto /treino/virtual/run POST "" '{"contest":"v1","action":"start","accept":true}'
  call beto /treino/virtual/run POST "" '{"contest":"v1","action":"discard"}'
done
ck "2 desistências contadas"                 '[[ "$(jq -r .me.discards <<<"$BODY")" == 2 && "$(jq -r .me.discards_left <<<"$BODY")" == 0 ]]'
call beto /treino/virtual/run POST "" '{"contest":"v1","action":"start","accept":true}'
ck "3ª largada é DEFINITIVA (sem desistir)"  '[[ "$(jq -r .me.final <<<"$BODY")" == true && "$(jq -r .me.can_discard <<<"$BODY")" == false ]]'
call beto /treino/virtual/run POST "" '{"contest":"v1","action":"discard"}'; ck "…discard recusado" '[[ "$(code)" == virtual_locked ]]'
call beto /treino/virtual/run POST "" '{"contest":"v1","action":"finish"}'
ck "definitiva encerra com 0 AC e GRAVA"     '[[ "$(st)" == finished ]] && [[ -f "$C/virtual/runs/beto.json" ]]'
# caio: fim do tempo com 0 AC = descarte automático (conta)
call caio /treino/virtual/run POST "" '{"contest":"v1","action":"start","accept":true}'
age caio 10001
call caio /treino/virtual/run GET contest=v1
ck "0 AC no fim do tempo: descartada sozinha" '[[ "$(st)" == discarded && "$(jq -r .me.discards <<<"$BODY")" == 1 ]] && [[ ! -f "$C/virtual/runs/caio.json" ]]'

echo "== finalização, snapshot, board =="
vsub ana 'col#pb'; A3="$SID"                 # fica PENDENTE
age ana 7001                                  # passou do fim
call ana /treino/virtual/run GET contest=v1; ck "pendente segura a finalização (judging)" '[[ "$(st)" == judging ]]'
vsub ana 'col#pb';                           ck "submit depois do fim: 403" '[[ "$(code)" == virtual_not_running ]]'
verdict ana "$A3" 'Accepted'
call ana /treino/virtual/run GET contest=v1
ck "finalizou: snapshot publicado"           '[[ "$(st)" == finished ]] && [[ "$(jq -r .solved "$C/virtual/runs/ana.json")" == 2 ]]'
SNAP="$(cat "$C/virtual/runs/ana.json")"
verdict ana "$A3" 'X'; sed -i "s/:Accepted:\([0-9]*\):$A3\$/:Wrong Answer:\1:$A3/" "$T/users/ana/history"
call ana /treino/virtual/run GET contest=v1
ck "snapshot imune a rejulgamento"           '[[ "$(cat "$C/virtual/runs/ana.json")" == "$SNAP" ]]'
call ana /treino/virtual/run POST "" '{"contest":"v1","action":"start","accept":true}'; ck "UMA vez: 409 depois de gravada" '[[ "$(code)" == virtual_already ]]'
call ana /treino/virtual/board GET contest=v1
ck "board lista os finalizados e marca you"  '[[ "$(jq -r ".virtuals|length" <<<"$BODY")" == 2 && "$(jq -r ".virtuals[]|select(.login==\"ana\").you" <<<"$BODY")" == true ]]'
call - /treino/virtual/board GET contest=v1;  ck "board anônimo: 200, ninguém é you" '[[ "$(jq -r "[.virtuals[].you]|any" <<<"$BODY")" == false ]]'

echo "== feed dos fantasmas =="
call - /treino/virtual/feed GET contest=v1
ck "feed: 2 times, 5 runs, CE = X (não penaliza)" '[[ "$(jq -r ".teams|length" <<<"$BODY")" == 2 && "$(jq -r ".runs|length" <<<"$BODY")" == 5 && "$(jq -c "[.runs[]|.[3]]" <<<"$BODY")" == "[\"N\",\"Y\",\"X\",\"Y\",\"Y\"]" ]]'
ck "feed: segundos relativos ao início"       '[[ "$(jq -r ".runs[0][0]" <<<"$BODY")" == 600 ]]'
ck "feed não carrega papel nem id de problema" '! grep -q "v1.admin\|col#" <<<"$BODY"'

echo "== o placar OFICIAL não muda um byte =="
P0="$(md5sum < "$C/var/placar.txt")"; rm -f "$C/var/placar.txt" "$C/var/.metrics-stamp"
bash "$ROOT/score/build.sh" v1 >/dev/null 2>&1
ck "placar oficial idêntico após as runs virtuais" '[[ "$(md5sum < "$C/var/placar.txt")" == "$P0" ]] && ! grep -q "ana\|beto" "$C/var/placar.txt"'
ck "nada do virtual em contests/v1/users/"    '[[ ! -e "$C/users/ana" && ! -e "$C/users/beto" ]]'

echo "== moderação + módulo =="
call adm /contest/admin/virtual GET contest=v1
ck "painel: elegível, checklist ok, 2 virtuais" '[[ "$(jq -r .eligible <<<"$BODY")" == true && "$(jq -r "[.checks[].ok]|all" <<<"$BODY")" == true && "$(jq -r ".virtuals|length" <<<"$BODY")" == 2 ]]'
call adm /contest/admin/virtual POST contest=v1 '{"action":"remove","login":"beto"}'
call - /treino/virtual/board GET contest=v1;  ck "removido some do board" '[[ "$(jq -r "[.virtuals[].login]|join(\",\")" <<<"$BODY")" == ana ]]'
ck "…e foi auditado"                          'grep -q "virtual-remove" "$C/var/admin-audit.log" 2>/dev/null || grep -rq "virtual-remove" "$C" 2>/dev/null'

echo "== dono DEVOLVE a tentativa (testador / quem teve problema) =="
call adm /contest/admin/virtual POST contest=v1 '{"action":"reset","login":"beto"}'
ck "reset: linha some do painel"               '[[ "$(jq -r "[.virtuals[].login]|index(\"beto\")" <<<"$BODY")" == null ]] && [[ ! -e "$C/virtual/runs/beto.json" ]]'
ck "…auditado"                                 'grep -rq "virtual-reset" "$C/var" 2>/dev/null'
call beto /treino/virtual/info GET contest=v1
ck "conta volta ao zero (sem run, 2 desistências)" '[[ "$(jq -r .me.state <<<"$BODY")" == none && "$(jq -r .me.discards_left <<<"$BODY")" == 2 ]]'
call beto /treino/virtual/run POST "" '{"contest":"v1","action":"start","accept":true}'
ck "…e pode largar de novo, não-definitiva"    '[[ "$(st)" == running && "$(jq -r .me.final <<<"$BODY")" == false ]]'
call adm /contest/admin/virtual POST contest=v1 '{"action":"reset","login":"ninguem"}'; ck "reset de quem não tem nada: 404" '[[ "$OUT" == *"Status: 404"* ]]'
call ana /contest/admin/virtual POST contest=v1 '{"action":"reset","login":"beto"}';   ck "reset por não-admin: recusa" '[[ "$OUT" == *"Status: 403"* || "$OUT" == *"Status: 401"* ]]'

echo "== MEUS ESCOLHIDOS: lista por conta (/treino/virtual/friends) =="
call - /treino/virtual/friends GET "";            ck "sem Bearer: 401" '[[ "$OUT" == *"Status: 401"* ]]'
call caio /treino/virtual/friends GET "";         ck "lista começa vazia, teto 100" '[[ "$(jq -c .logins <<<"$BODY")" == "[]" && "$(jq -r .max <<<"$BODY")" == 100 ]]'
call caio /treino/virtual/friends POST "" '{"add":["ana","beto","ana","caio"]}'
ck "add: dedupe e o PRÓPRIO login fica de fora" '[[ "$(jq -c .logins <<<"$BODY")" == "[\"ana\",\"beto\"]" ]]'
call caio /treino/virtual/friends POST "" '{"remove":["beto"],"add":["zeh"]}'
ck "add+remove no mesmo POST"                   '[[ "$(jq -c .logins <<<"$BODY")" == "[\"ana\",\"zeh\"]" ]]'
call caio /treino/virtual/friends POST "" '{"add":["../x"]}';      ck "login com barra: 422 friends_invalid" '[[ "$(code)" == friends_invalid ]]'
call caio /treino/virtual/friends POST "" '{"add":["a b"]}';       ck "login com espaço: 422"               '[[ "$(code)" == friends_invalid ]]'
call caio /treino/virtual/friends POST "" '{"add":[42]}';          ck "não-string: 422"                     '[[ "$(code)" == friends_invalid ]]'
BIG="$(jq -cn '[range(0;101)|"u\(.)"]')"
call caio /treino/virtual/friends POST "" "{\"logins\":$BIG}";     ck "101 logins: 422 friends_limit"       '[[ "$(code)" == friends_limit ]]'
call caio /treino/virtual/friends GET "";         ck "recusa não alterou a lista"                 '[[ "$(jq -c .logins <<<"$BODY")" == "[\"ana\",\"zeh\"]" ]]'
call caio /treino/virtual/friends POST "" '{"logins":["beto","ana"]}'
ck "logins:[…] substitui o conjunto"            '[[ "$(jq -c .logins <<<"$BODY")" == "[\"ana\",\"beto\"]" ]]'
call beto /treino/virtual/friends GET "";         ck "cada conta só vê a PRÓPRIA lista"           '[[ "$(jq -c .logins <<<"$BODY")" == "[]" ]]'
ck "arquivo _friends.json não é estado de contest" '[[ -s "$T/users/caio/virtual/_friends.json" ]] && ! ls "$T/users/caio/virtual/" | grep -qx "friends.json"'

echo "== rename do login leva o snapshot =="
( _LIBDIR="$ROOT/api/v1/lib"; source "$_LIBDIR/common.sh" 2>/dev/null; source "$_LIBDIR/virtual.sh"
  mv "$T/users/ana" "$T/users/ana2"; vr_rename_login ana ana2 )
ck "rename do AMIGO reescreve a lista de quem o escolheu" '[[ "$(jq -c .logins "$T/users/caio/virtual/_friends.json")" == "[\"ana2\",\"beto\"]" ]]'
( _LIBDIR="$ROOT/api/v1/lib"; source "$_LIBDIR/common.sh" 2>/dev/null; source "$_LIBDIR/virtual.sh"
  mv "$T/users/caio" "$T/users/caio9"; vr_rename_login caio caio9 )
ck "rename do DONO leva a lista junto (e _friends não vira contest)" '[[ "$(jq -c .logins "$T/users/caio9/virtual/_friends.json")" == "[\"ana2\",\"beto\"]" && ! -e "$FIX/_friends" ]]'
ck "snapshot renomeado"                        '[[ -f "$C/virtual/runs/ana2.json" && ! -f "$C/virtual/runs/ana.json" && "$(jq -r .login "$C/virtual/runs/ana2.json")" == ana2 ]]'

echo; echo "RESULT: $pass passed, $fail failed"; (( fail == 0 ))
