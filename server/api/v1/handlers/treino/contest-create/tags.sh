# GET /treino/contest-create/tags  (auth treino, pode criar) -> tags do banco com contagem
require_method GET
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar contest" "create_forbidden"
emit_json 200 OK
cc_bank_json | jq -c '
  [ .[].tags[]? ]
  | reduce .[] as $t ({}; .[$t] += 1)
  | to_entries | map({tag:.key, count:.value}) | sort_by(-.count)
  | {success:true, tags:., total:length}
' 2>/dev/null || echo '{"success":true,"tags":[],"total":0}'
