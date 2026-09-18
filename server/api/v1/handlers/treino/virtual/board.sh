# GET /treino/virtual/board?contest=<cid>   (anônimo)
# Participações virtuais JÁ FINALIZADAS do contest (snapshots): {login,name,solved,penalty,runs…}.
# Com Bearer do treino marca `you`. Mesmo portão do feed.
require_method GET
source "$_LIBDIR/virtual.sh"
cid="$(param contest)"; vr_gate "$cid"
me=""; load_session 2>/dev/null && [[ "${SESSION_CONTEST:-}" == treino ]] && me="$SESSION_LOGIN"
ok_json_slurp '{contest:$c, virtuals:($v[0] | map(. + {you:(.login == $me)}))}' v "$(vr_board_json "$cid")" \
  --arg c "$VR_CID" --arg me "$me"
