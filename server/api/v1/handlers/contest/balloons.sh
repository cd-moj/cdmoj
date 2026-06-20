# GET /contest/balloons?contest=<id>
# Mapa letra/shortname -> cor (hex sem '#') dos balões. Default = paleta ICPC;
# pode ser sobrescrito (parcial ou total) por contests/<id>/balloons.json.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"

emit_json 200 OK
# objeto default construído com jq (aceita chaves sem aspas)
DEFAULT="$(jq -cn '{A:"FFFFFF",B:"000000",C:"FF0000",D:"800000",E:"FFFF00",
                    F:"008000",G:"0000FF",H:"000080",I:"FF00FF",J:"800080",
                    K:"00FF00",L:"00FFFF",M:"C0C0C0",N:"FF8000",O:"A3794D"}')"

f="$CONTESTSDIR/$contest/balloons.json"
if [[ -f "$f" ]] && jq -e . "$f" >/dev/null 2>&1; then
  # override merge: defaults + arquivo (chaves do arquivo prevalecem)
  jq -cn --argjson d "$DEFAULT" --slurpfile o "$f" \
    '{success:true, balloons:($d + ($o[0]))}'
else
  jq -cn --argjson d "$DEFAULT" '{success:true, balloons:$d}'
fi
