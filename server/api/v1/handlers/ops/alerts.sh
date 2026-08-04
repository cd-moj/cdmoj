# GET /ops/alerts   (AUTH: bot token — require_bot)
# Avalia as condições de incidente (throttled) e DRENA o outbox de alertas, devolvendo
# {items:[{id, text, chats:[<chat_id>...]}]} para o bot entregar. A API decide o quê/quando;
# o bot só envia (+ o grupo configurado, que ele adiciona). Efeito colateral idempotente
# (throttle por stamp): pode ser chamado com a frequência do poll do bot.
require_bot
# heartbeat do bot: mtime = último poll. É o que deixa a queda do CARTEIRO visível — o /status
# e o /index/status mostram, e alerts_evaluate (bot_gone) avisa os admins quando ele VOLTA.
mkdir -p "$RUNDIR/alerts" 2>/dev/null; touch "$RUNDIR/alerts/bot.alive" 2>/dev/null || true
alerts_evaluate
items="$(alerts_claim)"
[[ -n "$items" ]] || items='[]'
ok_json '{items:$items}' --argjson items "$items"
