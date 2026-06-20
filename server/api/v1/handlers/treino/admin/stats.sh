# GET /treino/admin/stats  (.admin) -> números p/ gráficos (logins/dia, submissões/dia, etc.)
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
T="$CONTESTSDIR/treino"
users="$(wc -l < "$T/passwd" 2>/dev/null || echo 0)"; users="${users//[!0-9]/}"; users="${users:-0}"

# sessões ativas do treino
sess=0
set +o noglob; shopt -s nullglob
for f in "$SESSIONDIR"/*; do
  [[ -f "$f" ]] || continue
  ( CONTEST=""; source "$f" 2>/dev/null; [[ "$CONTEST" == treino ]] && exit 7; exit 0 )
  [[ $? -eq 7 ]] && ((sess++))
done
shopt -u nullglob

cut=$(( EPOCHSECONDS - 30*86400 ))
# agrupa por dia (UTC) = floor(epoch/86400)*86400; o front formata a data
loginsday="$(awk -F'\t' -v c=$cut '$1>=c{a[int($1/86400)]++} END{for(k in a) print (k*86400)"\t"a[k]}' \
  "$T/var/access.log" 2>/dev/null | sort -n \
  | jq -R -cs 'split("\n")|map(select(length>0)|split("\t")|{day:(.[0]|tonumber), count:(.[1]|tonumber)})')"
[[ -z "$loginsday" ]] && loginsday='[]'
subsday="$(awk -F: -v c=$cut '{ts=$6+0; if(ts<1) ts=$1+0; if(ts>=c) a[int(ts/86400)]++} END{for(k in a) print (k*86400)"\t"a[k]}' \
  "$T/controle/history" 2>/dev/null | sort -n \
  | jq -R -cs 'split("\n")|map(select(length>0)|split("\t")|{day:(.[0]|tonumber), count:(.[1]|tonumber)})')"
[[ -z "$subsday" ]] && subsday='[]'

ok_json '{users:$u, active_sessions:$s, logins_per_day:$lpd, submissions_per_day:$spd}' \
  --argjson u "$users" --argjson s "$sess" --argjson lpd "$loginsday" --argjson spd "$subsday"
