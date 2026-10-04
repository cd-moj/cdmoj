#!/bin/bash
# Prova › Problemas — o que a auditoria do painel (03/10/2026) pegou dando falsa impressão:
#   - "+ adicionar todos" = um POST por problema, todos de uma vez: sem trava, só 1 ficava (todos 200);
#   - reordenar com letras AUTOMÁTICAS troca as letras: a cor do balão e as clarifications (chaveadas pela LETRA)
#     ficavam no problema errado;
#   - "Atualizar do banco" apagava o enunciado e reindexava em background (corrida + pacote que não reindexa = nada).
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$HERE/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN"; mkdir -p "$RUN/tl"
NOW="$EPOCHSECONDS"; T="$FIX/treino"; mkdir -p "$T/var/jsons"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\n' > "$T/conf"
ids=(); for i in 1 2 3 4 5 6 7 8 9; do
  printf '{"id":"o#p%s","title":"P%s","public":true,"statement_html_b64":"%s"}' "$i" "$i" "$(printf '<p>P%s</p>' "$i" | base64 -w0)" > "$T/var/jsons/o#p$i.json"
  ids+=("o#p$i"); done
fx_owners_index "$FIX" "${ids[@]}"
C="$FIX/po"; mkdir -p "$C/var" "$C/enunciados" "$C/clarifications"
{ printf 'CONTEST_ID=po\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW-60))" "$((NOW+3600))"
  printf "PROBS=( cdmoj 'o#p1' P1 A 'o#p1' cdmoj 'o#p2' P2 B 'o#p2' cdmoj 'o#p3' P3 C 'o#p3' )\n"; } > "$C/conf"
fx_user "$C" po.admin p Admin; printf 'CONTEST=po\nLOGIN=po.admin\nUSERFULLNAME=A\nLOGINAT=1\n' > "$SESS/adm"
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="contest=po" HTTP_AUTHORIZATION="Bearer adm" bash "$ROUTER" <<<"${3:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:240}"; ((fail++)); fi; }
letters(){ ( PROBS=(); source "$C/conf"; for ((i=0; i+4<${#PROBS[@]}; i+=5)); do printf '%s=%s ' "${PROBS[i+4]}" "${PROBS[i+3]}"; done ); }

echo "== reordenar com letras automáticas: cor de balão e clarification acompanham o problema =="
printf '{"A":"FF0000","B":"00FF00","C":"0000FF","enableSonic":true}' > "$C/balloons.json"
printf '{"id":"q1","time":1,"problem":"B","login":"t","question":"?","public":false,"answer":"","answered_by":"","answered_at":0}' > "$C/clarifications/q1.json"
call /contest/admin/problems POST '{"action":"reorder","order":["C","A","B"]}'
ck "letras re-atribuídas pela posição (p3=A p1=B p2=C)" '[[ "$(letters)" == "o#p3=A o#p1=B o#p2=C " ]]'
ck "cores seguem o problema (A=azul do p3, B=vermelho do p1, C=verde do p2) e o resto fica" '[[ "$(jq -cS . "$C/balloons.json")" == "{\"A\":\"0000FF\",\"B\":\"FF0000\",\"C\":\"00FF00\",\"enableSonic\":true}" ]]'
ck "clarification do p2 (era B) agora aponta p/ C" '[[ "$(jq -r .problem "$C/clarifications/q1.json")" == C ]]'
ck "auditado" 'grep -q "problems-reletter" "$C/var/admin-audit.log"'
call /contest/admin/problems GET
ck "GET traz a fase (a tela confirma o reordenar com a prova no ar)" '[[ "$(jq -r .phase <<<"$BODY")" == running ]]'

echo "== adicionar vários AO MESMO TEMPO (o + adicionar todos): nenhum se perde =="
for i in 4 5 6 7 8 9; do
  ( PATH_INFO=/contest/admin/problems REQUEST_METHOD=POST QUERY_STRING=contest=po HTTP_AUTHORIZATION="Bearer adm" \
      bash "$ROUTER" <<<"{\"action\":\"add\",\"problem\":{\"bank_id\":\"o#p$i\"}}" >/dev/null 2>&1 ) &
done; wait
ck "9 problemas depois de 6 adições paralelas (eram perdidas)" '( PROBS=(); source "$C/conf"; (( ${#PROBS[@]} == 45 )) )'
ck "letras únicas" '[[ "$(letters | tr " " "\n" | sed "/^$/d" | cut -d= -f2 | sort | uniq -d)" == "" ]]'

echo "== Balões: trocar a cor passa as tarefas NÃO impressas à cor nova; as impressas são avisadas =="
mkdir -p "$C/print-requests"
printf '{"id":"b1","kind":"balloon","short":"A","color_hex":"0000FF","color_name":"azul","status":"pending"}' > "$C/print-requests/b1.json"
printf 'PDF-velho' > "$C/print-requests/b1.combined.pdf"
printf '{"id":"b2","kind":"balloon","short":"B","color_hex":"FF0000","color_name":"vermelho","status":"printed"}' > "$C/print-requests/b2.json"
printf '{"id":"b3","kind":"balloon","short":"C","color_hex":"00FF00","color_name":"verde","status":"delivered"}' > "$C/print-requests/b3.json"
call /contest/admin/config POST '{"colors":{"A":"FFFF00","B":"FFFF00","C":"FFFF00","enableSonic":false}}'
ck "1 pendente recolorida, 1 impressa avisada (a entregue não conta)" '[[ "$(jq -r .balloons_recolored <<<"$BODY")" == 1 && "$(jq -r .balloons_printed_old <<<"$BODY")" == 1 ]]'
ck "a pendente tem a cor nova e o PDF em cache foi descartado" '[[ "$(jq -r .color_hex "$C/print-requests/b1.json")" == FFFF00 && "$(jq -r .color_name "$C/print-requests/b1.json")" != azul && ! -e "$C/print-requests/b1.combined.pdf" ]]'
ck "a impressa fica como estava" '[[ "$(jq -r .color_hex "$C/print-requests/b2.json")" == FF0000 ]]'
call /contest/admin/config POST '{"colors":null}'
ck "cores padrão: a pendente volta à paleta ICPC (A=FFFFFF)" '[[ "$(jq -r .color_hex "$C/print-requests/b1.json")" == FFFFFF && "$(jq -r .balloons_recolored <<<"$BODY")" == 1 ]]'

echo; echo "RESULT: $pass passed, $fail failed"; (( fail == 0 ))
