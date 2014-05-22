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
  printf "\n$N\n"
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

  #com CDMOJDELEGATION, repassa a correcao para servidores auxiliares,
  # liberando a fila atual.
  # Isso é válido apenas para os contests com essa variável habilitada, ou
  # quando é uma variável global do ambiente que chamou este script.
  #   Tem essa característica para evitar quebrar compatibilidade com os
  #   contests em execução, pois pode acontecer dos servidores DELEGATION
  #   não possuírem todos os problemas habilitados por padrão no CDMOJ.
  if [[ "$IDSITE" == "cdmoj" && "$CDMOJDELEGATION" == "true" ]]; then
    if [[ ! -e /tmp/cdmoj-delegation-lastserver ]]; then
      echo 0 > /tmp/cdmoj-delegation-lastserver
    fi

    LASTSERVER=$(< /tmp/cdmoj-delegation-lastserver)
    TOTALSERVERS=$(ls -d "$SUBMISSIONDIR/../cdmoj-delegation-server*"|wc -l)
    ((NEXT= (LASTSERVER+1)%TOTALSERVERS))
    mv "$ARQ" "$SUBMISSIONSDIR/../cdmoj-delegation-server$NEXT/"
    continue
  fi

  login-$SITE
  CODIGOSUBMISSAO="$(enviar-$SITE "$ARQ" $IDSITE $LING)"

  #aguarda um pouco
  sleep 3

  RESP="$(pega-resultado-$SITE "$CODIGOSUBMISSAO")"

  if [[ "${RESP// }" == "" || "${RESP// }" == "??" ]]; then
    continue
  fi

  #ordem de ARQ: $CONTEST:$AGORA:$RAND:$LOGIN:comando:$PROBLEMA:$FILETYPE
  CMDRESP=corrigido
  if [[ "$COMANDO" == "rejulgar" ]]; then
    CMDRESP=rejulgado
  fi
  touch "$SUBMISSIONDIR/$CONTEST:$ID:$LOGIN:$CMDRESP:$PROBID:$LING:$RESP"

  rm -f "$ARQ"

done
