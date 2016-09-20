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

if [[ "x$CONTEST" == "x" ]] || [[ ! -d "$CONTESTSDIR/$CONTEST" ]] || 
  [[ "$CONTEST" == "admin" ]]; then
  tela-erro
  exit 0
fi

source $CONTESTSDIR/$CONTEST/conf
if verifica-login $CONTEST| grep -q Nao; then
  tela-login $CONTEST
elif is-admin | grep -q Nao; then
  tela-erro
  exit 0
else
  incontest-cabecalho-html $CONTEST
fi
printf "<h1>Todas Submissões em \"<em>$CONTEST_NAME</em>\"</h1>\n"

cd $CONTESTSDIR/$CONTEST/data/
for i in *; do
  NOME="$(grep "^$i:" ../passwd |cut -d: -f3)"
  cat << EOF
  <h2>$NOME ($i)</h2>
  <table border=1>
  <tr><th>Problema</th><th>Resposta</th><th>Horário da
  Submissão</th><th>fonte</th></tr>
EOF
  LINHA=1
  while read LINE; do
    CODIGO=$(cut -d: -f1,2 <<< $LINE)
    TEMPO=$(cut -d: -f1 <<< $LINE)
    HORA="$(date --date=@$TEMPO)"
    RESP=$(cut -d: -f4 <<< $LINE)
    EXERCICIO=$(cut -d: -f3 <<< $LINE)
    BGCOLOR=
    if (( LINHA%2 == 0 )); then
      BGCOLOR="bgcolor='#00EEEE'"
    fi
    USUARIO=$i
    ((TEMPO= (TEMPO - CONTEST_START) ))
    TYPE=$(grep "^$TEMPO:$USUARIO:" $CONTESTSDIR/$CONTEST/controle/history|cut -d: -f4)
    TYPE="$(echo $TYPE | tr '[A-Z]' '[a-z]')"

    cat <<EOF
    <tr $BGCOLOR><td>${PROBS[$((EXERCICIO+3))]}</td><td>$RESP</td><td>$HORA</td>
    <td><a target=_blank href='$BASEURL/cgi-bin/getcode.sh/$CONTEST/$CODIGO-$i-${PROBS[$((EXERCICIO+3))]}.$TYPE'>código</a>
    </td></tr>
EOF
  ((LINHA++))
  done < $i
  echo "</table><br/>"
done

incontest-footer
