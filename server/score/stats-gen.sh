#!/usr/bin/env bash
#
# stats-gen.sh <contest> <outfile>
#
# Gera o JSON de estatísticas agregadas do contest a partir do stream de history
# (7 campos: min:user:prob:lang:verdict:epoch:subid) e do conf (PROBS, p/ resolver
# letra/nome dos problemas), gravando o resultado ATÔMICO em <outfile>.
#
# É o "build" das estatísticas — análogo ao server/score/build.sh do placar. O
# handler /contest/statistics usa este script como cache preguiçoso: só regenera
# quando history/conf mudam (ver lib/common.sh: regen_locked / stale_cache).
#
# Estatísticas contam SÓ usuários normais — descarta privilegiados (.admin/.judge/.staff/.cstaff/.mon).
set -u
: "${CONTESTSDIR:=/home/ribas/moj/contests}"

C="${1:-}"; OUT="${2:-}"
[[ -n "$C" && -n "$OUT" ]] || { echo "uso: stats-gen.sh <contest> <outfile>" >&2; exit 1; }
case "$C" in *[!A-Za-z0-9._@#+-]* | "" | *..* ) echo "stats-gen: invalid contest id" >&2; exit 1;; esac

conf="$CONTESTSDIR/$C/conf"
# materializa o history no formato global (7 campos) num temp — awk abaixo inalterado.
_SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$_SDIR/../api/v1/lib/users.sh"
_HT="$(mktemp)"; emit_history_stream "$C" > "$_HT"; hist="$_HT"
mkdir -p "$(dirname "$OUT")" 2>/dev/null
TMP="$(mktemp "$OUT.XXXXXX")" || { echo "stats-gen: mktemp falhou" >&2; exit 1; }
trap 'rm -f "$TMP" "${_HT:-}"' EXIT

empty='{"success":true,"totals":{"submissions":0,"accepted":0,"users":0,"problems_solved":0},"problems":[],"languages":[],"verdicts":[],"timeline":[],"problems_solved_dist":[],"attempts_dist":[],"verdict_by_problem":[]}'
if [[ ! -f "$hist" ]]; then
  printf '%s\n' "$empty" > "$TMP"; mv "$TMP" "$OUT"; trap - EXIT; exit 0
fi

# Mapa do problem_id do history -> letra/nome. No history o campo 3 (PROBID) é o
# OFFSET-base no array PROBS (passo 5: 0,5,10,...; o juiz faz SITE=${PROBS[PROBID]}),
# enquanto submissões novas gravam o id-fonte pontilhado (a/b -> a.b). Cobrimos os dois.
PROBS=()
# shellcheck disable=SC1090
source "$conf" 2>/dev/null
set +o noglob
pm_items=()
for (( i=0; i<${#PROBS[@]}; i+=5 )); do
  praw="${PROBS[$((i+1))]}"
  # phash = id canônico 'coleção#problema' (forma que o pipeline novo grava no history);
  # skey (PROBS[i+4]) já é '#' nos contests novos, senão converte a barra do problem_id.
  phash="${PROBS[$((i+4))]}"; [[ "$phash" == *"#"* ]] || phash="${praw//\//#}"
  pm_items+=( "$(jq -cn --arg off "$i" --arg raw "$praw" --arg dot "${praw/\//.}" --arg hash "$phash" \
      --arg short "${PROBS[$((i+3))]}" --arg full "${PROBS[$((i+2))]}" \
      '{off:$off, raw:$raw, dot:$dot, hash:$hash, short:$short, full:$full}')" )
done
if (( ${#pm_items[@]} )); then probmeta="$(printf '%s\n' "${pm_items[@]}" | jq -cs '.')"; else probmeta='[]'; fi

START_VAL="${CONTEST_START:-0}"; [[ "$START_VAL" =~ ^[0-9]+$ ]] || START_VAL=0
awk -F: -v START="$START_VAL" '
{
  # estatísticas só de usuários normais: descarta privilegiados (.admin/.judge/.cjudge/.staff/.cstaff/.mon)
  if($2 ~ /\.(admin|judge|cjudge|staff|cstaff|mon)$/) next;
  # tempo RELATIVO ao início: usa o sub_epoch (penúltimo campo, sempre EPOCH absoluto) menos
  # CONTEST_START. mn = minutos relativos; secs = segundos (p/ desempate do 1º a resolver).
  secs=$(NF-1)-START; if(secs<0)secs=0; mn=int(secs/60);
  user=$2; prob=$3; lang=$4; v=$5;
  tot++; isac=(v ~ /^Accepted/);
  puk=prob SUBSEP user; if(!(puk in solvedAt)){ att[puk]=att[puk]+1; if(isac) solvedAt[puk]=att[puk] }
  vc=v; sub(/,.*/,"",vc); sub(/ *\(.*/,"",vc); gsub(/^ +| +$/,"",vc); if(vc=="")vc="?"; vcl[vc]++; pv[prob SUBSEP vc]++;
  psub[prob]++; lsub[lang]++; users[user]=1;
  if(!((prob SUBSEP user) in patt)){ patt[prob SUBSEP user]=1; pattn[prob]++; }
  if(isac){
    acc++; lacc[lang]++; pacc[prob]++;
    if(!((prob SUBSEP user) in psol)){ psol[prob SUBSEP user]=1; psoln[prob]++; }
    if(!((lang SUBSEP user) in lsol)){ lsol[lang SUBSEP user]=1; lsoln[lang]++; }
    if(!(prob in fsec) || (secs+0)<(fsec[prob]+0)){ fsec[prob]=secs+0; fmin[prob]=mn+0; fuser[prob]=user; }
    solved[prob]=1;
  }
  b=int((mn+0)/10); if(b<0)b=0; if(b>20000)b=20000; tl[b]++; if(isac)tla[b]++; if(b>maxb)maxb=b;
}
END{
  for(p in psub) printf "P\t%s\t%d\t%d\t%d\t%s\t%d\t%d\t%d\n", p, psub[p], pattn[p], psoln[p]+0, (p in fuser?fuser[p]:""), (p in fmin?fmin[p]:-1), pacc[p]+0, (p in fsec?fsec[p]:-1);
  for(pu in pv){ split(pu,xx,SUBSEP); printf "PV\t%s\t%s\t%d\n", xx[1], xx[2], pv[pu] }
  for(l in lsub) printf "L\t%s\t%d\t%d\t%d\n", l, lsub[l], lacc[l]+0, lsoln[l]+0;
  for(x in vcl) printf "V\t%s\t%d\n", x, vcl[x];
  for(i=0;i<=maxb;i++) if(tl[i]) printf "T\t%d\t%d\t%d\n", i*10, tl[i], tla[i]+0;
  for(pu in solvedAt){ split(pu,aa,SUBSEP); usolv[aa[2]]++ }
  for(u in users){ kk=usolv[u]+0; sdist[kk]++ }
  for(kk in sdist) printf "D\t%d\t%d\n", kk, sdist[kk];
  for(pu in solvedAt){ av=solvedAt[pu]; adist[av]++ }
  for(av in adist) printf "A\t%d\t%d\n", av, adist[av];
  ns=0; for(p in solved) ns++; nu=0; for(u in users) nu++;
  printf "G\t%d\t%d\t%d\t%d\n", tot, acc+0, nu, ns;
}' "$hist" | jq -R -s --argjson pm "$probmeta" '
  [ split("\n")[] | select(length>0) | split("\t") ] as $r
  | { success:true,
      totals: ( ([ $r[] | select(.[0]=="G") ][0]) as $g | if $g then {submissions:($g[1]|tonumber), accepted:($g[2]|tonumber), users:($g[3]|tonumber), problems_solved:($g[4]|tonumber)} else {submissions:0,accepted:0,users:0,problems_solved:0} end),
      problems: ([ $r[] | select(.[0]=="P") | (.[1]) as $pid | ($pm | map(select(.off==$pid or .raw==$pid or .dot==$pid or .hash==$pid)) | .[0]) as $m | {problem_id:$pid, short_name:($m.short // $pid), full_name:($m.full // ""), submissions:(.[2]|tonumber), attempted:(.[3]|tonumber), solved:(.[4]|tonumber), accepted_subs:(.[7]|tonumber? // 0), first_solver:.[5], first_minute:(.[6]|tonumber), first_seconds:(.[8]|tonumber? // -1), accept_rate:(if (.[3]|tonumber)>0 then ((.[4]|tonumber)/(.[3]|tonumber)) else 0 end), avg_subs:(if (.[3]|tonumber)>0 then (((.[2]|tonumber)/(.[3]|tonumber)*100)|floor)/100 else 0 end)} ] | sort_by(.short_name)),
      languages: ([ $r[] | select(.[0]=="L") | {lang:.[1], submissions:(.[2]|tonumber), accepted:(.[3]|tonumber), solvers:(.[4]|tonumber)} ] | sort_by(-.submissions)),
      verdicts: ([ $r[] | select(.[0]=="V") | {verdict:.[1], count:(.[2]|tonumber)} ] | sort_by(-.count)),
      timeline: ([ $r[] | select(.[0]=="T") | {minute:(.[1]|tonumber), submissions:(.[2]|tonumber), accepted:(.[3]|tonumber)} ] | sort_by(.minute)),
      problems_solved_dist: ([ $r[] | select(.[0]=="D") | {solved:(.[1]|tonumber), users:(.[2]|tonumber)} ] | sort_by(.solved)),
      attempts_dist: ([ $r[] | select(.[0]=="A") | {attempts:(.[1]|tonumber), count:(.[2]|tonumber)} ] | sort_by(.attempts)),
      verdict_by_problem: ([ $r[] | select(.[0]=="PV") | {problem:.[1], verdict:.[2], count:(.[3]|tonumber)} ]) }' \
  > "$TMP" 2>/dev/null || printf '%s\n' "$empty" > "$TMP"

mv "$TMP" "$OUT"; trap - EXIT
