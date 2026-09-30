# GET /treino/contest-create/tags[?include_private=1]  (auth treino, pode criar) -> tags do banco com
# contagem. include_private=1 soma os privados de quem cria (o mesmo banco do draw.sh).
require_method GET
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar contest" "create_forbidden"
inc=0; [[ "$(param include_private)" == 1 ]] && inc=1
# o banco sai ANTES do cabeçalho: com o 200 já enviado não dá mais p/ dizer 503
bank="$(cc_bank_json_for "$SESSION_LOGIN" "$inc")" || fail 503 "Índice de problemas indisponível" "index_unavailable"
emit_json 200 OK
jq -c '
  [ .[].tags[]? ]
  | reduce .[] as $t ({}; .[$t] += 1)
  | to_entries | map({tag:.key, count:.value}) | sort_by(-.count)
  | {success:true, tags:., total:length}
' <<<"$bank" 2>/dev/null || echo '{"success":true,"tags":[],"total":0}'
