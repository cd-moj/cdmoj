# GET /contest/userinfo?contest=<id>   (Bearer)
# Dados do usuário logado: login, name e campos opcionais do conf (team/country/univ/show_log).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

# Toggles do conf: SHOWLOG/SHOWEDITOR default LIGADOS (só "0" desliga); SHOWCODE default desligado.
SHOWCODE=0; SHOWLOG=""; SHOWEDITOR=""
load_contest_conf "$contest"

# fullname canônico do passwd (cai p/ SESSION_NAME se vazio)
NAME="$(user_fullname "$contest" "$SESSION_LOGIN")"
[[ -n "$NAME" ]] || NAME="$SESSION_NAME"

show_log=true;    [[ "$SHOWLOG" == 0 ]] && show_log=false
show_editor=true; [[ "$SHOWEDITOR" == 0 ]] && show_editor=false
show_code=false;  [[ "${SHOWCODE:-0}" == 1 ]] && show_code=true

ok_json '{login:$l, name:$n, contest:$c, is_admin:$a, is_judge:$j, is_staff:$s, is_mon:$m, is_chief:$ch,
          show_log:$sl, show_code:$sc, show_editor:$se}' \
  --arg l "$SESSION_LOGIN" --arg n "$NAME" --arg c "$contest" \
  --argjson a "$(is_admin && echo true || echo false)" \
  --argjson j "$(is_judge && echo true || echo false)" \
  --argjson s "$(is_staff && echo true || echo false)" \
  --argjson m "$(is_mon && echo true || echo false)" \
  --argjson ch "$(is_chief && echo true || echo false)" \
  --argjson sl "$show_log" --argjson sc "$show_code" --argjson se "$show_editor"
