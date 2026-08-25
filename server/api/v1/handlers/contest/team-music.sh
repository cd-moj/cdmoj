# GET /contest/team-music?contest=<id>&user=<login>   -> a MÚSICA do time (audio/mpeg)
# Gate = o do PLACAR (público; contest SECRETO exige sessão do contest), igual ao /contest/team-photo.
# TIME SEM MÚSICA não dá 404: devolve a MÚSICA PADRÃO do contest (200) com o cabeçalho
# `X-MOJ-Music: placeholder` — é o que faz o Animeitor ter faixa para todo time do placar.
# Quem precisa saber quem MANDOU a sua usa o `has_music` das listagens.
# Sem suporte a Range (a API não tem em lugar nenhum): o player toca progressivo, que é o uso
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
if [[ -n "$f" ]]; then ph=0; else f="$(tm_placeholder "$contest")"; ph=1; fi
[[ -n "$f" ]] || fail 404 "Sem música" "no_music"   # nem padrão (instalação sem server/etc)

printf 'Status: 200 OK\r\nContent-Type: audio/mpeg\r\nContent-Length: %s\r\nAccept-Ranges: none\r\nCache-Control: max-age=60\r\n' \
  "$(stat -c %s "$f" 2>/dev/null || echo 0)"
(( ph )) && printf 'X-MOJ-Music: placeholder\r\n'
printf '\r\n'
cat "$f"
