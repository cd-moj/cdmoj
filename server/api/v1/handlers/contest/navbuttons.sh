# GET /contest/navbuttons?contest=<id>   (Bearer)
# Lista de botões de navegação por papel (substring no login): [{label,url}].
#   base   : Contest, Score, Clarification, Logout
#   .admin : + Todas Submissões, Estatísticas, Jplag, Reports, Tarefas Administrativas, Log
#   .judge : + Submissões Pendentes de Julgamento  (antes do Logout)
#   .staff : apenas Score, Tarefas, Logout
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

emit_json 200 OK

if is_staff; then
  jq -cn '{success:true, buttons:[
    {label:"Score", url:"/score"},
    {label:"Tarefas", url:"/admin_tasks"},
    {label:"Logout", url:"/logout"}
  ]}'
  exit 0
fi

# base comum a usuário/judge/admin
buttons='[{label:"Contest", url:"/"},
          {label:"Score", url:"/score"},
          {label:"Clarification", url:"/clarification"}]'

if is_admin; then
  buttons="$buttons + [
    {label:\"⚙ Configurar\", url:\"/contest/admin/\"},
    {label:\"Todas Submissões\", url:\"/all_submissions\"},
    {label:\"Estatísticas\", url:\"/stats\"},
    {label:\"Jplag\", url:\"/jplag\"},
    {label:\"Reports\", url:\"/reports\"},
    {label:\"Tarefas Administrativas\", url:\"/admin_tasks\"},
    {label:\"Log\", url:\"/log\"}]"
elif is_judge; then
  buttons="$buttons + [{label:\"Submissões Pendentes de Julgamento\", url:\"/pending\"}]"
fi

buttons="$buttons + [{label:\"Logout\", url:\"/logout\"}]"
jq -cn "{success:true, buttons:($buttons)}"
