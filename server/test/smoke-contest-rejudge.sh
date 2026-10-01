#!/bin/bash
# smoke-contest-rejudge.sh — POST /contest/rejudge (handlers/contest/rejudge.sh) sem ARG_MAX (01/10/2026).
# A FONTE ia ao jq por `--arg b "$codeb64"`: o Linux limita UM argumento a 128 KiB, então fonte >~96 KiB matava o
# jq, o spool saía com 0 byte e o rejulgamento virava Judge Error — com a linha do history JÁ marcada pendente.
# E a resposta montava as listas queued/skipped por `--argjson`: rejulgar milhares de ids (todas as submissões de
# um problema numa prova grande) dava 500 build_fail DEPOIS de o trabalho estar feito. Afirma:
#   • fonte pequena e fonte de 200 KiB chegam INTEIRAS ao spool (base64 decodifica no arquivo original);
#   • o history vira pendente só com o spool gravado; sem fonte = "pulada" e a linha fica como estava;
#   • 3.500 ids na mesma chamada (lista de puladas > 128 KiB) respondem 200 com as contagens;
#   • o spool vai ao shard do DONO; quem não é admin/chefe leva 403.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" \
       SPOOLDIR="$RUN/spool/submissions" SPOOLDONEDIR="$RUN/spool/submissions-done"
unset JUDGED_SHARDS
mkdir -p "$SPOOLDIR" "$SPOOLDONEDIR"
NOW="$EPOCHSECONDS"; C="$FIX/rj"; mkdir -p "$C/var" "$C/enunciados"
{ printf 'CONTEST_ID=rj\nCONTEST_NAME=Rejudge\nCONTEST_TYPE=icpc\nCONTEST_PRIORITY=prova\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW-3600))" "$((NOW+3600))"
  printf "PROBS=( x col#pa Alfa A col#pa )\n"; } > "$C/conf"
fx_user "$C" alice s "Alice"; fx_user "$C" rj.admin s "Admin"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' rj rj.admin Admin "$NOW" > "$SESS/adm"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' rj alice Alice "$NOW" > "$SESS/alu"
mkdir -p "$C/users/alice/submissions"
sub(){ # <id> <ext> <arquivo-fonte|""> -> linha WA no history (+ fonte arquivada)
  printf '%s:col#pa:%s:Wrong Answer:%s:%s\n' "$NOW" "${2^^}" "$NOW" "$1" >> "$C/users/alice/history"
  if [[ -n "$3" ]]; then cp "$3" "$C/users/alice/submissions/$1.$2"
  else mkdir -p "$C/users/alice/results"; printf '{"verdict":"Wrong Answer"}' > "$C/users/alice/results/$1.json"; fi; }   # julgada, fonte perdida
printf 'int main(){return 0;}\n' > "$FIX/small.c"
{ printf '#include <stdio.h>\n'; for i in $(seq 1 6000); do printf '/* linha %05d de comentario para a fonte ficar grande */\n' "$i"; done
  printf 'int main(){return 0;}\n'; } > "$FIX/big.cpp"
