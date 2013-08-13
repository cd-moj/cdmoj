#!/bin/bash

source #CONFDIR#/judge.conf
source #CONFDIR#/common.conf
source #SCRIPTSDIR#/enviar-spoj.sh
source #SCRIPTSDIR#/enviar-uri.sh


#ordem de ARQ: $CONTEST:$AGORA:$RAND:$LOGIN:comando:$PROBLEMA:$FILETYPE
for ARQ in $SUBMISSIONDIR-enviaroj/*; do
  if [[ ! -e "$ARQ" ]]; then
    continue
  fi
  N="$(basename $ARQ)"
  CONTEST="$(cut -d: -f1 <<< "$N")"
  ID="$(cut -d: -f2,3 <<< "$N")"
  LOGIN="$(cut -d: -f4 <<< "$N")"
  COMANDO="$(cut -d: -f5 <<< "$N")"
  PROBID="$(cut -d: -f6 <<< "$N")"
  LING="$(cut -d: -f7 <<< "$N")"

  #carregar contest
  source $CONTESTSDIR/$CONTEST/conf

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

  if (( JAACERTOU > 0 )); then
    RESP="Ignored"
  fi

  #ordem de ARQ: $CONTEST:$AGORA:$RAND:$LOGIN:comando:$PROBLEMA:$FILETYPE
  touch "$SUBMISSIONDIR/$CONTEST:$ID:$LOGIN:corrigido:$PROBID:$LING:$RESP"

  rm -f "$ARQ"

done
