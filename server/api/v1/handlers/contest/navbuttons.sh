# GET /contest/navbuttons?contest=<id>   (Bearer)
# Botões de navegação por papel (substring no login). URLs em caminhos completos
# (/contest/...); '/' e '/logout' são especiais (ver shared/contest-shell.js navHref).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

emit_json 200 OK

if is_staff; then
  jq -cn '{success:true, buttons:[
    {label:"Score", url:"/contest/score/"},
    {label:"Tarefas", url:"/contest/admin_tasks/"},
    {label:"Logout", url:"/logout"}
  ]}'
  exit 0
fi

# base comum a usuário/monitor/judge/admin
buttons='[{label:"Contest", url:"/"},
          {label:"Score", url:"/contest/score/"},
          {label:"Clarification", url:"/contest/clarification/"}]'

if is_admin; then
  buttons="$buttons + [
    {label:\"⚙ Configurar\",         url:\"/contest/admin/\"},
    {label:\"Tarefas Administrativas\", url:\"/contest/admin_tasks/\"},
    {label:\"Todas Submissões\",      url:\"/contest/allsubmissions/\"},
    {label:\"Estatísticas\",          url:\"/contest/statistics/\"},
    {label:\"jplag\",                 url:\"/contest/jplag/\"},
    {label:\"Log\",                   url:\"/contest/log/\"}]"
elif is_judge; then
  buttons="$buttons + [
    {label:\"Submissões Pendentes\", url:\"/contest/judge/\"},
    {label:\"Todas Submissões\",     url:\"/contest/allsubmissions/\"},
    {label:\"Estatísticas\",         url:\"/contest/statistics/\"}]"
elif is_mon; then
  buttons="$buttons + [
    {label:\"Todas Submissões\", url:\"/contest/allsubmissions/\"},
    {label:\"Estatísticas\",     url:\"/contest/statistics/\"}]"
fi

buttons="$buttons + [{label:\"Logout\", url:\"/logout\"}]"
jq -cn "{success:true, buttons:($buttons)}"
