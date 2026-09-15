# GET /treino/admin/contests  (.admin) -> contests criados pela interface que ESTE admin pode ver.
# Escopo (cc_contest_visible_to, 2026-09-15): super-admin (conf SUPERADMINS do treino) vê tudo
# (`scope:"all"`); `.admin` comum vê os seus e os de criadores sem papel de admin (`scope:"admin"`) —
# professor não vê a prova de outro professor. O corte é AQUI; a tela só reflete.
# -> {contests:[{id,name,mode,owner,owner_name,owner_has_photo,owner_is_admin,created_at,start,end,
#     problems_count}], count, scope, me, is_superadmin}
require_method GET
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
source "$_LIBDIR/contest-create.sh"
c="$(cc_list_created "$SESSION_LOGIN")"
sup=false; scope=admin; is_superadmin && { sup=true; scope=all; }
ok_json '{contests:$c, count:($c|length), scope:$s, me:$me, is_superadmin:$sup}' \
  --argjson c "$c" --arg s "$scope" --arg me "$SESSION_LOGIN" --argjson sup "$sup"
