# POST /treino/telegram/unlink   (Bearer — sessão do treino)
# Desvincula o Telegram do PRÓPRIO login (contraparte do link-start). O vínculo é 1:1
# (telegram_id imutável); desvincular libera o telegram_id p/ outra conta.
# GATE ANTI CONTA-DESCARTÁVEL: usuário comum desvincula no máx TELEGRAM_CHANGE_LIMIT (1)
# vez por ano — o vínculo é a identidade/prova de posse; sem o gate, desvincular+recadastrar
# vira fábrica de contas. Trocar de Telegram EXIGE desvincular (o verify recusa tgid já
# vinculado), então gatear o unlink cobre a troca. `.admin` é LIVRE (opera a plataforma).
# Histórico em account.json `.telegram_changes` (epochs — espelho do uname_changes).
require_method POST
require_auth_contest treino
[[ -n "$SESSION_LOGIN" ]] || fail 401 "Not authenticated" "auth_required"
tgid="$(tg_id_of_login treino "$SESSION_LOGIN" 2>/dev/null)"
[[ -n "$tgid" ]] || fail 404 "Nenhum Telegram vinculado a esta conta" "not_linked"
if ! is_admin; then
  changes="$(account_field treino "$SESSION_LOGIN" '(.telegram_changes // []) | map(tostring) | join(" ")')"
  used="$(uname_changes_recent "$changes")"   # helpers de cota são genéricos (epochs)
  if (( used >= TELEGRAM_CHANGE_LIMIT )); then
    nextav="$(uname_next_available "$changes")"
    whenstr="$(date -d "@$nextav" '+%d/%m/%Y' 2>/dev/null || echo '-')"
    fail 403 "O Telegram vinculado é a identidade da sua conta: só $TELEGRAM_CHANGE_LIMIT troca por ano. Próxima disponível em $whenstr." "telegram_limit"
  fi
fi
tg_unlink treino "$tgid" || fail 500 "Falha ao desvincular" "unlink_fail"
is_admin || account_merge treino "$SESSION_LOGIN" \
  '.telegram_changes = ((.telegram_changes // []) + [$t])' --argjson t "$EPOCHSECONDS"
audit_log "telegram-unlink" "login=$SESSION_LOGIN"
ok_json '{unlinked:true}'
