#!/usr/bin/env bash
# problem-panorama-gen.sh <outfile> — PANORAMA por problema (id canônico do DONO) agregando as
# submissões de TODA a plataforma: treino livre + as ~174 listas/turmas. Por problema: tentativas,
# aceitos, usuários distintos, quem resolveu, veredictos, linguagens, nº de contests, 1ª/última.
#
# Reconciliação de NAMESPACE (o ponto delicado): o history usa `problemas-apc#`, `moj-problems#`,
# `compiladores-problems#`, OU um OFFSET numérico (legado), enquanto o índice de donos usa `apc#`,
# `obi-problems#`, `monitores#`. A ponte é o campo `collections` do índice: p/ cada dono R#P com
# collections [Ci], os ids do history Ci#P / Ci.P / Ci/P (mesmo nome P, só muda o prefixo) mapeiam p/
# R#P. Legado: o campo-3 é o OFFSET no PROBS -> resolvido pela conf ({off,raw,dot,hash}, igual ao
# stats-gen.sh). Ids sem dono ficam sob o próprio id canônico (o /problems/my-stats filtra ao dono,
# então nunca aparecem p/ ninguém). Precompute (o handler serve o cache filtrado).
set -u
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
_SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_SDIR/../api/v1/lib/users.sh" 2>/dev/null   # emit_history_stream / store_v2

OUT="${1:-}"; [[ -n "$OUT" ]] || { echo "uso: problem-panorama-gen.sh <outfile>" >&2; exit 1; }
IDX="$CONTESTSDIR/treino/var/problem-owners.json"
mkdir -p "$(dirname "$OUT")" 2>/dev/null
TMP="$(mktemp "$OUT.XXXXXX")" || exit 1
NORM="$(mktemp)"; ALIAS="$(mktemp)"; CMAP="$(mktemp)"
trap 'rm -f "$TMP" "$NORM" "$ALIAS" "$CMAP" "${_HT:-}"' EXIT

