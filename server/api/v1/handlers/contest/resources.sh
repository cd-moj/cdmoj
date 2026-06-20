# GET /contest/resources?contest=<id>   (Bearer)
# Seção "Prova": arquivos adicionais (caderno, time limits...) (opcional).
# Lê contests/<id>/resources.json (array de {label,url}); senão {success:true, items:[]}.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

f="$CONTESTSDIR/$contest/resources.json"
emit_json 200 OK
if [[ -f "$f" ]] && jq -e . "$f" >/dev/null 2>&1; then
  jq -c '{success:true, items:.}' "$f"
else
  jq -cn '{success:true, items:[]}'
fi
