# GET /treino/contest-create/mine  (auth treino, pode criar) -> contests CRIADOS POR MIM
# (owner == login; exige created-by = criado pela interface). A lista do admin é
# /treino/admin/contests — aqui é só o recorte do criador (duplicar/exportar). Mesma leitura
# (cc_list_created … mine) da lista do admin.
require_method GET
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar contest" "create_forbidden"
list="$(cc_list_created "$SESSION_LOGIN" mine)"
ok_json '{contests:$l, total:($l|length)}' --argjson l "$list"
