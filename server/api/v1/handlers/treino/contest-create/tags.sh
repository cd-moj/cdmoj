# GET /treino/contest-create/tags  (auth treino, pode criar) -> tags do banco com contagem
require_method GET
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar contest" "create_forbidden"
CACHE="$CONTESTSDIR/treino/var/problems.json"
if [[ -f "$CACHE" ]]; then
  data="$(cat "$CACHE")"
else
  set +o noglob
  data="$(jq -s 'map({id, title, tags:(.tags//[])})' "$CONTESTSDIR"/treino/var/jsons/*.json 2>/dev/null)"
  set -o noglob
  [[ -n "$data" ]] || data='[]'
fi
emit_json 200 OK
jq -c '
  [ .[].tags[]? ]
  | reduce .[] as $t ({}; .[$t] += 1)
  | to_entries | map({tag:.key, count:.value}) | sort_by(-.count)
  | {success:true, tags:., total:length}
' <<<"$data" 2>/dev/null || echo '{"success":true,"tags":[],"total":0}'
