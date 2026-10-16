#!/bin/bash
# smoke-treino-admin-guard.sh — AS GUARDAS DO PAINEL DO TREINO (16/10/2026). Um .admin comum deslogou 1.310 contas de
# uma vez — ele mesmo, o super-admin e os outros .admin no meio — e as /ops aceitavam o .admin LOCAL de qualquer
# contest. Prende (lib/admin-bulk.sh, lib/auth.sh require_treino_admin/require_treino_superadmin):
#   · deslogar: 1 alvo executa direto; 2..20 só com a PRÉVIA (plan_id) + o número; 21+ só o super; teto 5000;
#     a própria conta, conta de papel e super-admin NUNCA entram (skipped, com motivo); confirm errado e plan_id de
#     outra lista = 409; folga do número acima de 20 contas (sessões que caem entre a prévia e o executar);
#   · travar e deslogar por IP: só o super, sempre com a prévia;
#   · o aviso vai p/ o outbox do mojinho (DM ao super com Telegram vinculado) e o detalhe p/ var/admin-actions/;
#   · /ops de escrita só o super do treino; /ops de leitura só admin COM SESSÃO DO TREINO (o .admin local de outro
#     contest leva 403); agir na Fila só o super.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN"
T="$FIX/treino"; mkdir -p "$T/var" "$FIX/outro/var" "$RUN/secrets" "$RUN/registry" "$RUN/alerts/outbox"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nSUPERADMINS=sup.admin\n' > "$T/conf"
printf 'CONTEST_ID=outro\nCONTEST_TYPE=icpc\n' > "$FIX/outro/conf"
fx_user "$T" adm.admin s "Admin Comum" >/dev/null; fx_user "$T" sup.admin s "Super" >/dev/null
fx_user "$T" outro.admin s "Outro Admin" >/dev/null; fx_user "$T" juiz.judge s "Juiz" >/dev/null
for i in $(seq -w 1 30); do fx_user "$T" "al$i" s "Aluno $i" >/dev/null; done
fx_user "$FIX/outro" chefe.admin s "Admin local" >/dev/null
mkdir -p "$T/var/telegram/by-login"; printf '777001\n' > "$T/var/telegram/by-login/sup.admin"   # o super tem Telegram
NOW="$EPOCHSECONDS"
ses(){ printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\nIP=%q\nUA_B64=\nMKEY=\n' "$2" "$3" "$3" "$NOW" "${4:-1.2.3.4}" > "$SESS/$1"; }
ses tk-adm treino adm.admin; ses tk-sup treino sup.admin; ses tk-loc outro chefe.admin
reset_ses(){ local i; for i in $(seq -w 1 30); do ses "s$i" treino "al$i"; done
             ses s-adm2 treino adm.admin; ses s-sup2 treino sup.admin; ses s-oa treino outro.admin; ses s-jz treino juiz.judge; }
call(){ # <rota> <método> <token> [corpo]
  OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="contest=treino" HTTP_AUTHORIZATION="Bearer $3" REMOTE_ADDR=198.51.100.9 \
        bash "$ROUTER" <<<"${4:-}" 2>/dev/null)"
  CODE="$(sed -n 's/^Status: \([0-9]*\).*/\1/p' <<<"$OUT" | head -1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: $CODE ${BODY:0:240}"; ((fail++)); fi; }
has(){ [[ -f "$SESS/$1" ]]; }
logins(){ local a=() i; for i in "$@"; do a+=("al$i"); done; printf '%s\n' "${a[@]}" | jq -R . | jq -cs '{logins:.}'; }
withplan(){ jq -c --arg p "$(jq -r .plan_id <<<"$BODY")" --argjson n "${2:-$(jq -r .need <<<"$BODY")}" '. + {plan_id:$p, confirm:$n}' <<<"$1"; }

