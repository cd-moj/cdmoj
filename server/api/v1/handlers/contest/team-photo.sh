# GET /contest/team-photo?contest=<id>&user=<login>[&thumb=1]   -> foto do time
# Gate = o do PLACAR (público; contest SECRETO exige sessão do contest).
#   sem thumb  -> a foto (webp; png no acervo antigo) — é o que a galeria do telão e o painel Pessoas › Times abrem
#   &thumb=1   -> a MINIATURA de 320px (~7 KB), para a galeria do .animeitor
# TIME SEM FOTO **não dá mais 404**: devolve a FOTO PADRÃO do contest (200) com o cabeçalho
# `X-MOJ-Photo: placeholder`. É o que faz o Animeitor achar imagem para todo time do placar.
# Quem precisa saber quem MANDOU foto usa o `has_photo` das listagens (/contest/teams,
# /contest/animeitor/photos) — é lá que mora a verdade, e é o que a galeria do telão consulta.
# O cliente manda `&v=<mtime>` na URL, então a foto real pode ter cache longo; a padrão troca
# quando o .animeitor quiser, por isso cache curto.
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
  ph=0; maxage=$([[ -n "$want_thumb" ]] && echo 86400 || echo 60)
else
  f="$(tp_placeholder "$contest" "$want_thumb")"; ph=1; maxage=60
fi
[[ -n "$f" ]] || fail 404 "Sem foto" "no_photo"      # nem padrão (instalação sem server/etc)

printf 'Status: 200 OK\r\nContent-Type: %s\r\nCache-Control: max-age=%s\r\n' "$(tp_ctype "$f")" "$maxage"
(( ph )) && printf 'X-MOJ-Photo: placeholder\r\n'
printf '\r\n'
cat "$f"
