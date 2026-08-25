# GET /auth/status[?contest=<id>]   (Bearer)
contest="$(param contest)"
if load_session; then
  if [[ -n "$contest" && "$SESSION_CONTEST" != "$contest" ]]; then
    ok_json '{logged_in:false, message:"not logged into this contest"}'; exit 0
  fi
  # `actor`/`is_team`: sessão de TIME (o membro entrou com a credencial dele e compete pelo
  # time) — o front mostra os dois nomes. Vazio/ausente = sessão comum.
  # has_photo: o avatar do cabeçalho aparece em TODA página. Sem este campo o front pedia a foto
  # e caía nas iniciais pelo erro — 5.712 respostas 404 no dia 24/08/2026 (54% de TODOS os 404 do
  # dia), cada uma um fork de bash sob fcgiwrap. O `avatarEl` já sabe pular a requisição quando
  # recebe `hasPhoto:false`; o que faltava era o servidor dizer. Custo aqui: um teste de arquivo.
  ok_json '{logged_in:true, login:$l, name:$n, contest:$c, is_admin:$a, is_judge:$j, is_staff:$s, is_cstaff:$cs, is_chief:$ch, is_animeitor:$an, has_photo:$hp}
           + (if $ac == "" then {} else {actor:$ac, is_team:true} end)' \
    --arg l "$SESSION_LOGIN" --arg n "$SESSION_NAME" --arg c "$SESSION_CONTEST" \
    --arg ac "${SESSION_ACTOR:-}" \
    --argjson hp "$([[ -f "$(photo_file treino "$SESSION_LOGIN")" ]] && echo true || echo false)" \
    --argjson a "$(is_admin && echo true || echo false)" \
    --argjson j "$(is_judge && echo true || echo false)" \
    --argjson s "$(is_staff && echo true || echo false)" \
    --argjson cs "$(is_cstaff && echo true || echo false)" \
    --argjson ch "$(is_chief && echo true || echo false)" \
    --argjson an "$(is_animeitor && echo true || echo false)"
else
  ok_json '{logged_in:false}'
fi
