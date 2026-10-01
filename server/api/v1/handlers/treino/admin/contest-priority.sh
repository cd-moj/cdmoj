# POST /treino/admin/contest-priority  (SUPER-ADMIN do treino) — {contest, priority}
# A prioridade do contest no escalonador, inclusive SUPER (passa na frente de toda fila). O admin do contest muda
# entre as três de baixo em Central › Regras; Super é só daqui: a sessão é do TREINO (conta verificada) e o login
# tem de estar no SUPERADMINS do conf do treino. Grava + audita no contest e na trilha central do treino
# (lib/contest-create.sh cc_set_priority). -> {contest, priority, previous, changed}
require_method POST
require_auth_contest treino
is_superadmin || fail 403 "Apenas o super-admin do treino" "superadmin_required"
source "$_LIBDIR/contest-create.sh"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
c="$(jq -r '.contest // ""' <<<"$body")"; p="$(jq -r '.priority // ""' <<<"$body")"
{ [[ -n "$c" ]] && valid_id "$c" && [[ -f "$CONTESTSDIR/$c/conf" ]]; } || fail 404 "Contest não encontrado" "notfound"
cc_priority_ok "$p" || fail 422 "Prioridade inválida (lista-publica, lista-privada, prova ou super)" "priority_invalid"
cc_set_priority "$c" "$p" "painel-treino" || fail 500 "Falha ao gravar a prioridade" "priority_write"
ok_json '{contest:$c, priority:$p, previous:(if $o == "" then null else $o end), changed:($ch == "1")}' \
  --arg c "$c" --arg p "$p" --arg o "$CC_PRIO_OLD" --arg ch "$CC_PRIO_CHANGED"
