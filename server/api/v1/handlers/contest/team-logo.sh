# GET /contest/team-logo?contest=<id>&user=<login>   -> PNG do brasão do time (máx 128)
# Gate = o do PLACAR (público; contest SECRETO exige sessão do contest). 404 sem brasão.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
# ⚠ SEM GATE DE SECRETO, de propósito (2026-08-24). A mídia de time é PÚBLICA mesmo em contest
# `SECRET=1`: a foto e a música existem para ir ao TELÃO, e o telão é um sistema EXTERNO (o
# Animeitor) que busca sem sessão. Com o gate, ele não tinha saída — e nem o `<img>` do próprio
# MOJ, porque tag de mídia não manda `Authorization` (foi disso que nasceu o media-auth.js).
# O que o SECRET continua escondendo é o que importa: placar, diretório de times, teams-meta,
# balões e regiões — todos seguem sob `require_not_secret_or_auth`. Não devolva o gate aqui.
quser="$(param user)"
[[ -n "$quser" ]] || fail 400 "Missing user" "user_missing"
valid_id "$quser" || fail 400 "Invalid user" "user_invalid"
f="$(user_dir "$contest" "$quser")/logo.png"
[[ -f "$f" ]] || fail 404 "Sem brasão" "no_logo"
printf 'Status: 200 OK\r\nContent-Type: image/png\r\nCache-Control: max-age=60\r\n\r\n'
cat "$f"
