# GET /contest/review/stats?contest=<id>   (Bearer, admin OU juiz-chefe)
# Estatística por .judge da avaliação manual, derivada do log de auditoria (var/admin-audit.log):
# nº de veredictos dados, tempo MÉDIO de resposta (do claim até o voto), concordâncias e conflitos.
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin_or_chief || fail 403 "Apenas o admin ou o juiz-chefe" "chief_required"

log="$CONTESTSDIR/$contest/var/admin-audit.log"
if [[ ! -f "$log" ]]; then ok_json '{judges:[], total:{votes:0, avg_response_s:0}}'; exit 0; fi

# parse TSV (epoch \t who \t action \t details): casa o claim do juiz com o voto na MESMA submissão
rows="$(awk -F'\t' '
  function getid(s){ if (match(s, /id=[^ ]+/)) return substr(s, RSTART+3, RLENGTH-3); return "" }
  $3=="review-claim" { id=getid($4); if (id!="") claim[$2 SUBSEP id]=$1 }
  ($3=="review-vote" || $3=="review-agree" || $3=="review-conflict") {
    id=getid($4); who=$2; votes[who]++; tv++;
    k=who SUBSEP id;
    if (k in claim) { rt=$1-claim[k]; if (rt>=0) { rtsum[who]+=rt; rtn[who]++; trts+=rt; trtn++ } }
    if ($3=="review-agree")    agree[who]++;
    if ($3=="review-conflict") confl[who]++;
  }
  END {
    for (j in votes) printf "%s\t%d\t%d\t%d\t%d\t%d\n", j, votes[j], (rtn[j]?int(rtsum[j]/rtn[j]):0), rtn[j], agree[j]+0, confl[j]+0;
    printf "::TOTAL::\t%d\t%d\n", tv+0, (trtn?int(trts/trtn):0) > "/dev/stderr";
  }
' "$log" 2>"$log.tot.$$")"
read -r _tag tv tavg < <(cat "$log.tot.$$" 2>/dev/null); rm -f "$log.tot.$$"
[[ "$tv" =~ ^[0-9]+$ ]] || tv=0; [[ "$tavg" =~ ^[0-9]+$ ]] || tavg=0

judges="$(printf '%s' "$rows" | jq -R -s '
  split("\n") | map(select(length>0) | split("\t")
    | { judge:.[0], votes:(.[1]|tonumber), avg_response_s:(.[2]|tonumber),
        timed:(.[3]|tonumber), agreements:(.[4]|tonumber), conflicts:(.[5]|tonumber) })
  | sort_by(-.votes)')"
[[ -n "$judges" ]] || judges='[]'
ok_json '{judges:$j, total:{votes:$tv, avg_response_s:$ta}}' \
  --argjson j "$judges" --argjson tv "$tv" --argjson ta "$tavg"
