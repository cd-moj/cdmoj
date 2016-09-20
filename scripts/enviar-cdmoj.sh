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

function login-cdmoj()
{
  true
}

#retorna o ID da submissao
function enviar-cdmoj()
{
  ARQFONTE=$1
  PROBID=$2
  LINGUAGEM=$3
  CODIGO=$(cut -d: -f3 <<< "$ARQFONTE")
  ssh mojjudge@mojjudge.naquadah.com.br "bash autojudge-sh.sh $LINGUAGEM $PROBID $CODIGO" < "$ARQFONTE"
}

#Retorna string do resultado
function pega-resultado-cdmoj()
{
  JOBID="$1"
  echo "$JOBID"
}