sub aaaa0000000000000000000000000001 c "$FIX/small.c"
sub aaaa0000000000000000000000000002 cpp "$FIX/big.cpp"
sub aaaa0000000000000000000000000003 c ""
call(){ # <token> <body|@arquivo>
  local o; if [[ "$2" == @* ]]; then
    o="$(PATH_INFO=/contest/rejudge REQUEST_METHOD=POST QUERY_STRING="contest=rj" HTTP_AUTHORIZATION="Bearer $1" bash "$ROUTER" < "${2#@}" 2>/dev/null)"
  else
    o="$(PATH_INFO=/contest/rejudge REQUEST_METHOD=POST QUERY_STRING="contest=rj" HTTP_AUTHORIZATION="Bearer $1" bash "$ROUTER" <<<"$2" 2>/dev/null)"
  fi
  STATUS="$(printf '%s' "$o" | sed -n 's/^Status: \([0-9]*\).*/\1/p' | head -1)"; STATUS="${STATUS:-200}"
  BODY="$(printf '%s' "$o" | awk 'f{print} /^\r?$/{f=1}')"; }
spoolf(){ find "$SPOOLDIR" -name "rj:*:$1:*" -print -quit; }
hline(){ grep ":$1\$" "$C/users/alice/history"; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: $STATUS ${BODY:0:200}"; ((fail++)); fi; }

echo "== papel =="
call alu '{"ids":["aaaa0000000000000000000000000001"]}'
ck "time comum: 403"                         '[[ "$STATUS" == 403 ]]'

echo "== fonte pequena, fonte de 200 KiB e sem fonte =="
(( $(stat -c %s "$FIX/big.cpp") > 200000 )) || echo "  (aviso: a fonte grande ficou menor que 200 KB)"
call adm '{"ids":["aaaa0000000000000000000000000001","aaaa0000000000000000000000000002","aaaa0000000000000000000000000003"]}'
ck "200, 2 enfileiradas e 1 pulada"          '[[ "$STATUS" == 200 && "$(jq -r .count <<<"$BODY")" == 2 && "$(jq -r .skipped_count <<<"$BODY")" == 1 ]]'
ck "queued lista as duas, na ordem"          '[[ "$(jq -c .queued <<<"$BODY")" == "[\"aaaa0000000000000000000000000001\",\"aaaa0000000000000000000000000002\"]" ]]'
ck "pulada diz o porquê (sem_fonte)"         '[[ "$(jq -r ".skipped[0]" <<<"$BODY")" == "aaaa0000000000000000000000000003:sem_fonte" ]]'
F1="$(spoolf aaaa0000000000000000000000000001)"; F2="$(spoolf aaaa0000000000000000000000000002)"
ck "fonte pequena inteira no spool"          '[[ -n "$F1" ]] && jq -r .code_b64 "$F1" | base64 -d | cmp -s - "$FIX/small.c"'
ck "fonte de 200 KiB INTEIRA no spool (era 0 byte)" '[[ -n "$F2" && -s "$F2" ]] && jq -r .code_b64 "$F2" | base64 -d | cmp -s - "$FIX/big.cpp"'
ck "spool com lang/filename/time do history" '[[ "$(jq -r ".lang + \" \" + .filename + \" \" + (.time|tostring)" "$F2")" == "CPP solution.cpp $NOW" ]]'
ck "as duas viraram pendentes no history"    'hline aaaa0000000000000000000000000001 | grep -q "Not Answered Yet" && hline aaaa0000000000000000000000000002 | grep -q "Not Answered Yet"'
ck "a sem fonte segue como estava"           'hline aaaa0000000000000000000000000003 | grep -q ":Wrong Answer:"'
ck "nenhum .in. largado no spool"            '[[ -z "$(find "$SPOOLDIR" -name ".in.*")" ]]'

echo "== milhares de ids numa chamada (listas > 128 KiB na resposta) =="
jq -cn '{ids: [range(0; 3500) | "bbbb\(.)" | . + ("0" * (32 - length))]}' > "$FIX/many.json"
t0=$EPOCHSECONDS; call adm @"$FIX/many.json"; dt=$(( EPOCHSECONDS - t0 ))
ck "200 com 3.500 puladas (era 500 build_fail)" '[[ "$STATUS" == 200 && "$(jq -r .skipped_count <<<"$BODY")" == 3500 && "$(jq -r .count <<<"$BODY")" == 0 ]]'
ck "a lista de puladas passa de 128 KiB"     '(( $(jq -c .skipped <<<"$BODY" | wc -c) > 131072 ))'
echo "  (3.500 ids em ${dt}s)"

echo "== shard do dono (JUDGED_SHARDS=2) =="
rm -rf "$SPOOLDIR"/*; mkdir -p "$SPOOLDIR"
sed -i 's/Not Answered Yet/Wrong Answer/' "$C/users/alice/history"
JUDGED_SHARDS=2 call adm '{"ids":["aaaa0000000000000000000000000001"]}'
want="$(JUDGED_SHARDS=2 bash -c "source '$ROOT/api/v1/lib/spool-shard.sh'; spool_shard_dir alice")"
ck "spool no shard do dono"                  '[[ "$STATUS" == 200 && -n "$(find "$want" -maxdepth 1 -name "rj:*:aaaa0000000000000000000000000001:*" -print -quit)" ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
