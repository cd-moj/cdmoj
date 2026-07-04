# GET /contest/regions?contest=<id>
# Regiões/sub-regiões p/ filtro do placar (JSON de contests/<id>/regions.json),
# senão {success:true, regions:[]}.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_not_secret_or_auth "$contest"   # contest secreto: visual do placar exige sessão do contest

emit_json 200 OK
f="$CONTESTSDIR/$contest/regions.json"
if [[ -f "$f" ]] && jq -e . "$f" >/dev/null 2>&1; then
  jq -c '{success:true, regions:.}' "$f"
else
  jq -cn '{success:true, regions:[]}'
fi
