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

# O `time` é carimbado POR REQUISIÇÃO (27/08/2026, pedido do Animeitor): o zip fica em cache
# pelo piso de idade, mas o relógio da prova não pode andar em SALTOS de WEBCAST_FLOOR_S — o
# telão anima o cronômetro com ele. Só a entrada `time` é refeita, numa CÓPIA por requisição
# (dois polls concorrentes nunca mexem no mesmo arquivo); o que é caro no pacote — runs e
# contest, a varredura do history — continua vindo do cache. Custo medido: ~ms num zip de
# dezenas de KB. A CONTA É A MESMA do webcast-gen.sh (segundos decorridos, negativo antes do
# início, teto em DUR*60) — mudou lá, muda aqui.
_ws="$(conf_value "$contest" CONTEST_START)"; [[ "$_ws" =~ ^[0-9]+$ ]] || _ws=0
_we="$(conf_value "$contest" CONTEST_END)";   [[ "$_we" =~ ^[0-9]+$ ]] || _we=0
_wdur=$(( (_we > _ws) ? (_we - _ws) / 60 : 0 ))
_tsec=$(( EPOCHSECONDS - _ws )); (( _tsec > _wdur * 60 )) && _tsec=$(( _wdur * 60 ))
_wd="$(mktemp -d 2>/dev/null)" || _wd=""
if [[ -n "$_wd" ]] && cp -f "$out" "$_wd/wc.zip" 2>/dev/null; then
  trap 'rm -rf "$_wd"' EXIT
  printf '%s' "$_tsec" > "$_wd/time"
  # zip indisponível/falhou? serve a cópia com o time do cache (degrada p/ o salto de 10s,
  # nunca p/ erro — o telão prefere um relógio grosseiro a nenhum pacote)
  ( cd "$_wd" && zip -q wc.zip time ) 2>/dev/null || true
  out="$_wd/wc.zip"
fi

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
