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

#ARQFONTE=arquivo-com-a-fonte
#PROBID=id-do-problema
MOJPORTS=()
MOJPORTS+=(localhost:42000)
MOJPORTS+=(localhost:42050)
MOJPORTS+=(localhost:42100)
MOJPORTS+=(localhost:43000)
MOJPORTS+=(localhost:43050)
MOJPORTS+=(localhost:43100)
MOJPORTS+=(localhost:43150)
MOJPORTS+=(localhost:41050)
MOJPORTS+=(localhost:41000)
#MOJPORTS+=(localhost:40000)
#MOJPORTS+=(jaguapitanga.naquadah.com.br:40000)

function login-cdmoj()
{
  true
  #if [[ ! -e /tmp/mojports ]] || find /tmp/mojports -mmin +2|grep mojports &>/dev/null; then
  #  rm -f /tmp/mojports
  #  for PORT in ${MOJPORTS[0]} ${MOJPORTS[@]}; do
  #    if echo '{ "cmd": "null" }'| timeout 3 nc -w 1 ${PORT/:??*} ${PORT/??*:/}|grep "Invalid Command" &>/dev/null; then
  #      echo $PORT >> /tmp/mojports
  #    fi
  #  done
  #fi
}

#retorna o ID da submissao
function enviar-cdmoj()
{
  PORT=
  [[ -z "${MOJCONTESTSERVERS}" ]] && MOJCONTESTSERVERS="${MOJPORTS[@]}"
  for p in ${MOJCONTESTSERVERS}; do
    PORT="$p"
    echo '{ "cmd": "islocked" }'|timeout 3 nc -w 1 ${p/:??*} ${p/??*:}|grep -q "false" && break
    unset PORT
  done
  [[ -z "$PORT" ]] && echo "== Sem servidor livre do MOJ ($MOJCONTESTSERVERS)" >&2 && sleep 5 && echo "No_Servers" && return
  local ARQFONTE=$1
  local PROBID=$2
  local LINGUAGEM=$(echo $3|tr '[A-Z]' '[a-z]')
  #CODIGO=$(cut -d: -f3 <<< "$ARQFONTE")
  local TEMP=$(mktemp)
  #ssh mojjudge@mojjudge.naquadah.com.br "bash autojudge-sh.sh $LINGUAGEM $PROBID $CODIGO" < "$ARQFONTE"
  cat << EOF > $TEMP
{ "cmd": "run", "problemid": "$PROBID", "language": "$LINGUAGEM", "filename": "Main.$LINGUAGEM", "fileb64": "$(base64 -w 0 $ARQFONTE)", "metadata": "$ARQFONTE" }
EOF
  #cat $TEMP >&2
  cat $TEMP |timeout 60 nc ${PORT/:??*} ${PORT/??*:/} | jshon -e jobid |tr -d '"' > $TEMP.a
  CODIGO=$(<$TEMP.a)
  echo "$PORT-$CODIGO" |tr ':' ','
  echo "$PORT-$CODIGO" >&2
  echo "=== $CODIGO" >&2
  rm $TEMP.a $TEMP
  ## Gambiarra horrível
  local COMPETICAO="$(basename $ARQFONTE|cut -d: -f1)"
  local LOCALID="$(basename $ARQFONTE|cut -d: -f2,3)"
  mkdir -p $HOME/contests/$COMPETICAO/mojlog/
  echo "${PORT/:??*} ${PORT/??*:/} $CODIGO" > $HOME/contests/$COMPETICAO/mojlog/$LOCALID
  MOJCONTESTSERVERS=""
  unset MOJCONTESTSERVERS
}

#Retorna string do resultado
function pega-resultado-cdmoj()
{
  [[ "$1" == "No Servers" ]] && echo "" && return
  sleep 1
  local PORT=$(echo $1 |cut -d '-' -f1|tr ',' ':')
  local JOBID=$(echo $1|cut -d '-' -f2)
  local TEMP=$(mktemp)
  local COUNT=0
  local RESULT
  local SLEEPTIME
  echo "{ \"cmd\": \"getresult\", \"jobid\": \"$JOBID\" }"| timeout 30 nc ${PORT/:??*} ${PORT/??*:/} |jshon -e status|tr -d '"' > $TEMP
  echo "($PORT) { \"cmd\": \"getresult\", \"jobid\": \"$JOBID\" }" >&2
  RESULT="$(<$TEMP)"
  SLEEPTIME=0.5
  local INICIO=$EPOCHSECONDS
  while (( COUNT < 600 )) && (( EPOCHSECONDS - INICIO < 24*3600 )) && ( [[ -z "$RESULT" ]] || [[ "$RESULT" == "On queue" ]] || [[ "$RESULT" == "Running" ]] ); do
    sleep $SLEEPTIME
    [[ -z "$RESULT" ]] && ((COUNT++))
    echo "{ \"cmd\": \"getresult\", \"jobid\": \"$JOBID\" }"| timeout 30 nc ${PORT/:??*} ${PORT/??*:/} |jshon -e status|tr -d '"' > $TEMP
    RESULT="$(<$TEMP)"
    #SLEEPTIME=$(echo "$SLEEPTIME + 0.5" |bc)
    #(( $(echo "$SLEEPTIME > 10" |bc) == 1 )) && SLEEPTIME=0.5
  done
  RESULT="${RESULT/ \[?*\]/}"
  ([[ "$RESULT" == "On queue" ]] ||  [[ "$RESULT" == "Running" ]] ) && RESULT=""
  [[ "$RESULT" == "Presentation Error" ]] && RESULT=Accepted
  echo "$RESULT"
  rm $TEMP
}
