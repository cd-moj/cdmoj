# GET /treino/admin/managed-users  (.admin) -> lista das contas GERIDAS (com .managed).
# Contas criadas por admin p/ menores, sem Telegram — docs/CONTAS-GERIDAS.md.
# {users:[{login,fullname,by,note,birthdate,minor,expires_at,disabled,created_at}]}
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"

# find|xargs (ARG_MAX); minor calculado com corte "hoje - 18 anos" (nascido depois = menor)
cut18="$(date -d '-18 years' +%Y-%m-%d 2>/dev/null)"; cut18="${cut18:-1900-01-01}"
body="$(find "$CONTESTSDIR/treino/users" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
  | xargs -0 -r jq -c --arg cut "$cut18" '
      select(.managed != null)
      | {login, fullname:(.fullname // ""),
         by:(.managed.by // ""), note:(.managed.note // ""),
         birthdate:(.managed.birthdate // ""),
         minor:((.managed.birthdate // "9999") > $cut),
         expires_at:(.managed.expires_at // null),
         disabled:((.password // "") | startswith("!")),
         created_at:(.managed.created_at // .created_at // 0)}' 2>/dev/null \
  | jq -sc '{success:true, users:(sort_by(.login)), count:length}')"
[[ -n "$body" ]] || body='{"success":true,"users":[],"count":0}'

emit_json 200 OK
printf '%s\n' "$body"
