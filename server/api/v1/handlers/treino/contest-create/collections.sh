# GET /treino/contest-create/collections  (auth treino, pode criar) -> coleções do BANCO
# PÚBLICO do treino com contagem, p/ o sorteio/busca do wizard. Escopo ≠ /problems/collections
# (aquele conta sobre owners_visible — problemas do LOGIN; este conta o banco do treino).
require_method GET
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar contest" "create_forbidden"
emit_json 200 OK
cc_bank_json | jq -c '
  [ .[].collections[]? ]
  | reduce .[] as $c ({}; .[$c] += 1)
  | to_entries | map({collection:.key, count:.value}) | sort_by(-.count)
  | {success:true, collections:., total:length}
' 2>/dev/null || echo '{"success":true,"collections":[],"total":0}'
