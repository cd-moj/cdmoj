# POST /auth/login?contest=<id>   body: {username, password}
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
u="$(jq -r '.username // empty' <<<"$body")"
p="$(jq -r '.password // empty' <<<"$body")"
[[ -n "$u" && -n "$p" ]] || fail 400 "Missing credentials" "creds_missing"

verify_password "$contest" "$u" "$p" || fail 401 "Wrong user or password" "bad_creds"

# Gate por substring de USERAGENT (configurável por contest). Lido com grep (sem
# sourcing do conf no caminho de auth). Papéis privilegiados (.admin/.judge/.cjudge/.staff/.cstaff/.mon)
# ficam isentos — para conseguirem entrar e configurar. Racional: o browser da máquina
# de prova manda um UA único; só quem tem aquele UA loga.
_ua_sub="$(grep -m1 '^LOGIN_UA_SUBSTRING=' "$CONTESTSDIR/$contest/conf" 2>/dev/null | cut -d= -f2-)"
_ua_sub="${_ua_sub%\'}"; _ua_sub="${_ua_sub#\'}"; _ua_sub="${_ua_sub%\"}"; _ua_sub="${_ua_sub#\"}"
if [[ -n "$_ua_sub" ]]; then
  case "$u" in
    *.admin|*.judge|*.cjudge|*.staff|*.cstaff|*.mon) ;;   # privilegiados isentos
    *) [[ "${HTTP_USER_AGENT:-}" == *"$_ua_sub"* ]] \
         || fail 403 "Login bloqueado: este navegador/máquina não está autorizado para o contest" "ua_gate" ;;
  esac
fi

name="$(user_fullname "$contest" "$u")"
tok="$(create_session "$contest" "$u" "$name")"
# log de acesso (tab-sep: epoch, login, ip, ua_b64)
mkdir -p "$CONTESTSDIR/$contest/var"
printf '%s\t%s\t%s\t%s\n' "$EPOCHSECONDS" "$u" "$(client_ip)" "$(printf '%s' "${HTTP_USER_AGENT:-}" | base64 -w0)" \
  >> "$CONTESTSDIR/$contest/var/access.log" 2>/dev/null || true
# Contest (≠ treino): a resposta leva o kit da submissão OFFLINE do moj-comp — hora do
# servidor (a CLI mede o desvio do relógio local), a chave PÚBLICA do contest e um beacon
# de tempo assinado (piso do carimbo offline). Ver lib/contest-offline.sh e docs/API.md.
# Falha de openssl degrada p/ a resposta clássica (offline indisponível, login normal).
if [[ "$contest" != treino ]]; then
  source "$_LIBDIR/contest-offline.sh"
  _opub=""; _obeacon=""
  _opubf="$(offline_ensure_keys "$contest" 2>/dev/null)" && _opub="$(cat "$_opubf" 2>/dev/null)"
  [[ -n "$_opub" ]] && _obeacon="$(SESSION_LOGIN="$u" offline_beacon "$contest" "$u" 2>/dev/null)"
  if [[ -n "$_opub" && -n "$_obeacon" ]]; then
    ok_json '{token:$t, logged_in:true, username:$u, name:$n, contest:$c,
              server_utc:$st, offline_pubkey_pem:$pk, beacon:$b}' \
      --arg t "$tok" --arg u "$u" --arg n "$name" --arg c "$contest" \
      --argjson st "$EPOCHSECONDS" --arg pk "$_opub" --arg b "$_obeacon"
    exit 0
  fi
fi
ok_json '{token:$t, logged_in:true, username:$u, name:$n, contest:$c, server_utc:$st}' \
  --arg t "$tok" --arg u "$u" --arg n "$name" --arg c "$contest" --argjson st "$EPOCHSECONDS"
