# GET /contest/placeholder?contest=<id>[&thumb=1][&kind=photo|music]  -> o PADRÃO do contest
# É o que a API devolve no lugar do asset de quem não mandou o seu:
#   kind=photo (padrão)  -> a FOTO padrão   (ver /contest/team-photo)
#   kind=music           -> a MÚSICA padrão (ver /contest/team-music)
# Pública, com o mesmo gate do placar — quem vê o placar vê o padrão.
# O `.animeitor` troca/reseta por /contest/animeitor/placeholder; sem escolha dele, vale o de
# fábrica do repo (server/etc/team-placeholder.webp | .mp3).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
# ⚠ SEM GATE DE SECRETO, de propósito (2026-08-24). A mídia de time é PÚBLICA mesmo em contest
# `SECRET=1`: a foto e a música existem para ir ao TELÃO, e o telão é um sistema EXTERNO (o
# Animeitor) que busca sem sessão. Com o gate, ele não tinha saída — e nem o `<img>` do próprio
# MOJ, porque tag de mídia não manda `Authorization` (foi disso que nasceu o media-auth.js).
# O que o SECRET continua escondendo é o que importa: placar, diretório de times, teams-meta,
# balões e regiões — todos seguem sob `require_not_secret_or_auth`. Não devolva o gate aqui.

if [[ "$(param kind)" == music ]]; then
  source "$_LIBDIR/team-music.sh"
  f="$(tm_placeholder "$contest")"
  [[ -n "$f" ]] || fail 404 "Sem música padrão" "no_placeholder"
  printf 'Status: 200 OK\r\nContent-Type: audio/mpeg\r\nContent-Length: %s\r\nAccept-Ranges: none\r\nCache-Control: max-age=60\r\nX-MOJ-Music: placeholder\r\n\r\n' \
    "$(stat -c %s "$f" 2>/dev/null || echo 0)"
  cat "$f"
  exit 0
fi

source "$_LIBDIR/team-photo.sh"
f="$(tp_placeholder "$contest" "$(param thumb)")"
[[ -n "$f" ]] || fail 404 "Sem foto padrão" "no_placeholder"
printf 'Status: 200 OK\r\nContent-Type: %s\r\nCache-Control: max-age=60\r\nX-MOJ-Photo: placeholder\r\n\r\n' \
  "$(tp_ctype "$f")"
cat "$f"
