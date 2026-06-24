# GET /problems/shared   (Bearer)
# Problemas compartilhados COM o autor logado (é colaborador, mas não o dono).
require_method GET
require_auth
source "$_DIR/lib/problems.sh"
owners_emit '
  { success:true, login:$login,
    problems: [ .problems[] | select((.collaborators|index($login)) and .owner!=$login) ] }
' --arg login "$SESSION_LOGIN"
