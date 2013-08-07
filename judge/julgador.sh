#!/bin/bash

source #CONFDIR#/judge.conf
source #CONFDIR#/common.conf
source #SCRIPTSDIR#/enviar-spoj.sh
source #SCRIPTSDIR#/enviar-uri.sh

mkdir -p $SUBMISSIONDIR-julgados

#make $SUBMISSIONDIR is world writtable
chmod 777 $SUBMISSIONDIR

#ordem de ARQ: $CONTEST:$AGORA:$RAND:$LOGIN:$PROBLEMA:$FILETYPE
for ARQ in $SUBMISSIONDIR/*; do
  if [[ ! -e "$ARQ" ]]; then
    continue
  fi
  N="$(basename $ARQ)"
  CONTEST="$(cut -d: -f1 <<< "$N")"
  ID="$(cut -d: -f2,3 <<< "$N")"
  LOGIN="$(cut -d: -f4 <<< "$N")"
  PROBID="$(cut -d: -f5 <<< "$N")"
  LING="$(cut -d: -f6 <<< "$N")"
  #LING="$(file $ARQ|awk '{print $3}')"

  if [[ "$CONTEST" == "admin" ]]; then
    LOGIN="$(cut -d: -f2 <<< "$N")"
    FILENAME="$(cut -d: -f3 <<< "$N")"
    TMPDIR=$(mktemp -d)
    tar xf "$ARQ" -C $TMPDIR/
    CAMINHO="$(dirname $(find $TMPDIR -name 'contest-description.txt'))"
    bash #SCRIPTSDIR#/../bin/cria-contest.sh $CAMINHO
    rm -rf "$ARQ" $TMPDIR

    continue
  fi

  #carregar contest
  source $CONTESTSDIR/$CONTEST/conf

  if [[ "$PROBID" == "login" && ! -d $CONTESTSDIR/$CONTEST/controle/$LOGIN.d ]]; then
    mkdir -p $CONTESTSDIR/$CONTEST/controle/$LOGIN.d
    rm -f "$ARQ"

    {
      NOME="$(grep "^$LOGIN:" $CONTESTSDIR/$CONTEST/passwd|cut -d: -f3)"
      printf "<td>$NOME</td>"
      TAMARRAY=${#PROBS[@]}
      for ((prob=0;prob<TAMARRAY;prob+=5)); do
          printf "<td></td>"
      done
      printf "<td>0</td></tr>"
    } > $CONTESTSDIR/$CONTEST/controle/$LOGIN.score
    echo "<tr><td>--</td>$(<$CONTESTSDIR/$CONTEST/controle/$LOGIN.score)" >> $CONTESTSDIR/$CONTEST/controle/SCORE
    continue
  fi

  #SITE do problema:
  SITE=${PROBS[PROBID]}

  #ID no SITE
  IDSITE=${PROBS[PROBID+1]}
  login-$SITE
  CODIGOSUBMISSAO="$(enviar-$SITE "$ARQ" $IDSITE $LING)"

  #aguarda um pouco
  sleep 3

  RESP="$(pega-resultado-$SITE $CODIGOSUBMISSAO)"

  mkdir -p $CONTESTSDIR/$CONTEST/controle/$LOGIN.d

  PROBIDFILE=$CONTESTSDIR/$CONTEST/controle/$LOGIN.d/$PROBID

  PENALIDADES=0
  JAACERTOU=0
  TENTATIVAS=0
  if [[ -e $PROBIDFILE ]]; then
    source $PROBIDFILE
  fi

  TEMPO="$(cut -d: -f1 <<< "$ID")"
  ((TEMPO= (TEMPO - CONTEST_START) ))

  if [[ "$RESP" == "Accepted"  && "$JAACERTOU" == "0" ]] ; then
    (( PENALIDADES= PENALIDADES + TEMPO/60 ))
    JAACERTOU=$TEMPO
    ((TENTATIVAS++))
    {
      echo "PENALIDADES=$PENALIDADES"
      echo "JAACERTOU=$JAACERTOU"
      echo "TENTATIVAS=$TENTATIVAS"
    } > $PROBIDFILE
  elif [[ "$JAACERTOU" == "0" ]]; then
    ((TENTATIVAS++))
    ((PENALIDADES+=20))
    {
      echo "PENALIDADES=$PENALIDADES"
      echo "JAACERTOU=0"
      echo "TENTATIVAS=$TENTATIVAS"
    } > $PROBIDFILE
  fi

  echo "$TEMPO:$LOGIN:$PROBID:$LING:$RESP" >> $CONTESTSDIR/$CONTEST/controle/history


  #gerar arquivo para montar o score
  ACUMPENALIDADES=0
  ACUMACERTOS=0
  TAMARRAY=${#PROBS[@]}
  #Ordem tabela de score
  #nome | A | B | C | D | ... | Acertos | Penalidade |
  {
    NOME="$(grep "^$LOGIN:" $CONTESTSDIR/$CONTEST/passwd|cut -d: -f3)"
    printf "<td>$NOME</td>"
    for((prob=0;prob<TAMARRAY;prob+=5)); do
      PENALIDADES=0
      JAACERTOU=0
      TENTATIVAS=0
      source $CONTESTSDIR/$CONTEST/controle/$LOGIN.d/$prob 2>/dev/null
      if (( TENTATIVAS == 0 )) ; then
        printf "<td></td>"
      elif (( JAACERTOU > 0 )); then
        ((ACUMACERTOS++))
        ((ACUMPENALIDADES+=PENALIDADES))
        ((JAACERTOU = JAACERTOU/60))
        printf "<td> Yes <small>$TENTATIVAS/$JAACERTOU</small></td>"
      else
        #((ACUMPENALIDADES+=PENALIDADES))
        printf "<td> <small>$TENTATIVAS/-</small></td>"
      fi
    done
    printf "<td>$ACUMACERTOS ($ACUMPENALIDADES)</td></tr>:$ACUMACERTOS:$ACUMPENALIDADES\n"
  } > $CONTESTSDIR/$CONTEST/controle/$LOGIN.score
  CLASSIFICACAO=1
  cat $CONTESTSDIR/$CONTEST/controle/*.score|sort -n -t ':' -k3|
    sort -s -n -r -t ':' -k2|
    cut -d: -f1|
    while read LINE; do
      echo "<tr><td>$CLASSIFICACAO</td>$LINE";
      ((CLASSIFICACAO++))
    done  > $CONTESTSDIR/$CONTEST/controle/SCORE


  #gravar no arquivo de solucoes
  #TODO colocar um lock no arquivo do usuario
  USRFILE="$CONTESTSDIR/$CONTEST/data/$LOGIN"
  sed -i -e "s/^$ID:.*/$ID:$PROBID:$RESP/" "$USRFILE"
  chmod 777 "$USRFILE"
  cp "$ARQ" $SUBMISSIONDIR-julgados/

  #copiar $ARQ para o diretorio com historico de submissoes
  cp "$ARQ" "$CONTESTSDIR/$CONTEST/submissions/$ID-$LOGIN-${PROBS[PROBID+3]}.$LING"

  rm -f "$ARQ"
done
