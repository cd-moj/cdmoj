#!/bin/bash
# smoke-absent-dq.sh — DESCLASSIFICAR QUEM NÃO LOGOU em lote (/contest/admin/absent-disqualify, lib/absent-dq.sh):
#   · prévia: candidato = sem login na janela (1 h antes da abertura do login até o fim) E sem submissão; fica de fora
#     quem submeteu, quem logou, quem está num estágio PUBLICADO da classificação, quem já está desclassificado e papel;
#   · aplicar exige o plan_id da prévia (409 plan_changed); marca .disqualified + .dq_batch, audita, toca o .score-dirty;
#   · desfazer devolve só quem ainda tem a marca do lote (a decisão individual vence);
#   · só o admin; a qualquer momento (prova rodando: live + janela até agora).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN"
NOW="$EPOCHSECONDS"; ST=$((NOW - 7200)); EN=$((NOW - 3600)); LS=$((ST - 600))
C="$FIX/ad"; mkdir -p "$C/var"
{ printf 'CONTEST_ID=ad\nCONTEST_TYPE=icpc\nUSER_STORE=v2\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\nLOGIN_START_TIME=%s\n' "$ST" "$EN" "$LS"; } > "$C/conf"
for u in ad.admin ad.judge t1 t2 t3 t4 t5 t6 t7 t8 t9; do fx_user "$C" "$u" p "Time $u"; done
jq -c '.team = {name:"Norte Um", univ_short:"UN", region:"Norte"}' "$C/users/t4/account.json" > "$C/x" && mv "$C/x" "$C/users/t4/account.json"
echo "$ST:col#pa:C:Accepted:$ST:s1" > "$C/users/t1/history"            # t1: logou e submeteu
echo "$ST:col#pa:C:Wrong Answer:$ST:s3" > "$C/users/t3/history"        # t3: submeteu SEM login registrado
jq -c '.disqualified = true' "$C/users/t8/account.json" > "$C/x" && mv "$C/x" "$C/users/t8/account.json"
jq -c '.password = "!desabilitado"' "$C/users/t9/account.json" > "$C/x" && mv "$C/x" "$C/users/t9/account.json"
# acessos: t1 e t2 na janela; t4 só no aquecimento (antes da janela); ad.judge na janela (papel nunca conta)
{ printf '%s\tt1\t10.0.0.1\tx\n' $((ST + 60)); printf '%s\tt2\t10.0.0.2\tx\n' $((LS - 1800))
  printf '%s\tt4\t10.0.0.4\tx\n' $((ST - 86400)); printf '%s\tad.judge\t10.0.0.9\tx\n' $((ST + 5)); } > "$C/var/access.log"
# classificação: t6 num estágio PUBLICADO (fica); t7 só num RASCUNHO (sai)
jq -cn '{version:1, stages:[{id:"pda", status:"published", teams:{t6:{via:"p1"}}}, {id:"rasc", status:"draft", teams:{t7:{via:"p2"}}}]}' > "$C/classification.json"
for p in "ad.admin adm" "t1 tk1"; do set -- $p
  printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' ad "$1" "$1" "$NOW" > "$SESS/$2"; done