# 1) alias historyId -> ownerId (do índice de donos). repo + cada coleção viram prefixos possíveis.
if [[ -f "$IDX" ]]; then
  # prefixos possíveis do history por REPO = união dos `collections` de TODOS os problemas do repo:
  # nem todo problema do apc tem collections:[problemas-apc], mas o REPO como um todo tem, então cada
  # problema herda o prefixo do repo (senão `apc#cinema` não casaria `problemas-apc#cinema`).
  jq -r '
    (.problems | group_by(.repo) | map({key:.[0].repo, value:(map(.collections // [])|add|unique)}) | from_entries) as $rp
    | .problems[] | .id as $oid | .prob as $P | .repo as $R
    | (([$R] + ($rp[$R] // [])) | unique)[] as $C
    | "\($C)#\($P)\t\($oid)", "\($C).\($P)\t\($oid)", "\($C)/\($P)\t\($oid)"' "$IDX" 2>/dev/null > "$ALIAS"
  jq -r '.problems[] | "\(.id)\t\(.id)"' "$IDX" 2>/dev/null >> "$ALIAS"
fi
declare -A ALIASMAP
while IFS=$'\t' read -r _hk _oid; do [[ -n "$_hk" ]] && ALIASMAP["$_hk"]="$_oid"; done < "$ALIAS"

# 2) normaliza cada submissão -> "oid\tuser\tlangCanon\tverdictCanon\tcontest\tsub_epoch" em $NORM.
#    verdict/lang canonicalizados como no handlers/treino/problem-stats.sh. Descarta privilegiados.
norm_awk='
  function vcanon(v,  x){ x=v; sub(/,.*/,"",x); sub(/ *\(.*/,"",x); gsub(/^ +| +$/,"",x);
    if(x ~ /^Accepted/) return "Accepted";
    if(x ~ /^Wrong/) return "Wrong Answer";
    if(x ~ /^Time Limit/) return "Time Limit Exceeded";
    if(x ~ /^(Runtime|Possible Runtime|RunTime)/) return "Runtime Error";
    if(x ~ /^(Compilation|Language)/) return "Compilation Error";
    if(x=="") return "?"; return "Outro" }
  function lcanon(l,  u){ u=toupper(l); gsub(/[[:space:]]/,"",u);
    if(u=="C++"||u=="CC"||u=="CXX"||u=="HPP") return "cpp";
    if(u=="H") return "c"; if(u=="") return "?"; return tolower(u) }
  FILENAME==MAPF { split($0,a,"\t"); R[a[1]]=a[2]; next }   # arquivo-mapa campo3->oid (TAB; sem ":")
                                                            # (por NOME, não NR==FNR: mapa vazio não some com o history)
  {
    if($2 ~ /\.(admin|judge|cjudge|staff|mon)$/) next;
    f3=$3;
    oid = (f3 in R ? R[f3] : (KEEP ? f3 : ""));
    if(oid=="") next;
    printf "%s\t%s\t%s\t%s\t%s\t%s\n", oid, $2, lcanon($4), vcanon($5), CID, $(NF-1);
  }'

: > "$NORM"
set +o noglob; shopt -s nullglob
for cdir in "$CONTESTSDIR"/*/; do
  cdir="${cdir%/}"; c="${cdir##*/}"
  [[ -f "$cdir/conf" ]] || continue
  if store_v2 "$c"; then
    # store-v2 (treino & afins): campo-3 já é o id canônico -> resolve pelo ALIAS; sem dono, mantém.
    _HT="$(mktemp)"; emit_history_stream "$c" > "$_HT" 2>/dev/null
    awk -F: -v KEEP=1 -v CID="$c" -v MAPF="$ALIAS" "$norm_awk" "$ALIAS" "$_HT" 2>/dev/null >> "$NORM"
    rm -f "$_HT"; _HT=""
  else
    hist="$cdir/controle/history"; [[ -f "$hist" ]] || continue
    # legado: campo-3 = OFFSET no PROBS -> CMAP({off,raw,dot,hash}->owner-ou-canon) da conf.
    ( PROBS=(); source "$cdir/conf" 2>/dev/null
      for ((i=0; i<${#PROBS[@]}; i+=5)); do
        praw="${PROBS[i+1]:-}"; [[ -n "$praw" ]] || continue
        canon="${PROBS[i+4]:-}"; [[ "$canon" == *"#"* ]] || canon="${praw//\//#}"
        owner="${ALIASMAP[$canon]:-$canon}"
        Ci="${canon%%#*}"; Pp="${canon#*#}"
        printf '%s\t%s\n%s\t%s\n%s\t%s\n%s\t%s\n' "$i" "$owner" "$canon" "$owner" "$Ci/$Pp" "$owner" "$Ci.$Pp" "$owner"
      done ) > "$CMAP" 2>/dev/null
    awk -F: -v KEEP=0 -v CID="$c" -v MAPF="$CMAP" "$norm_awk" "$CMAP" "$hist" 2>/dev/null >> "$NORM"
  fi
done
shopt -u nullglob

# 3) agrega o NORM por oid (streaming, memória baixa) -> linhas P/V/L; jq monta o mapa {id:stats}.
awk -F'\t' '
  { oid=$1; u=$2; lang=$3; v=$4; c=$5; se=$6+0;
    subm[oid]++; if(v=="Accepted") acc[oid]++;
    vc[oid SUBSEP v]++; lc[oid SUBSEP lang]++; if(v=="Accepted") lac[oid SUBSEP lang]++;
    if(!((oid SUBSEP u) in ug)){ ug[oid SUBSEP u]=1; du[oid]++ }
    if(v=="Accepted" && !((oid SUBSEP u) in sg)){ sg[oid SUBSEP u]=1; solv[oid]++ }
    if(!((oid SUBSEP c) in cg)){ cg[oid SUBSEP c]=1; cc[oid]++ }
    if(!(oid in fst) || se<fst[oid]) fst[oid]=se;
    if(!(oid in lst) || se>lst[oid]) lst[oid]=se; }
  END {
    for(o in subm) printf "P\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n", o, subm[o], acc[o]+0, du[o]+0, solv[o]+0, cc[o]+0, fst[o]+0, lst[o]+0;
    for(k in vc){ split(k,x,SUBSEP); printf "V\t%s\t%s\t%d\n", x[1], x[2], vc[k] }
    for(k in lc){ split(k,x,SUBSEP); printf "L\t%s\t%s\t%d\t%d\n", x[1], x[2], lc[k], lac[k]+0 }
  }' "$NORM" \
| jq -R -s --argjson now "$EPOCHSECONDS" '
    [ split("\n")[] | select(length>0) | split("\t") ] as $r
    | ($r | map(select(.[0]=="V")) | group_by(.[1])
        | map({key:.[0][1], value:(map({verdict:.[2], count:(.[3]|tonumber)})|sort_by(-.count))}) | from_entries) as $vm
    | ($r | map(select(.[0]=="L")) | group_by(.[1])
        | map({key:.[0][1], value:(map({lang:.[2], submissions:(.[3]|tonumber), accepted:(.[4]|tonumber)})|sort_by(-.submissions))}) | from_entries) as $lm
    | { success:true, generated_at:$now,
        problems: ( $r | map(select(.[0]=="P")) | map( .[1] as $id
          | { id:$id, attempts:(.[2]|tonumber), accepts:(.[3]|tonumber), distinct_users:(.[4]|tonumber),
              solvers:(.[5]|tonumber), contests_count:(.[6]|tonumber), first:(.[7]|tonumber), last:(.[8]|tonumber),
              acceptance_rate:(if (.[2]|tonumber)>0 then (((.[3]|tonumber)/(.[2]|tonumber)*1000)|floor)/1000 else 0 end),
              verdicts:($vm[$id] // []), languages:($lm[$id] // []) } )
          | map({key:.id, value:.}) | from_entries ) }' \
  > "$TMP" 2>/dev/null || printf '%s\n' '{"success":true,"generated_at":0,"problems":{}}' > "$TMP"
[[ -s "$TMP" ]] || printf '%s\n' '{"success":true,"generated_at":0,"problems":{}}' > "$TMP"
# não ENVENENA um cache bom com resultado vazio (falha transitória do jq): só troca se veio conteúdo
# ou se ainda não há cache. Falha -> mantém o anterior (mtime velho -> o handler tenta de novo).
if [[ -s "$TMP" ]] && { [[ ! -f "$OUT" ]] || [[ "$(jq '.problems|length' "$TMP" 2>/dev/null || echo 0)" != "0" ]]; }; then
  mv "$TMP" "$OUT"
else
  rm -f "$TMP"
fi
