# GET /ops/alerts   (AUTH: bot token — require_bot)
# Avalia as condições de incidente (throttled) e DRENA o outbox de alertas, devolvendo
# {items:[{id, text, chats:[<chat_id>...]}]} para o bot entregar. A API decide o quê/quando;
# o bot só envia (+ o grupo configurado, que ele adiciona). Efeito colateral idempotente
# (throttle por stamp): pode ser chamado com a frequência do poll do bot.
require_bot
# heartbeat do bot: mtime de bot.alive = último poll. É o que deixa a queda do CARTEIRO visível
# (/index/status + página /status/). E a detecção do período fora TEM de ser AQUI, antes do
# touch: o alerts_evaluate só roda no poll do bot — com o bot morto ninguém avalia nada, então
# a única chance de medir a ausência é o PRIMEIRO poll da volta, olhando o mtime velho.
# (Incidente 2026-08-04: reboot, unit sem enable, bot fora por horas e ninguém soube.)
mkdir -p "$RUNDIR/alerts" 2>/dev/null
_ba="$RUNDIR/alerts/bot.alive"
if [[ -f "$_ba" ]]; then
  _bage=$(( EPOCHSECONDS - $(stat -c %Y "$_ba" 2>/dev/null || echo 0) ))
  if (( _bage > ${ALERT_BOT_GONE_AFTER:-300} )); then
    ( umask 077; printf '⚠️ <b>MOJ</b>: o bot de alertas (mojinho) ficou FORA DO AR por ~%s min (desde %s) — alertas desse período podem ter se perdido. Voltou agora.' \
        "$(( _bage / 60 ))" "$(date -d "@$(( EPOCHSECONDS - _bage ))" '+%d/%m %H:%M' 2>/dev/null)" \
        > "$RUNDIR/alerts/outbox/$EPOCHSECONDS-bot_gone-$$.txt" 2>/dev/null ) || true
  fi
fi
touch "$_ba" 2>/dev/null || true
alerts_evaluate
items="$(alerts_claim)"
[[ -n "$items" ]] || items='[]'
ok_json '{items:$items}' --argjson items "$items"
