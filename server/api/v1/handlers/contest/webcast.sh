# GET /contest/webcast?contest=<id>&key=<chave>   -> ZIP do placar (protocolo do Animeitor)
#
# ROTA SEM SESSÃO, de propósito: é o sistema Animeitor buscando em loop (o BOCA faz igual —
# o `webcast.php` pula o ValidSession quando vem `webcastcode`). Quem autoriza é a CHAVE, que
# o .animeitor cria em /contest/animeitor/webcast e que declara a VISÃO de placar servida.
# Formato do pacote: server/score/webcast-gen.sh + docs/WEBCAST.md.
#
# Chave inválida/revogada -> 404 (não confirma sequer que o contest existe).
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 404 "Not found" "notfound"
valid_id "$contest" || fail 404 "Not found" "notfound"
key="$(param key)"
[[ -n "$key" ]] || fail 404 "Not found" "notfound"

source "$_LIBDIR/webcast.sh"
ip="${HTTP_X_REAL_IP:-${REMOTE_ADDR:-}}"
[[ -d "$CONTESTSDIR/$contest" ]] || { wc_deny_log "$contest" "$key" "$ip"; fail 404 "Not found" "notfound"; }
view="$(wc_lookup "$contest" "$key")" || { wc_deny_log "$contest" "$key" "$ip"; fail 404 "Not found" "notfound"; }

vsafe="$(printf '%s' "$view" | tr -cd 'A-Za-z0-9_-')"; [[ -n "$vsafe" ]] || vsafe=public
out="$CONTESTSDIR/$contest/var/webcast-$vsafe.zip"
mkdir -p "$CONTESTSDIR/$contest/var" 2>/dev/null

# Cache com PISO DE IDADE (não é o regen_locked de sempre, que só regenera quando uma FONTE
# ficou mais nova): aqui o pacote tem de envelhecer sozinho, porque o arquivo `time` é o
# relógio da prova e precisa andar mesmo sem submissão nova. O Animeitor bate de segundos em
# segundos — sem o piso, cada poll refaria o zip; com ele, a maioria dos polls é `cat`.
: "${WEBCAST_FLOOR_S:=10}"
_wc_fresh(){ [[ -s "$out" ]] && [[ -n "$(find "$out" -newermt "-$WEBCAST_FLOOR_S seconds" 2>/dev/null)" ]]; }
if ! _wc_fresh; then
  ( flock -w 8 9 || exit 0
    _wc_fresh && exit 0                      # outro processo acabou de gerar
    if bash "$SCOREDIR/webcast-gen.sh" "$contest" "$view" "$out.tmp" >/dev/null 2>&1; then
      mv -f "$out.tmp" "$out"                # publica inteiro (nunca zip pela metade)
    else rm -f "$out.tmp"; fi
  ) 9>"$CONTESTSDIR/$contest/var/.webcast-$vsafe.lock" 2>/dev/null
fi
[[ -s "$out" ]] || fail 503 "Pacote indisponível" "webcast_unavailable"

wc_touch "$contest" "$key" "$ip"

# Content-Length explícito (arquivo pronto): o cliente do Animeitor não precisa lidar com
# resposta sem tamanho. O BOCA manda application/force-download; aqui é o tipo de verdade.
printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/zip\r\n'
printf 'Content-Length: %s\r\n' "$(stat -c %s "$out" 2>/dev/null || echo 0)"
printf 'Content-Disposition: attachment; filename="webcast-%s.zip"\r\n' "$vsafe"
printf 'Cache-Control: no-store\r\n'
printf '\r\n'
cat "$out"
