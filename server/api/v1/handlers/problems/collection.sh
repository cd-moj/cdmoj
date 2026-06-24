# GET /problems/collection?name=<coleção>   (Bearer)
# Problemas de uma coleção (curso/diretório compartilhado — ex.: obi-problems, saad-problems).
require_method GET
require_auth
source "$_DIR/lib/problems.sh"
name="$(param name)"
[[ -n "$name" ]] || fail 400 "Missing name" "name_missing"
owners_emit '
  { success:true, collection:$n,
    problems: [ .problems[] | select(.collections|index($n)) ] }
' --arg n "$name"
