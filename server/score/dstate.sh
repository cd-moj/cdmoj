#!/usr/bin/env bash
#
# dstate.sh <contest>
#
# Materializa os arquivos de estado por-problema que os geradores icpc/treino leem:
#
#   controle/<login>.d/<pidx>   ->  JAACERTOU=<seg> TENTATIVAS=<n> PENDING=<0|1>
#
# O pipeline ASSÍNCRONO (server/daemons/judged.sh) grava controle/history e
# data/<login> com o problem_id TEXTUAL, mas nunca escreve os .d/<pidx> (no MOJ
# legado quem os escrevia era o juiz). Sem eles, o placar icpc/obi de um contest novo
# fica vazio. Este script reconstrói os .d a partir do history (idempotente).
#
# Mapeia o problem_id textual -> offset (pidx) via SC_CANON (forma 'coleção#problema'),
# tolerando também o numérico/barra/ponto de linhas legadas. NÃO reescreve history/data.
#
#   JAACERTOU  = tempo RELATIVO (segundos) do 1º Accepted = sub_epoch(campo 6) - CONTEST_START,
#                senão 0. Usamos o campo 6 (sempre o epoch absoluto) e subtraímos o início —
#                o campo 1 não é confiável (no caminho de fila/pull ele fica em epoch absoluto).
#   TENTATIVAS = nº de tentativas que contam penalidade até (e incluindo) o 1º AC; se não
#                resolvido, todas. Não conta pendentes, Compilation Error nem Judge Error.
#   PENDING    = 1 se houver submissão "Not Answered Yet" OU congelada (>= FREEZE_TIME).
#   FREEZE     = submissões com sub_epoch >= FREEZE_TIME não revelam o AC (placar congela).
set -u
SC_PROG="dstate"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/score-common.sh"

sc_load "${1:-}"
START="${CONTEST_START:-0}"; [[ "$START" =~ ^[0-9]+$ ]] || START=0
FREEZE="${FREEZE_TIME:-0}";  [[ "$FREEZE" =~ ^[0-9]+$ ]] || FREEZE=0

HIST="$CONTESTDIR/controle/history"
[[ -f "$HIST" ]] || exit 0

# tabela "key<TAB>pidx" -> awk (robusto a ids com qualquer caractere). Para cada problema
# emitimos a forma canônica '#' e as legadas (offset numérico, barra, ponto).
MAP="$(mktemp 2>/dev/null)" || exit 1
trap 'rm -f "$MAP"' EXIT
for ((p=0; p<SC_NPROB; p++)); do
  pidx="${SC_PIDX[p]}"; canon="${SC_CANON[p]}"
  printf '%s\t%s\n' "$canon"          "$pidx"   # canônico 'coleção#problema'
  printf '%s\t%s\n' "$pidx"           "$pidx"   # offset numérico (legado)
  printf '%s\t%s\n' "${canon//#//}"   "$pidx"   # barra (legado)
  printf '%s\t%s\n' "${canon//#/.}"   "$pidx"   # ponto (contest.js pré-correção)
done > "$MAP"

# Duas passadas sobre o history (truque FNR==NR): 1ª acha o epoch/tempo do 1º AC por
# (login,pidx); 2ª conta tentativas até o AC (ou todas, se não resolvido) e pendências.
awk -F: -v mapf="$MAP" -v START="$START" -v FREEZE="$FREEZE" '
  BEGIN{ while ((getline line < mapf) > 0){ n=split(line,a,"\t"); if(n==2) M[a[1]]=a[2] } }
  function getv(   v,i){ v=$5; for(i=6;i<=NF-2;i++) v=v":"$i; return v }   # veredicto (sem epoch:subid)
  function counts(v){
    if (v ~ /Not Answered Yet/)   return 0
    if (v ~ /^Compilation Error/) return 0
    if (v ~ /^Judge Error/)       return 0
    if (v ~ /^No_?Servers/)       return 0
    return 1
  }
  function frozen(ep){ return (FREEZE+0 > 0 && ep+0 >= FREEZE+0) }   # >= freeze: resultado escondido
  FNR==NR {                                   # passada 1: 1º AC (antes do freeze) por chave
    prob=$3; if (!(prob in M)) next
    key=$2 SUBSEP M[prob]; v=getv(); ep=$6+0
    if (v ~ /Accepted/ && !frozen(ep)){
      if (!(key in ACEP) || ep < ACEP[key]){ ACEP[key]=ep; rel=ep-(START+0); if(rel<0)rel=0; ACTM[key]=rel } }
    next
  }
  {                                           # passada 2: tentativas + pendências
    prob=$3; if (!(prob in M)) next
    login=$2; pidx=M[prob]; key=login SUBSEP pidx; v=getv(); ep=$6+0
    LOGIN[key]=login; PIDX[key]=pidx; SEEN[key]=1
    if (v ~ /Not Answered Yet/) PEND[key]=1
    if (frozen(ep)) PEND[key]=1                # congelado: aparece como pendente, AC escondido
    if (counts(v) && (!(key in ACEP) || ep <= ACEP[key])) ATT[key]++
  }
  END{
    for (k in SEEN){
      printf "%s\t%s\t%s\t%s\t%s\n", LOGIN[k], PIDX[k],
        ((k in ACTM)?ACTM[k]:0), ((k in ATT)?ATT[k]:0), ((k in PEND)?PEND[k]:0)
    }
  }
' "$HIST" "$HIST" | while IFS=$'\t' read -r login pidx ja att pe; do
  [[ "$login" =~ ^[A-Za-z0-9._-]+$ && "$pidx" =~ ^[0-9]+$ ]] || continue
  d="$CONTESTDIR/controle/$login.d"
  mkdir -p "$d" 2>/dev/null || continue
  tmp="$d/.$pidx.tmp.$$"
  { printf 'JAACERTOU=%s\n' "${ja:-0}"
    printf 'TENTATIVAS=%s\n' "${att:-0}"
    printf 'PENDING=%s\n' "${pe:-0}"; } > "$tmp" && mv -f "$tmp" "$d/$pidx"
done