echo "== deslogar: a escada 1 / 2..20 / 21+"
reset_ses
call /treino/admin/logout-user POST tk-adm '{"login":"al01"}'
ck "1 alvo: executa direto (admin comum)" '[[ "$CODE" == 200 ]] && [[ "$(jq -r .sessions_removed <<<"$BODY")" == 1 ]] && ! has s01'
B="$(logins 02 03 04)"; call /treino/admin/logout-user POST tk-adm "$B"
ck "3 alvos sem plan_id: só a PRÉVIA, nada cai" '[[ "$CODE" == 200 && "$(jq -r .preview <<<"$BODY")" == true && "$(jq -r .need <<<"$BODY")" == 3 ]] && has s02 && has s04'
PV="$BODY"
call /treino/admin/logout-user POST tk-adm "$(BODY="$PV"; withplan "$B" 2)"
ck "número errado: 409 confirm_required com o need" '[[ "$CODE" == 409 ]] && grep -q confirm_required <<<"$BODY" && [[ "$(jq -r .error.need <<<"$BODY")" == 3 ]] && has s02'
call /treino/admin/logout-user POST tk-adm "$(BODY="$PV"; withplan "$(logins 02 03 05)" 3)"
ck "plan_id de outra lista: 409 plan_changed com a prévia nova" '[[ "$CODE" == 409 ]] && grep -q plan_changed <<<"$BODY" && [[ "$(jq -r .error.preview.plan_id <<<"$BODY")" != null ]]'
call /treino/admin/logout-user POST tk-adm "$(BODY="$PV"; withplan "$B")"
ck "prévia + número certo: as 3 caem" '[[ "$CODE" == 200 && "$(jq -r .users_count <<<"$BODY")" == 3 ]] && ! has s02 && ! has s03 && ! has s04 && has s05'
ck "detalhe gravado em var/admin-actions/ e citado no audit" '[[ -f "$T/var/$(jq -r .detail <<<"$BODY")" ]] && grep -q "logout-user	afetados=3 sessoes=3" "$T/var/admin-audit.log"'
DET="$(jq -r .detail <<<"$BODY")"; DET="${DET#admin-actions/}"
OUT="$(PATH_INFO=/treino/admin/action-detail REQUEST_METHOD=GET QUERY_STRING="contest=treino&f=$DET" HTTP_AUTHORIZATION="Bearer tk-adm" bash "$ROUTER" 2>/dev/null)"
ck "action-detail devolve quem foi afetado" '[[ "$(printf "%s" "$OUT" | awk "f{print} /^\r?$/{f=1}" | jq -c ".detail.affected|sort")" == "[\"al02\",\"al03\",\"al04\"]" ]]'
OUT="$(PATH_INFO=/treino/admin/action-detail REQUEST_METHOD=GET QUERY_STRING="contest=treino&f=../../conf" HTTP_AUTHORIZATION="Bearer tk-adm" bash "$ROUTER" 2>/dev/null)"
ck "action-detail recusa nome fora do padrão (400)" '[[ "$OUT" == *"Status: 400"* ]]'
OUT="$(PATH_INFO=/treino/admin/action-detail REQUEST_METHOD=GET QUERY_STRING="contest=treino&f=$DET" HTTP_AUTHORIZATION="Bearer s05" bash "$ROUTER" 2>/dev/null)"
ck "action-detail p/ aluno: 403 (a lista de afetados é do admin)" '[[ "$OUT" == *"Status: 403"* ]]'
OUT="$(PATH_INFO=/treino/admin/action-detail REQUEST_METHOD=GET QUERY_STRING="contest=treino&f=$DET" HTTP_AUTHORIZATION="Bearer tk-loc" bash "$ROUTER" 2>/dev/null)"
ck "action-detail p/ .admin LOCAL de outro contest: recusa" '[[ "$OUT" == *"Status: 40"[13]* ]]'
ck "aviso no outbox do mojinho: DM ao super (Telegram vinculado)" 'grep -l "777001" "$RUN"/alerts/outbox/*.json 2>/dev/null | xargs -r grep -l "deslogou" | grep -q .'
call /treino/admin/logout-user POST tk-adm "$(logins $(seq -w 1 21))"
ck "21 alvos p/ admin comum: 403 bulk_superadmin_only" '[[ "$CODE" == 403 ]] && grep -q bulk_superadmin_only <<<"$BODY"'

