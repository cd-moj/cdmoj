# GET /contest/admin/users?contest=<id>  (admin DO contest) -> usuários do passwd (sem senha)
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"

shared="$(grep -m1 '^USERS_FROM=' "$CONTESTSDIR/$contest/conf" 2>/dev/null | cut -d= -f2-)"
shared="${shared%\'}"; shared="${shared#\'}"; shared="${shared%\"}"; shared="${shared#\"}"
users="$(awk -F: 'NF{d=(substr($2,1,1)=="!")?"1":"0"; printf "%s\t%s\t%s\t%s\n",$1,$3,$4,d}' "$CONTESTSDIR/$contest/passwd" 2>/dev/null \
  | jq -R 'split("\t")|{login:.[0], fullname:.[1], email:.[2], admin:(.[0]|endswith(".admin")), disabled:(.[3]=="1")}' | jq -cs .)"
[[ -n "$users" ]] || users='[]'
ok_json '{users:$u, count:($u|length), shared:$sh}' --argjson u "$users" --arg sh "${shared:-}"
