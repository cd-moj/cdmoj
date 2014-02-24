#!/bin/bash

source #CONFDIR#/judge.conf
source #CONFDIR#/common.conf
source #SCRIPTSDIR#/enviar-spoj.sh
source #SCRIPTSDIR#/enviar-uri.sh
source #SCRIPTSDIR#/enviar-cdmoj.sh


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

  RESP="$(pega-resultado-$SITE "$CODIGOSUBMISSAO")"

  if [[ "${RESP// }" == "" || "${RESP// }" == "??" ]]; then
    continue
  fi

  #ordem de ARQ: $CONTEST:$AGORA:$RAND:$LOGIN:comando:$PROBLEMA:$FILETYPE
  touch "$SUBMISSIONDIR/$CONTEST:$ID:$LOGIN:corrigido:$PROBID:$LING:$RESP"

  rm -f "$ARQ"

done
