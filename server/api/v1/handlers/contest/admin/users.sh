# GET /contest/admin/users?contest=<id>  (admin DO contest) -> usuários do store (sem senha)
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"

shared="$(grep -m1 '^USERS_FROM=' "$CONTESTSDIR/$contest/conf" 2>/dev/null | cut -d= -f2-)"
shared="${shared%\'}"; shared="${shared#\'}"; shared="${shared%\"}"; shared="${shared#\"}"
# batch: find|xargs jq sobre users/*/account.json (sem ARG_MAX, sem fork por usuário)
d="$CONTESTSDIR/$contest/users"
users='[]'
if [[ -d "$d" ]]; then
  users="$(find "$d" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
    | xargs -0 -r jq -c '{login:(.login//""), fullname:(.fullname//""), email:(.email//""),
                          admin:((.login//"")|endswith(".admin")),
                          disabled:((.password//"")|startswith("!"))}' \
    | jq -cs 'map(select(.login != "")) | sort_by(.login)')"
  [[ -n "$users" ]] || users='[]'
fi
# ⚠ a lista cresce com o nº de CONTAS (um objeto por conta): num contest de 2354 contas ela
# passa de 250 KB e estoura o teto de **128 KiB por argumento** do exec — o jq morre com
# "Argument list too long" e o ok_json devolve 500 build_fail. Agregado de N arquivos NUNCA
# entra por --argjson (ver ../../../CLAUDE.md e ok_json_slurp em lib/common.sh).
ok_json_slurp '{users:$u[0], count:($u[0]|length), shared:$sh}' u "$users" --arg sh "${shared:-}"
