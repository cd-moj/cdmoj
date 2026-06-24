# GET /problems/mine   (Bearer)
# Problemas do autor logado: owner==login (reivindicados) + "prováveis" pré-migração
# (owner null e TODOS os tokens do nome completo da sessão, len>=4, aparecem no autor).
require_method GET
require_auth
source "$_DIR/lib/problems.sh"

# tokens do nome completo (>=4 chars) p/ casamento difuso enquanto não há owner curado
jtoks="$(prob_norm "$SESSION_NAME" | tr ' ' '\n' | awk 'length>=4' | jq -R . | jq -cs . 2>/dev/null)"
owners_emit '
  { success:true, login:$login,
    problems: [ .problems[]
      | select(.owner==$login
               or (.owner==null and ($toks|length)>0
                   and ([ $toks[] as $t | (.author_norm|contains($t)) ]|all)))
      | . + { claimed: (.owner==$login) } ] }
' --arg login "$SESSION_LOGIN" --argjson toks "${jtoks:-[]}"
