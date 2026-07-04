# GET /contest/teams-meta?contest=<id>
# Regras regex (login/time -> país + escola) para o placar preencher bandeira/universidade
# e habilitar filtro por país/escola. JSON de contests/<id>/teams-meta.json; senão vazio.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_not_secret_or_auth "$contest"   # contest secreto: visual do placar exige sessão do contest

emit_json 200 OK
f="$CONTESTSDIR/$contest/teams-meta.json"
if [[ -f "$f" ]] && jq -e . "$f" >/dev/null 2>&1; then
  jq -c '{success:true, rules:(.rules // (if type=="array" then . else [] end))}' "$f"
else
  jq -cn '{success:true, rules:[]}'
fi
