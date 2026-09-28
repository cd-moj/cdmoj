# GET /contest/admin/users?contest=<id>  (admin DO contest) -> usuários do store (sem senha)
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"

src="$(_users_source "$contest")"; shared=""; [[ "$src" != "$contest" ]] && shared="$src"
# batch: find|xargs jq sobre users/*/account.json (sem ARG_MAX, sem fork por usuário)
d="$CONTESTSDIR/$contest/users"
users='[]'
if [[ -d "$d" ]]; then
  # `shared`: entra pela conta do TREINO (sem senha local — overlay de inscrição ou de bloqueio).
  # Contest COMPARTILHADO: os participantes que só têm DIR (entraram/submeteram sem account.json local)
  # também são listados — antes eram invisíveis no painel e não havia como agir neles. A identidade vem
  # da fonte POR CAMINHO (um xargs jq sobre os account.json deles), NUNCA varrendo o treino (18/08).
  users="$( { find "$d" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
      | xargs -0 -r jq -c --arg sh "$shared" '{login:(.login//""), fullname:(.fullname//""), email:(.email//""),
                          admin:((.login//"")|endswith(".admin")),
                          disabled:((.password//"")|startswith("!")),
                          disqualified:(.disqualified == true),
                          shared:($sh != "" and ((.shared_overlay == true) or ((.password//"") == "")))}'
    if [[ -n "$shared" ]]; then
      find "$d" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | while IFS= read -r l; do
        [[ -f "$d/$l/account.json" ]] && continue
        valid_id "$l" && [[ -f "$CONTESTSDIR/$shared/users/$l/account.json" ]] \
          && printf '%s\0' "$CONTESTSDIR/$shared/users/$l/account.json"
      done | xargs -0 -r jq -c '{login:(.login//""), fullname:(.fullname//""), email:"",
                                 admin:((.login//"")|endswith(".admin")), disabled:false, disqualified:false,
                                 shared:true, dir_only:true}'
    fi; } | jq -cs 'map(select(.login != "")) | unique_by(.login) | sort_by(.login)')"
  [[ -n "$users" ]] || users='[]'
fi
# ⚠ a lista cresce com o nº de CONTAS (um objeto por conta): num contest de 2354 contas ela
# passa de 250 KB e estoura o teto de **128 KiB por argumento** do exec — o jq morre com
# "Argument list too long" e o ok_json devolve 500 build_fail. Agregado de N arquivos NUNCA
# entra por --argjson (ver ../../../CLAUDE.md e ok_json_slurp em lib/common.sh).
ok_json_slurp '{users:$u[0], count:($u[0]|length), shared:$sh}' u "$users" --arg sh "${shared:-}"
