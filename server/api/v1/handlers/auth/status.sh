# GET /auth/status[?contest=<id>]   (Bearer)
contest="$(param contest)"
if load_session; then
  if [[ -n "$contest" && "$SESSION_CONTEST" != "$contest" ]]; then
    ok_json '{logged_in:false, message:"not logged into this contest"}'; exit 0
  fi
  # `actor`/`is_team`: sessão de TIME (o membro entrou com a credencial dele e compete pelo
  # time) — o front mostra os dois nomes. Vazio/ausente = sessão comum.
  ok_json '{logged_in:true, login:$l, name:$n, contest:$c, is_admin:$a, is_judge:$j, is_staff:$s, is_cstaff:$cs, is_chief:$ch, is_animeitor:$an}
           + (if $ac == "" then {} else {actor:$ac, is_team:true} end)' \
    --arg l "$SESSION_LOGIN" --arg n "$SESSION_NAME" --arg c "$SESSION_CONTEST" \
    --arg ac "${SESSION_ACTOR:-}" \
    --argjson a "$(is_admin && echo true || echo false)" \
    --argjson j "$(is_judge && echo true || echo false)" \
    --argjson s "$(is_staff && echo true || echo false)" \
    --argjson cs "$(is_cstaff && echo true || echo false)" \
    --argjson ch "$(is_chief && echo true || echo false)" \
    --argjson an "$(is_animeitor && echo true || echo false)"
else
  ok_json '{logged_in:false}'
fi
