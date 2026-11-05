# GET /contest/team-music?contest=<id>&user=<login>   -> a MÚSICA do time (audio/mpeg)
# Público, inclusive em contest SECRETO (ver abaixo), igual ao /contest/team-photo. O nginx serve a música do DISCO antes de
# chegar aqui (moj-app.conf.in "MÍDIA DE TIME", com Range/206); este handler responde o que cai nele — a música PADRÃO,
# argumento estranho, host de outro contest — e o caminho sem nginx. Mesmo cache dos dois lados: a música real com
# `&v=<mtime>` (a galeria do telão) é imutável; sem ele (o telão externo) e a padrão, 1 min.
# TIME SEM MÚSICA não dá 404: devolve a MÚSICA PADRÃO do contest (200) com o cabeçalho
# `X-MOJ-Music: placeholder` — é o que faz o Animeitor ter faixa para todo time do placar.
# Quem precisa saber quem MANDOU a sua usa o `has_music` das listagens.
# Sem suporte a Range AQUI (a API não tem em lugar nenhum; o nginx tem): o player toca progressivo, que é o uso
# aqui (tocar do começo quando o time resolve). Mandamos Content-Length para o cliente saber o
# tamanho e conseguir mostrar a duração.
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
source "$_LIBDIR/team-music.sh"

f="$(tm_file "$contest" "$quser")"
cc="public, max-age=60"
if [[ -n "$f" ]]; then ph=0; [[ -n "$(param v)" ]] && cc="public, max-age=31536000, immutable"
else f="$(tm_placeholder "$contest")"; ph=1; fi
[[ -n "$f" ]] || fail 404 "Sem música" "no_music"   # nem padrão (instalação sem server/etc)

printf 'Status: 200 OK\r\nContent-Type: audio/mpeg\r\nContent-Length: %s\r\nAccept-Ranges: none\r\nCache-Control: %s\r\n' \
  "$(stat -c %s "$f" 2>/dev/null || echo 0)" "$cc"
(( ph )) && printf 'X-MOJ-Music: placeholder\r\n'
printf '\r\n'
cat "$f"
