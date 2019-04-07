#!/bin/bash
#This file is part of CD-MOJ.
#
#CD-MOJ is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#CD-MOJ is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with CD-MOJ.  If not, see <http://www.gnu.org/licenses/>.

source #CONFDIR#/judge.conf
source #CONFDIR#/common.conf
source #SCRIPTSDIR#/enviar-spoj.sh
source #SCRIPTSDIR#/enviar-uri.sh
source #SCRIPTSDIR#/enviar-cdmoj.sh
source #SCRIPTSDIR#/enviar-cdmoj2.sh

PENDING=
LOGGEDIN=
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

  if [[ "x$LING" == "x" ]]; then
    LING="UNKNOWN"
  fi

  #carregar contest
  source $CONTESTSDIR/$CONTEST/conf

  #SITE do problema:
  SITE=${PROBS[PROBID]}

  #ID no SITE
  IDSITE=${PROBS[PROBID+1]}

  if ! grep -q "\<$SITE\>" <<< "$LOGGEDIN" ; then
    login-$SITE
    LOGGEDIN="$LOGGEDIN $SITE"
  fi

  if [[ "$LANGUAGES" == "" ]] || grep -q "$LING" <<< "$LANGUAGES"; then
    CODIGOSUBMISSAO="$(enviar-$SITE "$ARQ" $IDSITE $LING|tr ' ' '_')"
    unset LANGUAGES
  else
    CODIGOSUBMISSAO="Wrong_Language_Choice"
  fi

  PENDING="$PENDING $SITE:$CODIGOSUBMISSAO:$ARQ"

done

#dar um tempo para o OJ começar a corrigir
sleep 3
echo "-- Pegando Submissões pendentes"
for SUBMISSIONS in $PENDING; do

  SITE="$(cut -d: -f1 <<< "$SUBMISSIONS")"
  CODIGOSUBMISSAO="$(cut -d: -f2 <<< "$SUBMISSIONS"|tr '_' ' ')"
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

  if [[ "$CODIGOSUBMISSAO" != "Wrong Language Choice" ]]; then
    RESP="$(pega-resultado-$SITE "$CODIGOSUBMISSAO")"
  else
    RESP="Wrong Language Choice"
  fi

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
