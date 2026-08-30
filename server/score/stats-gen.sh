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

empty='{"success":true,"totals":{"submissions":0,"accepted":0,"users":0,"problems_solved":0},"problems":[],"languages":[],"verdicts":[],"timeline":[],"problems_solved_dist":[],"attempts_dist":[],"verdict_by_problem":[],"by_region":{},"by_country":{}}'
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

# --- sede/país por login (R2, 2026-08-30) -----------------------------------------------
# Uma varredura de users/*/account.json (molde do sc_cells: login pelo caminho; find|xargs
# = imune a ARG_MAX). Sede = .team.region (texto curado, saneado de :/tab pela lib);
# país = .team.flag minúsculo — a MESMA chave do filtro "Bandeira" do placar (br-pr ≠ br,
# de propósito: os dois lados do recorte têm de casar). Conta sem o dado fica FORA do
# recorte correspondente (o agregado global não muda). Contest com USERS_FROM sem overlay
# local não tem .team ⇒ dimensões vazias, comportamento de sempre.
MAPF="$(mktemp)"
trap 'rm -f "$TMP" "${_HT:-}" "${MAPF:-}"' EXIT
find "$CONTESTSDIR/$C/users" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
  | xargs -0 -r jq -r '[ (((input_filename | split("/"))[-2]) // ""),
                         ((.team.region // "") | gsub("[\t\n]"; " ")),
                         ((.team.flag // "") | ascii_downcase | gsub("[^a-z0-9-]"; "")) ] | @tsv' \
      2>/dev/null > "$MAPF"

START_VAL="${CONTEST_START:-0}"; [[ "$START_VAL" =~ ^[0-9]+$ ]] || START_VAL=0
awk -F: -v START="$START_VAL" -v MF="$MAPF" '
# R2: cada submissão alimenta 1..3 ESCOPOS — g (global), r=<sede>, c=<país> — e o END emite
# as mesmas linhas de sempre prefixadas por "<kind>\t<val>\t". O escopo vira ID inteiro
# (sid): a chave composta id SUBSEP x é separável no END mesmo com sede de texto livre.
function sid(kind, val,   k) {
  k = kind SUBSEP val
  if (!(k in sidx)) { sidx[k] = ++nsc; skind[nsc] = kind; sval[nsc] = val }
  return sidx[k]
}
BEGIN{
  # mapa login\tsede\tpaís lido por getline (nunca NR==FNR: arquivo VAZIO deslocaria tudo)
  while ((getline mline < MF) > 0) {
    n = split(mline, ma, "\t")
    if (n >= 1 && ma[1] != "") { reg[ma[1]] = (n >= 2 ? ma[2] : ""); cty[ma[1]] = (n >= 3 ? ma[3] : "") }
  }
  close(MF)
}
{
  # estatísticas só de usuários normais: descarta privilegiados (.admin/.judge/.cjudge/.staff/.cstaff/.mon)
  if($2 ~ /\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$/) next;
  # tempo RELATIVO ao início: usa o sub_epoch (penúltimo campo, sempre EPOCH absoluto) menos
  # CONTEST_START. mn = minutos relativos; secs = segundos (p/ desempate do 1º a resolver).
  secs=$(NF-1)-START; if(secs<0)secs=0; mn=int(secs/60);
  user=$2; prob=$3; lang=$4; v=$5;
  isac=(v ~ /^Accepted/);
  vc=v; sub(/,.*/,"",vc); sub(/ *\(.*/,"",vc); gsub(/^ +| +$/,"",vc); if(vc=="")vc="?";
  nsl=0; sc[++nsl]=sid("g","");
  if (reg[user] != "") sc[++nsl]=sid("r", reg[user]);
  if (cty[user] != "") sc[++nsl]=sid("c", cty[user]);
  for (si=1; si<=nsl; si++) {
    s=sc[si]; tot[s]++;
    puk=s SUBSEP prob SUBSEP user;
    if(!(puk in solvedAt)){ att[puk]=att[puk]+1; if(isac) solvedAt[puk]=att[puk] }
    vcl[s SUBSEP vc]++; pv[s SUBSEP prob SUBSEP vc]++;
    psub[s SUBSEP prob]++; lsub[s SUBSEP lang]++; users[s SUBSEP user]=1;
    if(!(puk in patt)){ patt[puk]=1; pattn[s SUBSEP prob]++; }
    if(isac){
      acc[s]++; lacc[s SUBSEP lang]++; pacc[s SUBSEP prob]++;
      if(!(puk in psol)){ psol[puk]=1; psoln[s SUBSEP prob]++; }
      luk=s SUBSEP lang SUBSEP user;
      if(!(luk in lsol)){ lsol[luk]=1; lsoln[s SUBSEP lang]++; }
      pk=s SUBSEP prob;
      if(!(pk in fsec) || (secs+0)<(fsec[pk]+0)){ fsec[pk]=secs+0; fmin[pk]=mn+0; fuser[pk]=user; }
      solved[pk]=1;
    }
    b=int((mn+0)/10); if(b<0)b=0; if(b>20000)b=20000;
    tl[s SUBSEP b]++; if(isac)tla[s SUBSEP b]++; if(b>maxb[s]+0)maxb[s]=b;
  }
}
END{
  for(k in psub){ split(k,kk,SUBSEP); pre=skind[kk[1]] "\t" sval[kk[1]] "\t"; p=kk[2];
    printf "%sP\t%s\t%d\t%d\t%d\t%s\t%d\t%d\t%d\n", pre, p, psub[k], pattn[k]+0, psoln[k]+0, (k in fuser?fuser[k]:""), (k in fmin?fmin[k]:-1), pacc[k]+0, (k in fsec?fsec[k]:-1);
  }
  for(k in pv){ split(k,xx,SUBSEP); printf "%s\t%s\tPV\t%s\t%s\t%d\n", skind[xx[1]], sval[xx[1]], xx[2], xx[3], pv[k] }
  for(k in lsub){ split(k,ll,SUBSEP); printf "%s\t%s\tL\t%s\t%d\t%d\t%d\n", skind[ll[1]], sval[ll[1]], ll[2], lsub[k], lacc[k]+0, lsoln[k]+0 }
  for(k in vcl){ split(k,vv,SUBSEP); printf "%s\t%s\tV\t%s\t%d\n", skind[vv[1]], sval[vv[1]], vv[2], vcl[k] }
  for(sn=1; sn<=nsc; sn++){ for(i=0;i<=maxb[sn]+0;i++) if((sn SUBSEP i) in tl)
    printf "%s\t%s\tT\t%d\t%d\t%d\n", skind[sn], sval[sn], i*10, tl[sn SUBSEP i], tla[sn SUBSEP i]+0 }
  for(k in solvedAt){ split(k,aa,SUBSEP); usolv[aa[1] SUBSEP aa[3]]++; adist[aa[1] SUBSEP solvedAt[k]]++ }
  for(k in users){ split(k,uu,SUBSEP); sdist[uu[1] SUBSEP (usolv[k]+0)]++; nu[uu[1]]++ }
  for(k in sdist){ split(k,dd,SUBSEP); printf "%s\t%s\tD\t%d\t%d\n", skind[dd[1]], sval[dd[1]], dd[2], sdist[k] }
  for(k in adist){ split(k,ad,SUBSEP); printf "%s\t%s\tA\t%d\t%d\n", skind[ad[1]], sval[ad[1]], ad[2], adist[k] }
  for(k in solved){ split(k,ss,SUBSEP); nsv[ss[1]]++ }
  for(sn=1; sn<=nsc; sn++) printf "%s\t%s\tG\t%d\t%d\t%d\t%d\n", skind[sn], sval[sn], tot[sn]+0, acc[sn]+0, nu[sn]+0, nsv[sn]+0;
}' "$hist" | jq -R -s --argjson pm "$probmeta" '
  def assemble($r):
    { totals: ( ([ $r[] | select(.[0]=="G") ][0]) as $g | if $g then {submissions:($g[1]|tonumber), accepted:($g[2]|tonumber), users:($g[3]|tonumber), problems_solved:($g[4]|tonumber)} else {submissions:0,accepted:0,users:0,problems_solved:0} end),
      problems: ([ $r[] | select(.[0]=="P") | (.[1]) as $pid | ($pm | map(select(.off==$pid or .raw==$pid or .dot==$pid or .hash==$pid)) | .[0]) as $m | {problem_id:$pid, short_name:($m.short // $pid), full_name:($m.full // ""), submissions:(.[2]|tonumber), attempted:(.[3]|tonumber), solved:(.[4]|tonumber), accepted_subs:(.[7]|tonumber? // 0), first_solver:.[5], first_minute:(.[6]|tonumber), first_seconds:(.[8]|tonumber? // -1), accept_rate:(if (.[3]|tonumber)>0 then ((.[4]|tonumber)/(.[3]|tonumber)) else 0 end), avg_subs:(if (.[3]|tonumber)>0 then (((.[2]|tonumber)/(.[3]|tonumber)*100)|floor)/100 else 0 end)} ] | sort_by(.short_name)),
      languages: ([ $r[] | select(.[0]=="L") | {lang:.[1], submissions:(.[2]|tonumber), accepted:(.[3]|tonumber), solvers:(.[4]|tonumber)} ] | sort_by([-.submissions, .lang])),
      verdicts: ([ $r[] | select(.[0]=="V") | {verdict:.[1], count:(.[2]|tonumber)} ] | sort_by([-.count, .verdict])),
      timeline: ([ $r[] | select(.[0]=="T") | {minute:(.[1]|tonumber), submissions:(.[2]|tonumber), accepted:(.[3]|tonumber)} ] | sort_by(.minute)),
      problems_solved_dist: ([ $r[] | select(.[0]=="D") | {solved:(.[1]|tonumber), users:(.[2]|tonumber)} ] | sort_by(.solved)),
      attempts_dist: ([ $r[] | select(.[0]=="A") | {attempts:(.[1]|tonumber), count:(.[2]|tonumber)} ] | sort_by(.attempts)),
      verdict_by_problem: ([ $r[] | select(.[0]=="PV") | {problem:.[1], verdict:.[2], count:(.[3]|tonumber)} ] | sort_by([.problem, .verdict])) };
  def dim($all; $kind):
    [ $all[] | select(.[0]==$kind) ] | group_by(.[1])
    | map({key:(.[0][1]), value:(assemble(map(.[2:])))}) | from_entries;
  [ split("\n")[] | select(length>0) | split("\t") ] as $all
  | ({success:true} + assemble([ $all[] | select(.[0]=="g") | .[2:] ]))
    + { by_region: (dim($all; "r")), by_country: (dim($all; "c")) }' \
  > "$TMP" 2>/dev/null || printf '%s\n' "$empty" > "$TMP"

# --- nome de quem resolveu primeiro ------------------------------------------------------
# Estatística NUNCA mostra só o login: quem lê procura o NOME do time. Resolvido AQUI (no
# cache) e não na tela, porque são DOIS consumidores — o painel /contest/statistics/ e o
# statistics.html do relatório offline — e nenhum deles tem como consultar contas. São no
# máximo N logins (um por problema), então o custo é irrelevante.
NAMES_F="$(mktemp)"
{
  usrc="$(sed -n 's/^[[:space:]]*USERS_FROM=//p' "$conf" 2>/dev/null | tail -1)"
  usrc="${usrc//\'/}"; usrc="${usrc//\"/}"
  jq -r '[.problems[]?.first_solver, (.by_region // {})[]?.problems[]?.first_solver, (.by_country // {})[]?.problems[]?.first_solver]
         | map(select(. != null and . != "")) | unique[]' "$TMP" 2>/dev/null \
  | while IFS= read -r lg; do
      [[ -n "$lg" ]] || continue
      af="$(account_file "$C" "$lg")"
      [[ -f "$af" ]] || { [[ -n "$usrc" && "$usrc" != *[!A-Za-z0-9._-]* ]] && af="$(account_file "$usrc" "$lg")"; }
      [[ -f "$af" ]] || continue
      jq -c --arg l "$lg" '{login:$l, name:((.team.name // .fullname // "") | gsub("[\n\t]";" "))}' "$af" 2>/dev/null
    done
} > "$NAMES_F"
if [[ -s "$NAMES_F" ]]; then
  jq --slurpfile nm "$NAMES_F" '
      def nm_apply($m): .problems |= map(. + {first_solver_name: ($m[.first_solver] // "")});
      ($nm | map({key:.login, value:.name}) | from_entries) as $m
      | nm_apply($m)
      | .by_region  |= ((. // {}) | with_entries(.value |= nm_apply($m)))
      | .by_country |= ((. // {}) | with_entries(.value |= nm_apply($m)))
    ' "$TMP" > "$TMP.n" 2>/dev/null && mv -f "$TMP.n" "$TMP"
fi
rm -f "$NAMES_F"

mv "$TMP" "$OUT"; trap - EXIT
