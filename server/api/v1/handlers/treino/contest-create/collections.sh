# GET /treino/contest-create/collections[?include_private=1]  (auth treino, pode criar) -> coleções
# do BANCO PÚBLICO do treino com contagem, p/ o sorteio/busca do wizard; include_private=1 soma
# os privados de quem cria (o mesmo banco do draw.sh). Escopo ≠ /problems/collections
# (aquele conta sobre owners_visible — problemas do LOGIN; este conta o banco do treino).
require_method GET
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar contest" "create_forbidden"
inc=0; [[ "$(param include_private)" == 1 ]] && inc=1
# o banco sai ANTES do cabeçalho: com o 200 já enviado não dá mais p/ dizer 503
bank="$(cc_bank_json_for "$SESSION_LOGIN" "$inc")" || fail 503 "Índice de problemas indisponível" "index_unavailable"
emit_json 200 OK
jq -c '
  [ .[].collections[]? ]
  | reduce .[] as $c ({}; .[$c] += 1)
  | to_entries | map({collection:.key, count:.value}) | sort_by(-.count)
  | {success:true, collections:., total:length}
' <<<"$bank" 2>/dev/null || echo '{"success":true,"collections":[],"total":0}'
