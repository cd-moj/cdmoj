# GET /treino/contest-create/problems?q=&limit=  (auth treino, pode criar)
# Busca os problemas que o usuário PODE USAR num contest: públicos (banco do treino) + os
# PRIVADOS a que ele tem acesso (dono ou colaborador). Autocomplete do seletor de problemas.
require_method GET
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar contest" "create_forbidden"
source "$_LIBDIR/problems.sh"

q="$(param q)"; limit="$(param limit)"
[[ "$limit" =~ ^[0-9]+$ ]] || limit=40; (( limit > 100 )) && limit=100

emit_json 200 OK
owners_merged | jq -c --arg me "$SESSION_LOGIN" --arg q "$q" --argjson n "$limit" '
  [ .problems[]
    | ( if .owner==$me then "mine"
        elif ((.collaborators // [])|index($me)) then "shared"
        elif .public then "public" else null end ) as $acc
    | select($acc != null)
    | { id, title, tags:(.tags // []), access:$acc, private:(.public|not) } ]
  | ( if (($q|length) > 0)
      then map(select( ((.id + " " + (.title // ""))|ascii_downcase) | contains($q|ascii_downcase) ))
      else . end )
  | sort_by(.private|not) as $f                      # privados (seus) primeiro
  | { success:true, problems:($f[0:$n]), total:($f|length),
      mine:([$f[]|select(.access=="mine")]|length), shared:([$f[]|select(.access=="shared")]|length) }
' 2>/dev/null || echo '{"success":true,"problems":[],"total":0}'
