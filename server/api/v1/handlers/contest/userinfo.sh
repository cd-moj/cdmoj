# GET /contest/userinfo?contest=<id>   (Bearer)
# Dados do usuário logado: login, name e campos opcionais do conf (team/country/univ/show_log).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

# Campos opcionais: SHOWCODE/SHOWLOG do conf controlam show_log/show_code.
SHOWCODE=0; SHOWLOG=0
load_contest_conf "$contest"

# fullname canônico do passwd (cai p/ SESSION_NAME se vazio)
NAME="$(user_fullname "$contest" "$SESSION_LOGIN")"
[[ -n "$NAME" ]] || NAME="$SESSION_NAME"

show_log=false
[[ "${SHOWLOG:-0}" == 1 || "${SHOWCODE:-0}" == 1 ]] && show_log=true

ok_json '{login:$l, name:$n, contest:$c, is_admin:$a, is_judge:$j, is_staff:$s, show_log:$sl}' \
  --arg l "$SESSION_LOGIN" --arg n "$NAME" --arg c "$contest" \
  --argjson a "$(is_admin && echo true || echo false)" \
  --argjson j "$(is_judge && echo true || echo false)" \
  --argjson s "$(is_staff && echo true || echo false)" \
  --argjson sl "$show_log"