echo "== quem NUNCA entra"
reset_ses
call /treino/admin/logout-user POST tk-adm '{"logins":["adm.admin","sup.admin","outro.admin","juiz.judge","al10","al11"]}'
ck "prévia: a própria, o super e os de papel saem em skipped com o motivo" \
   '[[ "$(jq -r .need <<<"$BODY")" == 2 && "$(jq -r ".skipped_by_reason.self, .skipped_by_reason.superadmin, .skipped_by_reason.role" <<<"$BODY" | tr "\n" ,)" == "1,1,2," ]]'
call /treino/admin/logout-user POST tk-adm "$(withplan '{"logins":["adm.admin","sup.admin","outro.admin","juiz.judge","al10","al11"]}')"
ck "executa só nos 2 alunos; admin, super e juiz seguem logados" '[[ "$CODE" == 200 ]] && ! has s10 && ! has s11 && has s-adm2 && has s-sup2 && has s-oa && has s-jz'
call /treino/admin/logout-user POST tk-adm '{"logins":["adm.admin","juiz.judge"]}'
ck "só contas protegidas: 422 no_targets" '[[ "$CODE" == 422 ]] && grep -q no_targets <<<"$BODY"'
call /treino/admin/logout-user POST tk-adm '{"login":"adm.admin"}'
ck "deslogar a si mesmo, 1 alvo: 422 (nem o atalho de 1 alvo derruba a própria)" '[[ "$CODE" == 422 ]] && has tk-adm'

echo "== o super: lote grande, folga do número, teto"
reset_ses
B="$(logins $(seq -w 1 30))"; call /treino/admin/logout-user POST tk-sup "$B"
ck "30 alvos: prévia p/ o super (need 30)" '[[ "$CODE" == 200 && "$(jq -r .need <<<"$BODY")" == 30 ]]'
PV="$BODY"; rm -f "$SESS/s01" "$SESS/s02"         # dois alunos saem entre a prévia e o executar
call /treino/admin/logout-user POST tk-sup "$(BODY="$PV"; withplan "$B" 30)"
ck "folga: digitou 30, agora são 28 — executa (±5 acima de 20 contas)" '[[ "$CODE" == 200 && "$(jq -r .users_count <<<"$BODY")" == 28 ]]'
reset_ses; call /treino/admin/logout-user POST tk-sup "$B"; PV="$BODY"
call /treino/admin/logout-user POST tk-sup "$(BODY="$PV"; withplan "$B" 3)"
ck "o 'achei que eram 3': 409 com o need real" '[[ "$CODE" == 409 && "$(jq -r .error.need <<<"$BODY")" == 30 ]] && has s05'
BIG="$(seq 1 5001 | sed 's/^/u/' | jq -R . | jq -cs '{logins:.}')"
call /treino/admin/logout-user POST tk-sup "$BIG"
ck "5001 alvos: 422 bulk_too_big (teto por chamada)" '[[ "$CODE" == 422 ]] && grep -q bulk_too_big <<<"$BODY"'

