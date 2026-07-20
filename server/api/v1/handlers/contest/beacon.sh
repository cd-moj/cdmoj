# GET /contest/beacon?contest=<id>   (Bearer) — beacon de TEMPO assinado p/ a submissão
# offline do moj-comp. A CLI re-ancora a cada comando com rede: o beacon embutido no pacote
# offline prova que ele nasceu DEPOIS de .t (piso do carimbo). Ver lib/contest-offline.sh.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
[[ "$contest" != treino ]] || fail 400 "Beacon é de contest (não do treino)" "not_a_contest"

source "$_LIBDIR/contest-offline.sh"
b="$(offline_beacon "$contest" "$SESSION_LOGIN")" \
  || fail 500 "Beacon indisponível (openssl?)" "beacon_failed"
ok_json '{beacon:$b, server_utc:$t}' --arg b "$b" --argjson t "$EPOCHSECONDS"
