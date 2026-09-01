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

empty='{"success":true,"totals":{"submissions":0,"accepted":0,"users":0,"problems_solved":0,"enrolled":0,"absent":0},"problems":[],"languages":[],"verdicts":[],"timeline":[],"problems_solved_dist":[],"attempts_dist":[],"verdict_by_problem":[],"by_region":{},"by_country":{}}'
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
# país = o PREFIXO do .team.flag minúsculo (br-pr → br): time brasileiro declara bandeira
# de ESTADO, e "estatísticas do Brasil" tem de juntá-los — na Maratona 2026 só 14 de 1500+
# tinham a bandeira `br` crua. O filtro "Bandeira" do placar casa por prefixo do mesmo
# jeito (país agrega os estados; estado segue selecionável). Conta sem o dado fica FORA do
# recorte correspondente (o agregado global não muda). Contest com USERS_FROM sem overlay
# local não tem .team ⇒ dimensões vazias, comportamento de sempre.
MAPF="$(mktemp)"; RGF="$(mktemp)"
trap 'rm -f "$TMP" "${_HT:-}" "${MAPF:-}" "${RGF:-}"' EXIT
find "$CONTESTSDIR/$C/users" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
  | xargs -0 -r jq -r '[ (((input_filename | split("/"))[-2]) // ""),
                         ((.team.region // "") | gsub("[\t\n]"; " ")),
                         ((.team.flag // "") | ascii_downcase | gsub("[^a-z0-9-]"; "") | (split("-") | .[0])),
                         (if .disqualified == true then "1" else "0" end),
                         ((.team.name // .fullname // "") | gsub("[\t\n]"; " ")) ] | @tsv' \
      2>/dev/null > "$MAPF"

# Nós da ÁRVORE de regions.json (país › região/supersede › sede): a estatística oferece o
# MESMO seletor de Sede do placar, e os nós de cima só existem AGREGANDO por regex de login
# (o regionMatch do placar: regex no login OU nome == .team.region). Cada nó vira um
# recorte `r:<nome>` em by_region. Regex inválida p/ ERE é descartada (o placar a ignora
# igual, via safeRe). Sem regions.json = só as sedes do .team.region, como antes.
if [[ -s "$CONTESTSDIR/$C/regions.json" ]]; then
  # 3ª coluna: a flag `view` do nó (recorte SOBREPOSTO — supersede/femininos): a fatia
  # existe p/ VISUALIZAR, e somá-la com as sedes conta times em dobro. O flag viaja até o
  # by_region (campo `view:true`) e a UI avisa. ⚠ fatias são chaveadas por NOME: nó-view
  # com o MESMO nome de um nó real marcaria os dois — dê nomes próprios aos recortes.
  jq -r 'def flat: .[]? | ([(.name // ""), (.regex // ""), ((.view // false)|tostring)] | @tsv), ((.subregions // []) | flat); flat' \
      "$CONTESTSDIR/$C/regions.json" 2>/dev/null \
  | while IFS=$'\t' read -r _nm _re _vw; do
      [[ -n "$_nm" ]] || continue
      if [[ -n "$_re" ]]; then
        printf '' | grep -qE -- "$_re" 2>/dev/null; (( $? == 2 )) && continue
      fi
      printf '%s\t%s\t%s\n' "$_nm" "$_re" "$_vw"
    done > "$RGF"
fi

START_VAL="${CONTEST_START:-0}"; [[ "$START_VAL" =~ ^[0-9]+$ ]] || START_VAL=0
# convidados (coortes unranked, ex.: CCL): competem e aparecem nos eventos/comparação,
# mas NÃO entram em top_teams/performance — população oficial, como no placar
UNRX=""
if [[ -s "$CONTESTSDIR/$C/cohorts.json" ]]; then
  UNRX="$(jq -r '[(.cohorts // [])[] | select(.unranked == true) | .regex | select(. != "")] | join("|")' \
    "$CONTESTSDIR/$C/cohorts.json" 2>/dev/null)"
fi
awk -F: -v START="$START_VAL" -v MF="$MAPF" -v RF="$RGF" -v PEN="${PENALTY_MINUTES:-20}" -v UNRX="$UNRX" '
# R2: cada submissão alimenta N ESCOPOS — g (global), r=<sede/nó da árvore>, c=<país> — e o
# END emite as mesmas linhas de sempre prefixadas por "<kind>\t<val>\t". O escopo vira ID
# inteiro (sid): a chave composta id SUBSEP x é separável no END mesmo com sede livre.
function sid(kind, val,   k) {
  k = kind SUBSEP val
  if (!(k in sidx)) { sidx[k] = ++nsc; skind[nsc] = kind; sval[nsc] = val }
  return sidx[k]
}
# escopos de UM login (g/r/c + nós da árvore), memoizados em us_/uscn — usados pela
# passada de INSCRITOS (BEGIN) e pelo corpo por-submissão (o cache é compartilhado)
function calc_scopes(user,   r_, s_, i_, hit, useen) {
  split("", useen)
  n_u = 0; us_[user, ++n_u] = sid("g", "")
  r_ = reg[user]
  if (r_ != "") { s_ = sid("r", r_); useen[s_] = 1; us_[user, ++n_u] = s_ }
  if (cty[user] != "") us_[user, ++n_u] = sid("c", cty[user])
  for (i_ = 1; i_ <= nrg; i_++) {
    hit = 0
    if (rgre[i_] != "" && user ~ rgre[i_]) hit = 1
    else if (r_ != "" && tolower(rgname[i_]) == tolower(r_)) hit = 1
    if (hit) { s_ = sid("r", rgname[i_]); if (!(s_ in useen)) { useen[s_] = 1; us_[user, ++n_u] = s_ } }
  }
  uscn[user] = n_u
}
BEGIN{
  # mapa login\tsede\tpaís lido por getline (nunca NR==FNR: arquivo VAZIO deslocaria tudo)
  while ((getline mline < MF) > 0) {
    n = split(mline, ma, "\t")
    if (n >= 1 && ma[1] != "") {
      reg[ma[1]] = (n >= 2 ? ma[2] : ""); cty[ma[1]] = (n >= 3 ? ma[3] : "")
      if (n >= 4 && ma[4] == "1") dsq[ma[1]] = 1   # desclassificado: fora de TUDO (como no placar)
      if (n >= 5) tnm[ma[1]] = ma[5]               # nome do time (teams_idx/top_teams)
    }
  }
  close(MF)
  # nós da árvore de regions.json: nome \t regex \t view (regex já validada pelo gerador)
  while ((getline mline < RF) > 0) {
    n = split(mline, ma, "\t")
    if (n >= 1 && ma[1] != "") {
      nrg++; rgname[nrg] = ma[1]; rgre[nrg] = (n >= 2 ? ma[2] : "")
      if (n >= 3 && ma[3] == "true") viewname[ma[1]] = 1
    }
  }
  close(RF)
  # PASSADA DE INSCRITOS (2026-08-31, relato do Carlos na LATAM): a página contava só quem
  # SUBMETEU (users[] nasce de linha de history) — 43 zeros no placar viravam 2 na
  # estatística. Todo login NÃO-privilegiado do mapa de contas conta como INSCRITO em cada
  # escopo dele; o END soma os ausentes (enr-nu) no bucket 0 e emite enrolled no G.
  for (u_ in reg) {
    if (u_ in dsq) continue
    if (u_ ~ /\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$/) continue
    calc_scopes(u_)
    for (si_ = 1; si_ <= uscn[u_]; si_++) enr[us_[u_, si_]]++
  }
}
{
  # estatísticas só de usuários normais: descarta privilegiados (.admin/.judge/.cjudge/.staff/.cstaff/.mon)
  if($2 ~ /\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$/) next;
  if($2 in dsq) next;   # desclassificado: submissões fora da estatística (mesma população do placar)
  # tempo RELATIVO ao início: usa o sub_epoch (penúltimo campo, sempre EPOCH absoluto) menos
  # CONTEST_START. mn = minutos relativos; secs = segundos (p/ desempate do 1º a resolver).
  secs=$(NF-1)-START; if(secs<0)secs=0; mn=int(secs/60);
  user=$2; prob=$3; lang=$4; v=$5;
  isac=(v ~ /^Accepted/);
  vc=v; sub(/,.*/,"",vc); sub(/ *\(.*/,"",vc); gsub(/^ +| +$/,"",vc); if(vc=="")vc="?";
  # escopos POR USUÁRIO, computados uma vez (regex de cada nó da árvore contra o login —
  # como o regionMatch do placar; dedup: nó com o mesmo nome da sede não conta duas vezes)
  if (!(user in uscn)) calc_scopes(user)   # inscrito já vem memoizado da passada do BEGIN
  for (si=1; si<=uscn[user]; si++) {
    s=us_[user, si]; tot[s]++;
    puk=s SUBSEP prob SUBSEP user;
    if(!(puk in solvedAt)){ att[puk]=att[puk]+1; if(isac) solvedAt[puk]=att[puk] }
    vcl[s SUBSEP vc]++; pv[s SUBSEP prob SUBSEP vc]++;
    psub[s SUBSEP prob]++; lsub[s SUBSEP lang]++; users[s SUBSEP user]=1;
    if(!(puk in patt)){ patt[puk]=1; pattn[s SUBSEP prob]++; }
    if(isac){
      acc[s]++; lacc[s SUBSEP lang]++; pacc[s SUBSEP prob]++;
      if(!(puk in psol)){ psol[puk]=1; psoln[s SUBSEP prob]++;
        # Estatísticas 2.0 (01/09): o 1º AC do (time,problema) alimenta média de tempo,
        # tentativas-até-AC, dirt (tentativas-1 = erros de quem resolve) e a língua do AC
        acsum[s SUBSEP prob] += mn; trysum[s SUBSEP prob] += solvedAt[puk]
        pl_[s SUBSEP prob SUBSEP lang]++
        if (s == 1) { evm[prob SUBSEP user] = mn; evt[prob SUBSEP user] = solvedAt[puk] }
      }
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
    printf "%sP\t%s\t%d\t%d\t%d\t%s\t%d\t%d\t%d\t%d\t%d\n", pre, p, psub[k], pattn[k]+0, psoln[k]+0, (k in fuser?fuser[k]:""), (k in fmin?fmin[k]:-1), pacc[k]+0, (k in fsec?fsec[k]:-1), acsum[k]+0, trysum[k]+0;
  }
  for(k in pl_){ split(k,pp,SUBSEP); printf "%s\t%s\tPL\t%s\t%s\t%d\n", skind[pp[1]], sval[pp[1]], pp[2], pp[3], pl_[k] }
  # eventos de AC (SÓ global): base da corrida de problemas e da comparação de times
  for(k in evm){ split(k,ee,SUBSEP);
    printf "g\t\tE\t%s\t%s\t%d\t%d\n", ee[2], ee[1], evm[k], evt[k] }
  # por-usuário global: resolvidos + penalidade ICPC + 1º AC (percentis/top teams)
  for(k in evm){ split(k,ee,SUBSEP); u_=ee[2]
    usolv2[u_]++
    upen[u_] += evm[k] + PEN * (evt[k] - 1)
    if (!(u_ in ufst) || evm[k] < ufst[u_]) ufst[u_] = evm[k]
  }
  for(u_ in usolv2){
    if (UNRX != "" && u_ ~ UNRX) continue   # convidado (coorte unranked) fora do ranking oficial
    printf "g\t\tU\t%s\t%d\t%d\t%d\t%s\n", u_, usolv2[u_], upen[u_], ufst[u_], (u_ in tnm ? tnm[u_] : u_)
  }
  for(k in pv){ split(k,xx,SUBSEP); printf "%s\t%s\tPV\t%s\t%s\t%d\n", skind[xx[1]], sval[xx[1]], xx[2], xx[3], pv[k] }
  for(k in lsub){ split(k,ll,SUBSEP); printf "%s\t%s\tL\t%s\t%d\t%d\t%d\n", skind[ll[1]], sval[ll[1]], ll[2], lsub[k], lacc[k]+0, lsoln[k]+0 }
  for(k in vcl){ split(k,vv,SUBSEP); printf "%s\t%s\tV\t%s\t%d\n", skind[vv[1]], sval[vv[1]], vv[2], vcl[k] }
  for(sn=1; sn<=nsc; sn++){ for(i=0;i<=maxb[sn]+0;i++) if((sn SUBSEP i) in tl)
    printf "%s\t%s\tT\t%d\t%d\t%d\n", skind[sn], sval[sn], i*10, tl[sn SUBSEP i], tla[sn SUBSEP i]+0 }
  for(k in solvedAt){ split(k,aa,SUBSEP); usolv[aa[1] SUBSEP aa[3]]++; adist[aa[1] SUBSEP solvedAt[k]]++ }
  for(k in users){ split(k,uu,SUBSEP); sdist[uu[1] SUBSEP (usolv[k]+0)]++; nu[uu[1]]++ }
  # ausentes (inscritos sem submissão) entram no bucket 0 — a distribuição casa com o placar
  for(sn=1; sn<=nsc; sn++){ miss = enr[sn]+0 - nu[sn]+0; if (miss > 0) sdist[sn SUBSEP 0] += miss }
  for(k in sdist){ split(k,dd,SUBSEP); printf "%s\t%s\tD\t%d\t%d\n", skind[dd[1]], sval[dd[1]], dd[2], sdist[k] }
  for(k in adist){ split(k,ad,SUBSEP); printf "%s\t%s\tA\t%d\t%d\n", skind[ad[1]], sval[ad[1]], ad[2], adist[k] }
  for(k in solved){ split(k,ss,SUBSEP); nsv[ss[1]]++ }
  for(sn=1; sn<=nsc; sn++) printf "%s\t%s\tG\t%d\t%d\t%d\t%d\t%d\n", skind[sn], sval[sn], tot[sn]+0, acc[sn]+0, nu[sn]+0, nsv[sn]+0, enr[sn]+0;
  for(sn=1; sn<=nsc; sn++) if (skind[sn]=="r" && (sval[sn] in viewname)) printf "r\t%s\tW\t1\n", sval[sn];
}' "$hist" | jq -R -s --argjson pm "$probmeta" '
  def assemble($r):
    { totals: ( ([ $r[] | select(.[0]=="G") ][0]) as $g | if $g then
          (($g[3]|tonumber)) as $u | (($g[5]|tonumber? // 0)) as $e
          | {submissions:($g[1]|tonumber), accepted:($g[2]|tonumber), users:$u, problems_solved:($g[4]|tonumber),
             enrolled:(if $e > $u then $e else $u end), absent:(if $e > $u then ($e - $u) else 0 end)}
        else {submissions:0,accepted:0,users:0,problems_solved:0,enrolled:0,absent:0} end),
      view: (([ $r[] | select(.[0]=="W") ] | length) > 0),
      problems: ((([ $r[] | select(.[0]=="PL") | {p:.[1], l:.[2], n:(.[3]|tonumber)} ]
                 | group_by(.p) | map({key:.[0].p, value:(map({key:.l, value:.n}) | from_entries)}) | from_entries)) as $PL
        | ([ $r[] | select(.[0]=="P") | (.[1]) as $pid | ($pm | map(select(.off==$pid or .raw==$pid or .dot==$pid or .hash==$pid)) | .[0]) as $m
        | (.[4]|tonumber) as $slv | (.[9]|tonumber? // 0) as $acsum | (.[10]|tonumber? // 0) as $trysum
        | {problem_id:$pid, short_name:($m.short // $pid), full_name:($m.full // ""), submissions:(.[2]|tonumber), attempted:(.[3]|tonumber), solved:$slv, accepted_subs:(.[7]|tonumber? // 0), first_solver:.[5], first_minute:(.[6]|tonumber), first_seconds:(.[8]|tonumber? // -1), accept_rate:(if (.[3]|tonumber)>0 then ($slv/(.[3]|tonumber)) else 0 end), avg_subs:(if (.[3]|tonumber)>0 then (((.[2]|tonumber)/(.[3]|tonumber)*100)|floor)/100 else 0 end),
           avg_ac_min:(if $slv>0 then (($acsum/$slv)|floor) else null end),
           tries_per_ac:(if $slv>0 then ((($trysum/$slv)*10)|floor/10) else null end),
           dirt:(if $trysum>0 then (((($trysum-$slv)/$trysum)*1000)|floor/1000) else null end),
           ac_langs:($PL[$pid] // {})} ] | sort_by(.short_name))),
      languages: ([ $r[] | select(.[0]=="L") | {lang:.[1], submissions:(.[2]|tonumber), accepted:(.[3]|tonumber), solvers:(.[4]|tonumber)} ] | sort_by([-.submissions, .lang])),
      verdicts: ([ $r[] | select(.[0]=="V") | {verdict:.[1], count:(.[2]|tonumber)} ] | sort_by([-.count, .verdict])),
      timeline: ([ $r[] | select(.[0]=="T") | {minute:(.[1]|tonumber), submissions:(.[2]|tonumber), accepted:(.[3]|tonumber)} ] | sort_by(.minute)),
      problems_solved_dist: ([ $r[] | select(.[0]=="D") | {solved:(.[1]|tonumber), users:(.[2]|tonumber)} ] | sort_by(.solved)),
      attempts_dist: ([ $r[] | select(.[0]=="A") | {attempts:(.[1]|tonumber), count:(.[2]|tonumber)} ] | sort_by(.attempts)),
      verdict_by_problem: ([ $r[] | select(.[0]=="PV") | {problem:.[1], verdict:.[2], count:(.[3]|tonumber)} ] | sort_by([.problem, .verdict])),
      dirt: (([ $r[] | select(.[0]=="P") | (.[10]|tonumber? // 0) ] | add // 0) as $ts
             | ([ $r[] | select(.[0]=="P") | (.[4]|tonumber) ] | add // 0) as $sv
             | (if $ts>0 then (((($ts-$sv)/$ts)*1000)|floor/1000) else null end)) };
  def pctl($a; $q): (if ($a|length)==0 then null else $a[(((($a|length)-1)*$q)|floor)] end);
  def dim($all; $kind):
    [ $all[] | select(.[0]==$kind) ] | group_by(.[1])
    | map({key:(.[0][1]), value:(assemble(map(.[2:])))}) | from_entries;
  [ split("\n")[] | select(length>0) | split("\t") ] as $all
  | [ $all[] | select(.[0]=="g") | .[2:] ] as $g
  | ([ $g[] | select(.[0]=="E") | [.[1], .[2], (.[3]|tonumber), (.[4]|tonumber)] ] | sort_by(.[2])) as $EV
  | ([ $g[] | select(.[0]=="U") | {login:.[1], solved:(.[2]|tonumber), penalty:(.[3]|tonumber), first_ac:(.[4]|tonumber), name:(.[5] // .[1])} ]) as $UU
  | ([ $UU[].solved ] | sort) as $SO | ([ $UU[].penalty ] | sort) as $PE | ([ $UU[].first_ac ] | sort) as $FA
  | ({success:true} + assemble($g))
    + { by_region: (dim($all; "r")), by_country: (dim($all; "c")),
        ac_events: $EV,
        teams_idx: ($UU | map({key:.login, value:.name}) | from_entries),
        top_teams: ($UU | sort_by([-.solved, .penalty]) | .[:10] | map({login, name, solved, penalty})),
        performance: (if ($UU|length)==0 then null else
          { teams_with_ac: ($UU|length),
            solved:  {mean:((([ $UU[].solved ]|add)/($UU|length)*100|floor)/100), median:pctl($SO; 0.5), q1:pctl($SO; 0.25), q3:pctl($SO; 0.75), p90:pctl($SO; 0.9)},
            penalty: {mean:((([ $UU[].penalty ]|add)/($UU|length))|floor), median:pctl($PE; 0.5), q1:pctl($PE; 0.25), q3:pctl($PE; 0.75)},
            first_ac_median: pctl($FA; 0.5) } end) }' \
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
