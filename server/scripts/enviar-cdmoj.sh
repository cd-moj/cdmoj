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
MOJPORTS+=(localhost:40000)
MOJPORTS+=(jaguapitanga.naquadah.com.br:40000)

function login-cdmoj()
{
  true
}

#retorna o ID da submissao
function enviar-cdmoj()
{
  PORT=
  for p in ${MOJPORTS[@]}; do
    PORT="$p"
    echo '{ "cmd": "islocked" }'|timeout 3 nc -w 1 ${p/:??*} ${p/??*:}|grep -q "false" && break
    unset PORT
  done
  [[ -z "$PORT" ]] && echo "== Sem servidor livre do MOJ" >&2 && echo "No_Servers" && sleep 5 && return
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
  cat $TEMP |timeout 30 nc ${PORT/:??*} ${PORT/??*:/} | jshon -e jobid |tr -d '"' > $TEMP.a
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
}

#Retorna string do resultado
function pega-resultado-cdmoj()
{
  [[ "$1" == "No Servers" ]] && echo "" && return
  local PORT=$(echo $1 |cut -d '-' -f1|tr ',' ':')
  local JOBID=$(echo $1|cut -d '-' -f2)
  local TEMP=$(mktemp)
  local COUNT=0
  echo "{ \"cmd\": \"getresult\", \"jobid\": \"$JOBID\" }"| timeout 30 nc ${PORT/:??*} ${PORT/??*:/} |jshon -e status|tr -d '"' > $TEMP
  echo "($PORT) { \"cmd\": \"getresult\", \"jobid\": \"$JOBID\" }" >&2
  RESULT="$(<$TEMP)"
  SLEEPTIME=0.5
  local INICIO=$EPOCHSECONDS
  while (( EPOCHSECONDS - INICIO < 7200 )) && ( [[ "$RESULT" == "On queue" ]] || [[ "$RESULT" == "Running" ]] ); do
    sleep $SLEEPTIME
    echo "{ \"cmd\": \"getresult\", \"jobid\": \"$JOBID\" }"| timeout 30 nc ${PORT/:??*} ${PORT/??*:/} |jshon -e status|tr -d '"' > $TEMP
    RESULT="$(<$TEMP)"
    ((COUNT++))
  done
  ([[ "$RESULT" == "On queue" ]] ||  [[ "$RESULT" == "Running" ]] || [[ "$RESULT" =~ "Wrong Problem ID" ]] ) && RESULT=""
  [[ "$RESULT" == "Presentation Error" ]] && RESULT=Accepted
  echo "$RESULT"
  rm $TEMP
}
