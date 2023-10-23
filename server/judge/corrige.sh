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

source $CONFDIR/judge.conf
source $CONFDIR/common.conf
source $SCRIPTSDIR/enviar-spoj.sh
source $SCRIPTSDIR/enviar-uri.sh
source $SCRIPTSDIR/enviar-cdmoj.sh

ANIMACAO='/-\|'
ANIPOS=0
function pegaresultado()
{
  local SUBMISSIONS="$1"
  local SITE="$(cut -d: -f1 <<< "$SUBMISSIONS")"
  local CODIGOSUBMISSAO="$(cut -d: -f2 <<< "$SUBMISSIONS"|tr '_' ' ')"
  local ARQ="$(cut -d: -f3- <<< "$SUBMISSIONS")"
  local N="$(basename "$ARQ")"
  echo "--  $N"
  local CONTEST="$(cut -d: -f1 <<< "$N")"
  local ID="$(cut -d: -f2,3 <<< "$N")"
  local LOGIN="$(cut -d: -f4 <<< "$N")"
  local COMANDO="$(cut -d: -f5 <<< "$N")"
  local PROBID="$(cut -d: -f6 <<< "$N")"
  local LING="$(cut -d: -f7 <<< "$N")"
  local RESP

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
    return
  fi

  #ordem de ARQ: $CONTEST:$AGORA:$RAND:$LOGIN:comando:$PROBLEMA:$FILETYPE
  CMDRESP=corrigido
  if [[ "$COMANDO" == "rejulgar" ]]; then
    CMDRESP=rejulgado
  fi
  touch "$SUBMISSIONDIR/$CONTEST:$ID:$LOGIN:$CMDRESP:$PROBID:$LING:$RESP"

  rm -f "$ARQ"

}

declare -A PENDING PENDINGPID
declare -A LOGGEDIN
COUNT=0
#ordem de ARQ: $CONTEST:$AGORA:$RAND:$LOGIN:comando:$PROBLEMA:$FILETYPE

cd $SUBMISSIONDIR-enviaroj
X=0
while true; do
	if (( $(ls |wc -l) == 0 )); then
		(( X % 6 == 0 )) && printf "."
		sleep 0.5
		((X++))
		continue
	fi
	X=0
  for ARQ in $SUBMISSIONDIR-enviaroj/*submit* $SUBMISSIONDIR-enviaroj/*rejulgar*; do
    if [[ ! -e "$ARQ" ]]; then
      continue
    fi
    [[ -n "${PENDING[$ARQ]}" ]] && continue
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

    if [[ -z "${LOGGEDIN[$SITE]}" ]] || (( EPOCHSECONDS - ${LOGGEDIN[$SITE]} > 300 )); then
      login-$SITE
      LOGGEDIN[$SITE]=$EPOCHSECONDS
    fi

    if [[ "$LANGUAGES" == "" ]] || grep -q "$LING" <<< "$LANGUAGES"; then
      CODIGOSUBMISSAO="$(enviar-$SITE "$ARQ" $IDSITE $LING|tr ' ' '_')"
      unset LANGUAGES
    else
      CODIGOSUBMISSAO="Wrong_Language_Choice"
    fi

    PENDING[$ARQ]="$SITE:$CODIGOSUBMISSAO:$ARQ"
    pegaresultado "${PENDING[$ARQ]}" &
    PENDINGPID[$ARQ,PID]=$!
    PENDINGPID[$ARQ,TIME]=$EPOCHSECONDS

  done
  #dar um tempo para o OJ começar a corrigir
  sleep 1
  #echo -e "\n-- Pegando Submissões pendentes"
  echo -en "${ANIMACAO:$ANIPOS:1} \r"
  ((ANIPOS=(ANIPOS+1)%${#ANIMACAO}))
  for ARQ in ${!PENDING[@]}; do
    #[[ ! -e "$ARQ" ]] && unset PENDING[$ARQ] && unset PENDINGPID[$ARQ,PID] && echo "  -- ja pegou" && continue
    if [[ -n ${PENDINGPID[$ARQ,PID]} ]]; then
      [[ -d "/proc/${PENDINGPID[$ARQ,PID]}" ]] && continue
      echo -e "\n-- $(basename $ARQ)"
      echo -n "  -- verificando PID(${PENDINGPID[$ARQ,PID]})"
      [[ ! -e "$ARQ" ]] && echo ".. CONCLUIU após $((EPOCHSECONDS-PENDINGPID[$ARQ,TIME])) segundos"
      [[ -e "$ARQ" ]] && echo ".. DESISTIU após $((EPOCHSECONDS-PENDINGPID[$ARQ,TIME])) segundos. Recolocando na FILA..."
      unset PENDING[$ARQ] PENDINGPID[$ARQ,PID]
      continue
    fi
  done
done

wait
