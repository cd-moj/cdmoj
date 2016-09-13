#This file is part of CD-MOJ.
#
#CD-MOJ is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#Foobar is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with Foobar.  If not, see <http://www.gnu.org/licenses/>.

#ARQFONTE=arquivo-com-a-fonte
#PROBID=id-do-problema

function login-cdmoj2()
{
  true
}

#retorna o ID da submissao
function enviar-cdmoj2()
{
  local ARQFONTE=$1
  local PROBID=$2
  local LINGUAGEM=$3
  local ARQ="$(basename "$ARQFONTE")"

  if [[ ! -e /tmp/cdmoj2-delegation-lastserver-$USER ]]; then
    echo 0 > /tmp/cdmoj2-delegation-lastserver-$USER
  fi

  LASTSERVER=$(< /tmp/cdmoj2-delegation-lastserver-$USER)
  TOTALSERVERS=$(ls -d $SUBMISSIONDIR/../cdmoj2-delegation-server*|wc -l)
  ((NEXT= (LASTSERVER+1)%TOTALSERVERS))
  echo "$NEXT" > /tmp/cdmoj2-delegation-lastserver-$USER
  ID="$NEXT.$(awk -F: '{print $2"."$3}' <<< "$ARQ")"

  cp "$ARQFONTE" "$SUBMISSIONDIR/../cdmoj2-delegation-server$NEXT/submit:$PROBID:$ID:$LINGUAGEM"
  echo "$ID"
}

#Retorna string do resultado
function pega-resultado-cdmoj2()
{
  JOBID="$1"
  SERVER="$(cut -d'.' -f1 <<< "$JOBID")"
  JOBFILE="$SUBMISSIONDIR/../cdmoj2-delegation-server$SERVER/$JOBID"
  while [[ ! -e "$JOBFILE" ]]; do
    sleep 3
  done
  RESP="$(< "$JOBFILE")"
  rm "$JOBFILE"
  echo "$RESP"
}
