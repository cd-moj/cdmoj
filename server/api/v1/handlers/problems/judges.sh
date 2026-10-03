# GET /problems/judges   (Bearer)
# Lista os juízes (do registro pull) p/ a calibração DIRECIONADA do editor: host, modelo de CPU,
# linguagens e se está online. O editor agrupa por CPU p/ oferecer "1 por processador".
# (Dentro de um contest o seletor usa GET /contest/admin/judges — mesma lista, lib/judges-registry.sh.)
require_method GET
require_auth
source "$_LIBDIR/judges-registry.sh"
ok_json '{judges:$j}' --argjson j "$(jr_list_json)"
