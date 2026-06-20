# GET /contest/statistics?contest=<id>  (admin/judge/mon) -> estatísticas agregadas do contest.
# Calcula do controle/history (7 campos: min:user:prob:lang:verdict:epoch:subid).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_admin || is_judge || is_mon; } || fail 403 "Apenas admin/judge/monitor" "stats_forbidden"

hist="$CONTESTSDIR/$contest/controle/history"
emit_json 200 OK
[[ -f "$hist" ]] || { jq -cn '{success:true, totals:{submissions:0,accepted:0,users:0,problems_solved:0}, problems:[], languages:[], verdicts:[], timeline:[]}'; exit 0; }

awk -F: '
{
  mn=$1; user=$2; prob=$3; lang=$4; v=$5;
  tot++; isac=(v ~ /^Accepted/);
  vc=v; sub(/,.*/,"",vc); sub(/ *\(.*/,"",vc); gsub(/^ +| +$/,"",vc); if(vc=="")vc="?"; vcl[vc]++;
  psub[prob]++; lsub[lang]++; users[user]=1;
  if(!((prob SUBSEP user) in patt)){ patt[prob SUBSEP user]=1; pattn[prob]++; }
  if(isac){
    acc++; lacc[lang]++;
    if(!((prob SUBSEP user) in psol)){ psol[prob SUBSEP user]=1; psoln[prob]++; }
    if(!((lang SUBSEP user) in lsol)){ lsol[lang SUBSEP user]=1; lsoln[lang]++; }
    if(!(prob in fmin) || (mn+0)<(fmin[prob]+0)){ fmin[prob]=mn+0; fuser[prob]=user; }
    solved[prob]=1;
  }
  b=int((mn+0)/10); if(b<0)b=0; if(b>20000)b=20000; tl[b]++; if(isac)tla[b]++; if(b>maxb)maxb=b;
}
END{
  for(p in psub) printf "P\t%s\t%d\t%d\t%d\t%s\t%d\n", p, psub[p], pattn[p], psoln[p]+0, (p in fuser?fuser[p]:""), (p in fmin?fmin[p]:-1);
  for(l in lsub) printf "L\t%s\t%d\t%d\t%d\n", l, lsub[l], lacc[l]+0, lsoln[l]+0;
  for(x in vcl) printf "V\t%s\t%d\n", x, vcl[x];
  for(i=0;i<=maxb;i++) if(tl[i]) printf "T\t%d\t%d\t%d\n", i*10, tl[i], tla[i]+0;
  ns=0; for(p in solved) ns++; nu=0; for(u in users) nu++;
  printf "G\t%d\t%d\t%d\t%d\n", tot, acc+0, nu, ns;
}' "$hist" | jq -R -s '
  [ split("\n")[] | select(length>0) | split("\t") ] as $r
  | { success:true,
      totals: ( ([ $r[] | select(.[0]=="G") ][0]) as $g | if $g then {submissions:($g[1]|tonumber), accepted:($g[2]|tonumber), users:($g[3]|tonumber), problems_solved:($g[4]|tonumber)} else {submissions:0,accepted:0,users:0,problems_solved:0} end),
      problems: ([ $r[] | select(.[0]=="P") | {problem_id:.[1], submissions:(.[2]|tonumber), attempted:(.[3]|tonumber), solved:(.[4]|tonumber), first_solver:.[5], first_minute:(.[6]|tonumber), accept_rate:(if (.[3]|tonumber)>0 then ((.[4]|tonumber)/(.[3]|tonumber)) else 0 end)} ] | sort_by(.problem_id)),
      languages: ([ $r[] | select(.[0]=="L") | {lang:.[1], submissions:(.[2]|tonumber), accepted:(.[3]|tonumber), solvers:(.[4]|tonumber)} ] | sort_by(-.submissions)),
      verdicts: ([ $r[] | select(.[0]=="V") | {verdict:.[1], count:(.[2]|tonumber)} ] | sort_by(-.count)),
      timeline: ([ $r[] | select(.[0]=="T") | {minute:(.[1]|tonumber), submissions:(.[2]|tonumber), accepted:(.[3]|tonumber)} ] | sort_by(.minute)) }' \
  2>/dev/null || jq -cn '{success:true, totals:{submissions:0}, problems:[], languages:[], verdicts:[], timeline:[]}'
