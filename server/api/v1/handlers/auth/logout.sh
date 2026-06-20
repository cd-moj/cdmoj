# POST /auth/logout   (Bearer)
require_method POST
if load_session; then destroy_session "$SESSION_TOKEN"; fi
ok_json '{logged_out:true}'
