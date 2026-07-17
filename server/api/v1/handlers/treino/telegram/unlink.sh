# POST /treino/telegram/unlink   (Bearer — sessão do treino)
# Desvincula o Telegram do PRÓPRIO login (contraparte do link-start). O vínculo é 1:1
# (telegram_id imutável); desvincular libera o telegram_id p/ outra conta. .admin que
# desvincula deixa de receber os alertas do bot.
require_method POST
require_auth_contest treino
[[ -n "$SESSION_LOGIN" ]] || fail 401 "Not authenticated" "auth_required"
tgid="$(tg_id_of_login treino "$SESSION_LOGIN" 2>/dev/null)"
[[ -n "$tgid" ]] || fail 404 "Nenhum Telegram vinculado a esta conta" "not_linked"
tg_unlink treino "$tgid" || fail 500 "Falha ao desvincular" "unlink_fail"
audit_log "telegram-unlink" "login=$SESSION_LOGIN"
ok_json '{unlinked:true}'
