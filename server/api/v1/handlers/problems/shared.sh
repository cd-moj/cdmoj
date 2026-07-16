# GET /problems/shared   (Bearer)
# Problemas compartilhados COM o autor logado: tudo que ele PODE EDITAR e não é dele —
# colaborador por-problema OU **membro da org** (membro vê/opera todos os problemas da org,
# inclusive privados; decisão 2026-07-16). Dono fica na aba "mine".
require_method GET
require_auth
source "$_DIR/lib/problems.sh"
owners_emit '
  { success:true, login:$login,
    problems: [ .problems[] | select(.owner != $login
      and (((.collaborators // [])|index($login)|type=="number")
           or (((.repo // (.id|split("#")[0])) as $r | $orgs|index($r))|type=="number"))) ] }
' --arg login "$SESSION_LOGIN" --argjson orgs "$(my_orgs_json)"
