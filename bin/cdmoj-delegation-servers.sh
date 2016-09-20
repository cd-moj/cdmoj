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

if (( $# != 1 )); then
  printf "Uso: $0 <Number of Delegation Servers>\n"
  printf "   - Se 0, então desabilita os servidores de delegação e copia as\n"
  printf "     submissões pendentes para SUBMISSIONDIR-enviaroj/\n"
  exit 1
fi

TOTALSERVERS=$1

DIRS=$(ls -d $SUBMISSIONDIR/../cdmoj2-delegation-server*|wc -l)

if (( DIRS < TOTALSERVERS )); then
  for((i=0;i< TOTALSERVERS;i++)); do
    mkdir -p $SUBMISSIONDIR/../cdmoj2-delegation-server$i
  done

elif (( DIRS > TOTALSERVERS )); then
  for((i=TOTALSERVERS; i< DIRS; i++)); do
    mv $SUBMISSIONDIR/../cdmoj2-delegation-server$i/* $SUBMISSIONDIR/../cdmoj2-delegation-server0/
    rm -rf SUBMISSIONDIR/../cdmoj2-delegation-server$i
  done

#para desabilitar os delegation servers as submissões pendentes devem ser
#remanejadas
elif (( TOTALSERVERS == 0 )); then
  for((i=0; i< DIRS; i++)); do
    mv $SUBMISSIONDIR/../cdmoj2-delegation-server$i/* $SUBMISSIONDIR-enviaroj/
    rm -rf SUBMISSIONDIR/../cdmoj2-delegation-server$i
  done

fi
