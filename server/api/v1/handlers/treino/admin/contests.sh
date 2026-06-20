# GET /treino/admin/contests  (.admin) -> contests criados pela interface (com marcador created-by)
require_method GET
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
source "$_LIBDIR/contest-create.sh"
c="$(cc_list_created)"
ok_json '{contests:$c, count:($c|length)}' --argjson c "$c"