echo "== travar e deslogar por IP: só o super, sempre com prévia"
reset_ses
call /treino/admin/lock-user POST tk-adm '{"login":"al12"}'
ck "travar p/ admin comum: 403 superadmin_required" '[[ "$CODE" == 403 ]] && grep -q superadmin_required <<<"$BODY"'
call /treino/admin/lock-user POST tk-sup '{"logins":["al12","sup.admin"]}'
ck "travar p/ o super: prévia mesmo p/ 1 conta, sem o próprio" '[[ "$(jq -r .preview <<<"$BODY")" == true && "$(jq -r .need <<<"$BODY")" == 1 && "$(jq -r .skipped_by_reason.self <<<"$BODY")" == 1 ]]'
call /treino/admin/lock-user POST tk-sup "$(withplan '{"logins":["al12","sup.admin"]}')"
ck "trava al12 (senha trocada, sessão cai); o super segue" '[[ "$CODE" == 200 && "$(jq -r .users_count <<<"$BODY")" == 1 ]] && ! has s12 && has tk-sup && [[ "$(jq -r .password "$T/users/al12/account.json")" != s ]]'
call /treino/admin/lock-user POST tk-sup '{"logins":["sup.admin","juiz.judge"]}'
ck "travar só protegidas: 422 no_targets (não 404)" '[[ "$CODE" == 422 ]] && grep -q no_targets <<<"$BODY"'
call /treino/admin/lock-user POST tk-sup '{"login":"naoexiste"}'
ck "travar conta inexistente: 404 user_notfound" '[[ "$CODE" == 404 ]] && grep -q user_notfound <<<"$BODY"'
ses i1 treino al13 10.9.9.9; ses i2 treino al14 10.9.9.9; ses i3 treino adm.admin 10.9.9.9; ses i4 outro al13 10.9.9.9
call /treino/admin/logout-ip POST tk-adm '{"ip":"10.9.9.9"}'
ck "deslogar por IP p/ admin comum: 403" '[[ "$CODE" == 403 ]]'
call /treino/admin/logout-ip POST tk-sup '{"ip":"10.9.9.9"}'
ck "por IP: prévia = os 2 alunos; o admin naquele IP fica de fora" '[[ "$(jq -r .need <<<"$BODY")" == 2 && "$(jq -r .skipped_by_reason.role <<<"$BODY")" == 1 ]]'
call /treino/admin/logout-ip POST tk-sup "$(withplan '{"ip":"10.9.9.9"}')"
ck "por IP: caem os 2 do treino; o admin e a sessão de outro contest ficam" '[[ "$CODE" == 200 ]] && ! has i1 && ! has i2 && has i3 && has i4'

echo "== /ops e Fila"
call /ops/judge-config GET tk-loc
ck "admin LOCAL de outro contest: /ops de leitura = 403" '[[ "$CODE" == 403 ]]'
for r in judge-reset judge-cache calib-cancel updateproblemset; do
  call "/ops/$r" POST tk-loc '{"host":"j1","id":"a#b","repo":"a"}'
  ck "admin LOCAL de outro contest: /ops/$r = 403" '[[ "$CODE" == 403 ]]'
  call "/ops/$r" POST tk-adm '{"host":"j1","id":"a#b","repo":"a"}'
  ck "admin comum do treino: /ops/$r = 403 superadmin_required" '[[ "$CODE" == 403 ]] && grep -q superadmin_required <<<"$BODY"'
done
call /ops/judge-config GET tk-adm
ck "admin comum do treino LÊ a config dos juízes (200)" '[[ "$CODE" == 200 ]]'
call /ops/judge-config POST tk-adm '{"host":"j1","reserve":1}'
ck "admin comum não GRAVA a config (403)" '[[ "$CODE" == 403 ]]'
call /treino/admin/queue POST tk-adm '{"action":"resolve","contest":"treino","login":"al01","id":"0123456789abcdef0123456789abcdef"}'
ck "agir na Fila: admin comum = 403" '[[ "$CODE" == 403 ]] && grep -q superadmin_required <<<"$BODY"'
call /treino/admin/queue POST tk-sup '{"action":"resolve","contest":"treino","login":"al01","id":"0123456789abcdef0123456789abcdef"}'
ck "agir na Fila: o super passa do portão (404: a submissão não existe)" '[[ "$CODE" == 404 ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
