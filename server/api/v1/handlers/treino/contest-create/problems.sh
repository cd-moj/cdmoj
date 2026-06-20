# GET /treino/contest-create/problems?q=&limit=  (auth treino, pode criar)
# Busca no banco público (treino/var/problems.json ou var/jsons) para o seletor de problemas.
require_method GET
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar contest" "create_forbidden"
q="$(param q)"; limit="$(param limit)"
[[ "$limit" =~ ^[0-9]+$ ]] || limit=40; (( limit > 100 )) && limit=100
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
jq -c --arg q "$q" --argjson n "$limit" '
  ( [ .[] | {id, title, tags:(.tags//[])} ] ) as $all
  | ( if (($q|length)>0)
      then ($all | map(select( ((.id+" "+(.title//""))|ascii_downcase) | contains($q|ascii_downcase) )))
      else $all end ) as $f
  | {success:true, problems:($f[0:$n]), total:($f|length), bank_total:($all|length)}
' <<<"$data" 2>/dev/null || echo '{"success":true,"problems":[],"total":0,"bank_total":0}'
