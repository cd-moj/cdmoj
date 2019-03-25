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

source common.sh
AGORA=$(date +%s)


#limpar caminho, exemplo
#www.brunoribas.com.br/~ribas/moj/cgi-bin/contest.sh/contest-teste/oi
#vira 'contest-teste/oi'
CAMINHO="$PATH_INFO"
#TESTE="$0"
#CAMINHO="$(sed -e 's#.*/contest.sh/##' <<< "$CAMINHO")"

#contest é a base do caminho
CONTEST="$(cut -d'/' -f2 <<< "$CAMINHO")"
CONTEST="${CONTEST// }"
ARQUIVO="$(cut -d'/' -f3 <<< "$CAMINHO")"
ARQUIVO="${ARQUIVO// }"

if [[ "x$CONTEST" == "x" ]] || [[ ! -d "$CONTESTSDIR/$CONTEST" ]] || 
  [[ "$CONTEST" == "admin" ]]; then
  tela-erro
  exit 0
fi

source $CONTESTSDIR/$CONTEST/conf
if verifica-login $CONTEST| grep -q Nao; then
  tela-login $CONTEST
elif (is-admin | grep -q Nao) && (is-mon|grep -q Nao); then
  tela-erro
  exit 0
fi

TYPE="$(awk -F'.' '{print $NF}' <<< "$ARQUIVO")"
ARQUIVO="$(basename "$ARQUIVO" ".$TYPE")"
TYPE="$(tr '[a-z]' '[A-Z]' <<< "$TYPE")"
ARQUIVO="$ARQUIVO.$TYPE"
if [[ ! -e "$CONTESTSDIR/$CONTEST/submissions/$ARQUIVO" ]]; then
  tela-erro
  exit 0
fi
printf "Content-type: text/txt\n\n"
cat "$CONTESTSDIR/$CONTEST/submissions/$ARQUIVO"
