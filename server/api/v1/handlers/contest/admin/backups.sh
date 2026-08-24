# GET /contest/admin/backups?contest=<c>[&user=<substr>&q=<name-substr>]  (admin DO contest)
# Lista TODOS os backups de TODOS os usuários (filtra por login e/ou nome) + resumo por usuário.
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"

uq="$(param user | tr 'A-Z' 'a-z')"
nq="$(param q | tr 'A-Z' 'a-z')"
base="$CONTESTSDIR/$contest/backups"
set +o noglob; shopt -s nullglob
items=()
for ud in "$base"/*/; do
  [[ -d "$ud" ]] || continue
  ulogin="$(basename "$ud")"
  for m in "$ud"*.meta; do
    [[ -f "$m" ]] || continue
    bid="$(basename "$m" .meta)"
    items+=("$(jq -c --arg id "$bid" --arg login "$ulogin" '. + {id:$id, login:$login}' "$m" 2>/dev/null)")
  done
done
shopt -u nullglob
all="$( ((${#items[@]})) && printf '%s\n' "${items[@]}" | jq -cs '.' || echo '[]')"
out="$(jq -c --arg u "$uq" --arg q "$nq" '
  [ .[] | select(($u=="" or (.login|ascii_downcase|contains($u))) and ($q=="" or (.name|ascii_downcase|contains($q)))) ]
  | sort_by(-.time)' <<<"$all")"
users="$(jq -c 'group_by(.login) | map({login:.[0].login, count:length, bytes:(map(.size)|add)}) | sort_by(.login)' <<<"$all")"
# a lista de backups cresce com nº de contas × salvamentos: --slurpfile (teto de 128KiB do
# --argjson) — ver ok_json_slurp em lib/common.sh.
ok_json_slurp '{backups:$b[0], users:$u[0]}' b "$out" \
  --slurpfile u <(printf '%s' "${users:-[]}")   # 1 objeto por conta: mesmo teto de 128 KiB
