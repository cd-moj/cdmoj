# POST /auth/logout   (Bearer)
require_method POST
# apaga o arquivo MESMO se a sessão não vale mais (conta renomeada/removida, contest apagado):
# load_session preenche SESSION_TOKEN antes de qualquer validação, e um logout que não apaga
# deixaria o arquivo zumbi no store p/ sempre.
load_session || true
destroy_session "$SESSION_TOKEN"
ok_json '{logged_out:true}'
