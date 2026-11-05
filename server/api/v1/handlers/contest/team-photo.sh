# GET /contest/team-photo?contest=<id>&user=<login>[&thumb=1]   -> foto do time
# Público, inclusive em contest SECRETO (ver abaixo). O nginx serve a foto e a miniatura do DISCO antes de chegar aqui
# (moj-app.conf.in "MÍDIA DE TIME"); este handler responde o que cai nele — a foto PADRÃO, a miniatura que falta (e a
# gera), argumento estranho, host de outro contest — e o caminho sem nginx. Mesmo cache dos dois lados.
#   sem thumb  -> a foto (webp; png no acervo antigo) — é o que a galeria do telão e o painel Evento › Times abrem
#   &thumb=1   -> a MINIATURA de 320px (~7 KB), para a galeria do .animeitor
# TIME SEM FOTO **não dá mais 404**: devolve a FOTO PADRÃO do contest (200) com o cabeçalho
# `X-MOJ-Photo: placeholder`. É o que faz o Animeitor achar imagem para todo time do placar.
# Quem precisa saber quem MANDOU foto usa o `has_photo` das listagens (/contest/teams,
# /contest/animeitor/photos) — é lá que mora a verdade, e é o que a galeria do telão consulta.
# Cache da foto REAL: com `&v=<mtime>` (a galeria do telão) a URL é imutável; sem ele, miniatura 1 dia e foto 1 min (o
# telão externo busca sem `v`). A padrão troca quando o .animeitor quiser: sempre 1 min.
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
source "$_LIBDIR/team-photo.sh"

want_thumb="$(param thumb)"
if [[ -n "$want_thumb" ]]; then f="$(tp_thumb "$contest" "$quser")"; else f="$(tp_file "$contest" "$quser")"; fi
if [[ -n "$f" ]]; then
  ph=0; cc="public, max-age=60"; [[ -n "$want_thumb" ]] && cc="public, max-age=86400"
  [[ -n "$(param v)" ]] && cc="public, max-age=31536000, immutable"
else
  f="$(tp_placeholder "$contest" "$want_thumb")"; ph=1; cc="public, max-age=60"
fi
[[ -n "$f" ]] || fail 404 "Sem foto" "no_photo"      # nem padrão (instalação sem server/etc)

printf 'Status: 200 OK\r\nContent-Type: %s\r\nCache-Control: %s\r\n' "$(tp_ctype "$f")" "$cc"
(( ph )) && printf 'X-MOJ-Photo: placeholder\r\n'
printf '\r\n'
cat "$f"
