# GET /contest/placeholder?contest=<id>[&thumb=1]   -> a FOTO PADRÃO do contest
# É a imagem que a API devolve no lugar da foto de quem não mandou nenhuma (ver
# /contest/team-photo). Pública, com o mesmo gate do placar — quem vê o placar vê a padrão.
# O `.animeitor` troca/reseta por /contest/animeitor/placeholder; sem escolha dele, vale a de
# fábrica do repo (server/etc/team-placeholder.webp).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_not_secret_or_auth "$contest"
source "$_LIBDIR/team-photo.sh"

f="$(tp_placeholder "$contest" "$(param thumb)")"
[[ -n "$f" ]] || fail 404 "Sem foto padrão" "no_placeholder"
printf 'Status: 200 OK\r\nContent-Type: %s\r\nCache-Control: max-age=60\r\nX-MOJ-Photo: placeholder\r\n\r\n' \
  "$(tp_ctype "$f")"
cat "$f"
