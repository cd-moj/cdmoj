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
#LINGUAGEM=2(Cpp), 3(java)

URILANGS=(C Cpp Java)

function login-uri()
{
  #source config
  curl -s  -c $HOME/.cache/cookie -F "data[User][email]=$USUARIO" \
         -A "Mozilla/4.0" \
         -F "data[User][password]=$SENHA" \
        http://www.urionlinejudge.com.br/judge/pt/users/login \
          >/dev/null
}

#retorna o ID da submissao
function enviar-uri()
{
  ARQFONTE=$1
  PROBID=$2
  LINGUAGEM=$3

  if [[ "$LINGUAGEM" == "Java" ]];then
    LINGUAGEM=3;
  else
    LINGUAGEM=2;
  fi

  #enviar
  curl -A "Mozilla/4.0" -b ~/.cache/cookie \
    -F "data[Run][source]=$(<$ARQFONTE)" \
    -F "data[Run][lang_id]=$LINGUAGEM" \
    -F "data[Run][problem_id]=$PROBID" \
    www.urionlinejudge.com.br/judge/runs/add

  #pegar Codigo da submissao
  curl -A "Mozilla/4.0" -b ~/.cache/cookie -s\
    http://www.urionlinejudge.com.br/judge/runs|
    grep "/judge/runs/code/"|head -n1|cut -d'"' -f2|
      awk -F'/' '{print $NF}'
}

#Retorna string do resultado
function pega-resultado-uri()
{
  JOBID=$1
  RESP="$(curl -s -A "Mozilla/4.0" -b ~/.cache/cookie www.urionlinejudge.com.br/judge/runs/code/$JOBID | elinks -dump|grep -A1 Resposta:|tail -n1|sed -e 's/  //g'|sed -e 's/^ //')"
  while [[ "$RESP" =~ "queue" ]]; do
    sleep 5
    RESP="$(curl -s -A "Mozilla/4.0" -b ~/.cache/cookie www.urionlinejudge.com.br/judge/runs/code/$JOBID | elinks -dump|grep -A1 Resposta:|tail -n1|sed -e 's/  //g'|sed -e 's/^ //')"
  done
  echo "$RESP"
}
