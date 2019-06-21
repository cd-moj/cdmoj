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
elif (is-admin | grep -q Nao) && (is-mon |grep -q Nao); then
  tela-erro
  exit 0
else
  incontest-cabecalho-html $CONTEST
fi
printf "<h1>Todas Submissões em \"<em>$CONTEST_NAME</em>\"</h1>\n"

declare -A MAPA LINHAMAPA MAPACOMSOLUCAO

declare -A MAPAUSUARIO
while read l; do
	MAPAUSUARIO[${l%%:*}]="$(cut -d: -f3 <<< "$l")"
done < $CONTESTSDIR/$CONTEST/passwd

while read LINE; do
  #2367:brenno.silva037:0:C:Accepted:1559351367:67ec1806c49888aab55bacf2cb538550
  readarray -t -d: VET <<< "$LINE"
  #CODIGO=$(cut -d: -f1,2 <<< $LINE)
  CODIGO=${VET[5]}:${VET[6]}
  #TEMPO=$(cut -d: -f1 <<< $LINE)
  TEMPO=${VET[5]}
  HORA="$(date --date=@$TEMPO)"
  #RESP=$(cut -d: -f4 <<< $LINE)
  RESP="${VET[4]}"
  #EXERCICIO=$(cut -d: -f3 <<< $LINE)
  EXERCICIO="${VET[2]}"
  BGCOLOR=
  ((LINHAMAPA[${VET[1]}]++))
  if (( LINHAMAPA[${VET[1]}]%2 == 0 )); then
    BGCOLOR="bgcolor='#00EEEE'"
  fi
  USUARIO=${VET[1]}
  ((TEMPO= (TEMPO - CONTEST_START) ))
  TYPE=${VET[3],,}
  #TYPE="$(echo $TYPE | tr '[A-Z]' '[a-z]')"

  MAPA[${VET[1]}]+="
  <tr $BGCOLOR><td>${PROBS[$((EXERCICIO+3))]}</td>
  <td><a target=_blank href='$BASEURL/cgi-bin/getcode.sh/$CONTEST/$CODIGO-${VET[1]}-${PROBS[$((EXERCICIO+3))]}.$TYPE'>(fonte)</a> $RESP</td>
  <td>$CODIGO</td><td>$HORA</td>
  </tr>"
  MAPACOMSOLUCAO[${VET[1]}]=1
done < $CONTESTSDIR/$CONTEST/controle/history

cd $CONTESTSDIR/$CONTEST/data/
for i in *.mon; do
  NOME="${MAPAUSUARIO[$i]}"
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
    #TYPE=$(grep "^$TEMPO:$USUARIO:" $CONTESTSDIR/$CONTEST/controle/history|cut -d: -f4)
    #TYPE="$(echo $TYPE | tr '[A-Z]' '[a-z]')"
    MAPACOMSOLUCAO[$i]=1
    MAPA[$i]+="<tr $BGCOLOR><td>${PROBS[$((EXERCICIO+3))]}</td>
    <td><a target=_blank href='$BASEURL/cgi-bin/getcode.sh/$CONTEST/$CODIGO-$i-${PROBS[$((EXERCICIO+3))]}.$TYPE'>(fonte)</a> $RESP</td>
    <td>$CODIGO</td><td>$HORA</td>
    </td></tr>"
  ((LINHA++))
  done < $i
done

cd $CONTESTSDIR/$CONTEST/data/
for i in ${!MAPACOMSOLUCAO[@]}; do
  NOME="${MAPAUSUARIO[$i]}"
  cat << EOF
  <h2>$NOME ($i)</h2>
  <table border=1>
  <tr><th>Problema</th><th>Resposta</th><th>Código</th><th>Horário da
  Submissão</th></tr>
  ${MAPA[$i]}
  </table><br/>
EOF
done

incontest-footer
