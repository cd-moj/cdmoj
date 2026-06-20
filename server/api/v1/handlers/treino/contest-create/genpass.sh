# GET /treino/contest-create/genpass?n=K  (auth treino, pode criar) -> K senhas legíveis
require_method GET
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar contest" "create_forbidden"
n="$(param n)"; [[ "$n" =~ ^[0-9]+$ ]] || n=1; (( n < 1 )) && n=1; (( n > 500 )) && n=500
declare -a PW
for ((i=0;i<n;i++)); do PW+=("$(cc_genpass)"); done
list="$(printf '%s\n' "${PW[@]}" | jq -R . | jq -cs .)"
ok_json '{passwords:$p}' --argjson p "$list"