call(){ # <method> <token> [body]
  local b="${3:-}"
  OUT="$(PATH_INFO=/contest/admin/absent-disqualify REQUEST_METHOD="$1" QUERY_STRING="contest=ad" HTTP_AUTHORIZATION="Bearer $2" \
    CONTENT_LENGTH="${#b}" REMOTE_ADDR=127.0.0.9 TEAM_HOST_LOCK=0 bash "$ROUTER" <<<"$b" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
code(){ jq -r '.error.code // empty' <<<"$BODY"; }
dq(){ jq -r 'if .disqualified == true then "dq" else "ok" end' "$C/users/$1/account.json"; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:240}"; ((fail++)); fi; }

echo "== prévia =="
call GET tk1; ck "time não usa (403)" '[[ "$(code)" == admin_required ]]'
call GET adm
ck "candidatos: t4 (só aquecimento), t5, t7 (rascunho não protege), t9 (desabilitado)" \
   '[[ "$(jq -r "[.preview.candidates[].login] | sort | join(\",\")" <<<"$BODY")" == "t4,t5,t7,t9" ]]'
ck "fica: t6, classificado num estágio publicado" '[[ "$(jq -c "[.preview.kept_classified[] | [.login, .via, .stage]]" <<<"$BODY")" == "[[\"t6\",\"p1\",\"pda\"]]" ]]'
ck "contagens: 9 times, 2 logaram, 2 com submissão, 1 já desclassificado" \
   '[[ "$(jq -c ".preview.counts | [.teams, .logged, .with_subs, .already_dq, .absent, .candidates]" <<<"$BODY")" == "[9,2,2,1,5,4]" ]]'
ck "janela: 1 h antes da abertura do login até o fim; prova encerrada (live:false)" \
   '[[ "$(jq -c "[.preview.window.from, .preview.window.to, .preview.live]" <<<"$BODY")" == "[$((LS - 3600)),$EN,false]" ]]'
ck "o último login do t4 vem junto (o aquecimento)" '[[ "$(jq -r ".preview.candidates[] | select(.login==\"t4\") | [.last_login, .name, .region] | @tsv" <<<"$BODY")" == "$((ST - 86400))	Norte Um	Norte" ]]'
ck "nenhuma conta mudou na prévia" '[[ "$(dq t4)$(dq t5)" == okok && ! -e "$C/var/absent-dq.json" ]]'
PID="$(jq -r .preview.plan_id <<<"$BODY")"

echo "== aplicar =="
call POST adm '{"action":"apply"}';                    ck "sem plan_id: 409 plan_changed" '[[ "$(code)" == plan_changed && "$(dq t4)" == ok ]]'
call POST adm '{"action":"apply","plan_id":"x"}';      ck "plan_id de outra lista: 409 plan_changed" '[[ "$(code)" == plan_changed ]]'
call POST tk1 "{\"action\":\"apply\",\"plan_id\":\"$PID\"}"; ck "time não aplica (403)" '[[ "$(code)" == admin_required && "$(dq t4)" == ok ]]'
rm -f "$C/var/.score-dirty"
call POST adm "{\"action\":\"apply\",\"plan_id\":\"$PID\"}"
BID="$(jq -r .batch <<<"$BODY")"
ck "aplica: 4 no lote" '[[ "$(jq -r .count <<<"$BODY")" == 4 && "$BID" =~ ^adq[0-9a-f]{10}$ ]]'
ck "t4 t5 t7 t9 desclassificados com a marca do lote; t1 t2 t3 t6 não" \
   '[[ "$(dq t4)$(dq t5)$(dq t7)$(dq t9)" == dqdqdqdq && "$(dq t1)$(dq t2)$(dq t3)$(dq t6)" == okokokok && "$(jq -r .dq_batch "$C/users/t7/account.json")" == "$BID" ]]'
ck "placar/estatística regeneram (.score-dirty)" '[[ -e "$C/var/.score-dirty" ]]'
ck "auditoria: uma linha por time + a do lote" '[[ "$(grep -c "user-disqualify.*batch=$BID" "$C/var/admin-audit.log")" == 4 && "$(grep -c "absent-disqualify.*batch=$BID n=4" "$C/var/admin-audit.log")" == 1 ]]'
ck "lote listado" '[[ "$(jq -c ".batches[0] | [.id, .count, .by, .undone_at]" <<<"$BODY")" == "[\"$BID\",4,\"ad.admin\",null]" ]]'
call GET adm; ck "nova prévia: ninguém a desclassificar" '[[ "$(jq -r .preview.counts.candidates <<<"$BODY")" == 0 && "$(jq -r .preview.counts.already_dq <<<"$BODY")" == 5 ]]'
call POST adm "{\"action\":\"apply\",\"plan_id\":\"$(jq -r .preview.plan_id <<<"$BODY")\"}"; ck "sem candidato: 409 nothing_to_do" '[[ "$(code)" == nothing_to_do ]]'

echo "== desfazer =="
# o admin devolve o t5 à mão e o desclassifica de novo, individualmente: a decisão individual vence a do lote
for u in true false; do b="{\"login\":\"t5\",\"undo\":$u}"
  PATH_INFO=/contest/admin/user-disqualify REQUEST_METHOD=POST QUERY_STRING="contest=ad" HTTP_AUTHORIZATION="Bearer adm" \
    CONTENT_LENGTH="${#b}" TEAM_HOST_LOCK=0 bash "$ROUTER" <<<"$b" >/dev/null 2>&1; done
ck "t5 desclassificado À MÃO: sem a marca do lote" '[[ "$(dq t5)" == dq && "$(jq -r ".dq_batch // \"-\"" "$C/users/t5/account.json")" == - ]]'
call POST adm '{"action":"undo","batch":"lixo"}';            ck "lote mal formado: 400" '[[ "$(code)" == batch_invalid ]]'
call POST adm '{"action":"undo","batch":"adq0000000000"}';   ck "lote inexistente: 404" '[[ "$(code)" == batch_notfound ]]'
call POST adm "{\"action\":\"undo\",\"batch\":\"$BID\"}"
ck "desfaz: 3 voltam (t4 t7 t9), o t5 individual fica" '[[ "$(jq -r .restored <<<"$BODY")" == 3 && "$(dq t4)$(dq t7)$(dq t9)" == okokok && "$(dq t5)" == dq ]]'
ck "a marca do lote sai junto" '! grep -q dq_batch "$C/users/t4/account.json"'
ck "lote marcado como desfeito" '[[ "$(jq -r ".batches[0].undone_by" <<<"$BODY")" == ad.admin && "$(jq -r ".batches[0].undone_at" <<<"$BODY")" -gt 0 ]]'
call POST adm "{\"action\":\"undo\",\"batch\":\"$BID\"}";    ck "desfazer de novo: 409 batch_undone" '[[ "$(code)" == batch_undone ]]'
ck "t8 (desclassificado antes) nunca mexido" '[[ "$(dq t8)" == dq ]]'

echo "== prova rodando: vale, e a janela vai até agora =="
sed -i "s/^CONTEST_END=.*/CONTEST_END=$((NOW + 3600))/" "$C/conf"
call GET adm; to="$(jq -r .preview.window.to <<<"$BODY")"
ck "live:true e a janela termina agora" '[[ "$(jq -r .preview.live <<<"$BODY")" == true ]] && (( to >= NOW && to <= EPOCHSECONDS + 5 ))'

echo "== contest compartilhado (USERS_FROM): o participante sem account.json local ganha a camada local =="
SRC="$FIX/src"; mkdir -p "$SRC/var"; printf 'CONTEST_ID=src\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\n' > "$SRC/conf"
fx_user "$SRC" p1 x "Pessoa Um"; fx_user "$SRC" p2 x "Pessoa Dois"
SH="$FIX/sh"; mkdir -p "$SH/var" "$SH/users/p1" "$SH/users/p2"; : > "$SH/users/p1/history"; : > "$SH/users/p2/history"
{ printf 'CONTEST_ID=sh\nCONTEST_TYPE=icpc\nUSER_STORE=v2\nUSERS_FROM=src\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$ST" "$EN"; } > "$SH/conf"
fx_user "$SH" sh.admin p "Admin SH"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' sh sh.admin sh.admin "$NOW" > "$SESS/admsh"
printf '%s\tp2\t10.0.0.5\tx\n' $((ST + 30)) > "$SH/var/access.log"
callsh(){ local b="${2:-}"
  OUT="$(PATH_INFO=/contest/admin/absent-disqualify REQUEST_METHOD="$1" QUERY_STRING="contest=sh" HTTP_AUTHORIZATION="Bearer admsh" \
    CONTENT_LENGTH="${#b}" REMOTE_ADDR=127.0.0.9 TEAM_HOST_LOCK=0 bash "$ROUTER" <<<"$b" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
callsh GET
ck "candidato: só o p1 (o p2 logou)" '[[ "$(jq -r "[.preview.candidates[].login] | join(\",\")" <<<"$BODY")" == p1 ]]'
callsh POST "{\"action\":\"apply\",\"plan_id\":\"$(jq -r .preview.plan_id <<<"$BODY")\"}"
ck "aplica: a camada local do p1 nasce desclassificada, sem senha" \
   '[[ "$(jq -r .count <<<"$BODY")" == 1 && "$(jq -r ".disqualified, (.password // \"-\")" "$SH/users/p1/account.json" | tr "\n" " ")" == "true - " ]]'
ck "…a conta do p1 na fonte não muda" '! grep -q disqualified "$SRC/users/p1/account.json"'

echo; echo "RESULT: $pass passed, $fail failed"; (( fail == 0 ))
