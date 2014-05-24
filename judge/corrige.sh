#!/bin/bash

source #CONFDIR#/judge.conf
source #CONFDIR#/common.conf
source #SCRIPTSDIR#/enviar-spoj.sh
source #SCRIPTSDIR#/enviar-uri.sh
source #SCRIPTSDIR#/enviar-cdmoj.sh

PENDING=
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

  login-$SITE
  CODIGOSUBMISSAO="$(enviar-$SITE "$ARQ" $IDSITE $LING)"
  PENDING="$PENDING $SITE:$CODIGOSUBMISSAO:$ARQ"

done

#dar um tempo para o OJ começar a corrigir
sleep 3
echo "-- Pegando Submissões pendentes"
for SUBMISSIONS in $PENDING; do

  SITE="$(cut -d: -f1 <<< "$SUBMISSIONS")"
  CODIGOSUBMISSAO="$(cut -d: -f2 <<< "$SUBMISSIONS")"
  ARQ="$(cut -d: -f3- <<< "$SUBMISSIONS")"
  N="$(basename "$ARQ")"
  printf "  $N\n"
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

  RESP="$(pega-resultado-$SITE "$CODIGOSUBMISSAO")"

  #Se RESP voltar vazio ou ??, significa que deve ser reenviado
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
