# GET /contest/navbuttons?contest=<id>   (Bearer)
# Botões de navegação por papel (substring no login). URLs em caminhos completos
# (/contest/...); '/' e '/logout' são especiais (ver shared/contest-shell.js navHref).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
source "$_LIBDIR/print.sh"

emit_json 200 OK

# .staff: NÃO submete (sem Contest/Clarification). Vê o placar (congela no freeze, como
# usuário normal) e a área de tarefas de impressão recebidas.
if is_staff; then
  jq -cn '{success:true, buttons:[
    {label:"Score", url:"/contest/score/"},
    {label:"🖨️ Impressão", url:"/contest/staff/"},
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
    {label:\"⚙ Administração\",  url:\"/contest/admin/\"},
    {label:\"Todas Submissões\", url:\"/contest/allsubmissions/\"},
    {label:\"Estatísticas\",     url:\"/contest/statistics/\"},
    {label:\"jplag\",            url:\"/contest/jplag/\"}]"
elif is_judge; then
  buttons="$buttons + [
    {label:\"Submissões Pendentes\", url:\"/contest/judge/\"},
    {label:\"Todas Submissões\",     url:\"/contest/allsubmissions/\"},
    {label:\"Estatísticas\",         url:\"/contest/statistics/\"}]"
elif is_mon; then
  buttons="$buttons + [
    {label:\"Todas Submissões\", url:\"/contest/allsubmissions/\"},
    {label:\"Estatísticas\",     url:\"/contest/statistics/\"}]"
else
  # usuário comum (não-privilegiado): página de backup só se o admin não desabilitou (BACKUP!=0)
  if [[ "$(. "$CONTESTSDIR/$contest/conf" 2>/dev/null; printf '%s' "${BACKUP:-}")" != 0 ]]; then
    buttons="$buttons + [{label:\"💾 Backup\", url:\"/contest/backup/\"}]"
  fi
  # página de impressão só quando há staff no contest E a impressão está habilitada
  if staff_exists "$contest" && print_enabled "$contest"; then
    buttons="$buttons + [{label:\"🖨️ Impressão\", url:\"/contest/print/\"}]"
  fi
fi

buttons="$buttons + [{label:\"Logout\", url:\"/logout\"}]"
jq -cn "{success:true, buttons:($buttons)}"
