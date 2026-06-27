# GET /problems/mine   (Bearer)
# Problemas do autor logado: owner==login. Gitea é a fonte; sem casamento difuso de "legado".
require_method GET
require_auth
source "$_DIR/lib/problems.sh"

owners_emit '
  { success:true, login:$login,
    problems: [ .problems[] | select(.owner==$login) | . + { claimed:true } ] }
' --arg login "$SESSION_LOGIN"
