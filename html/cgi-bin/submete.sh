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

POST="$(cat |tr -d '\r' )"
AGORA="$(date +%s)"
CAMINHO="$PATH_INFO"
CONTEST="$(cut -d'/' -f2 <<< "$CAMINHO")"
CONTEST="${CONTEST// }"
AGORA="$(date +%s)"
source $CONTESTSDIR/$CONTEST/conf

function submete-sair-com-erro()
{
  MSG="$1"
  printf "Content-type: text/html\n\n"
  cat << EOF
  <script type="text/javascript">
    window.alert("$MSG");
    top.location.href = "$BASEURL/cgi-bin/contest.sh/$CONTEST"
  </script>
EOF
exit 0
}

if (( AGORA > CONTEST_END )) && is-admin |grep -q Nao ; then
  cabecalho-html
  echo "<h1>O contest \"$CONTEST_NAME\" não está mais em execução</h1>"
  echo "<p> A sua submissão não foi armazenada</p>"
  cat ../footer.html
  exit 0
fi

if [[ "x$POST" == "x" ]]; then
  tela-erro
  exit 0

elif verifica-login $CONTEST |grep -q Nao; then
  tela-login $CONTEST
fi

LOGIN=$(pega-login)
PROBLEMA="$(grep -A2 'name="problem"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
FILENAME="$(grep 'filename' <<< "$POST" |sed -e 's/.*filename="\(.*\)".*/\1/g'|head -n1|sed -e 's/\([[\/?*]\|\]\)/\\&/g')"
FILETYPE="$(awk -F'.' '{print $NF}' <<< "$FILENAME"|tr '[a-z]' '[A-Z]')"
FILETYPE="${FILETYPE// }"
ID="$(echo "$AGORA $LOGIN $POST $RANDOM"|md5sum |awk '{print $1}')"

fd='Content-Type: '
boundary="$(head -n1 <<< "$POST")"
DESTINO="$CONTEST:$AGORA:$ID:$LOGIN:submit:$PROBLEMA:"
TMP="$(mktemp)"

sed -e "1,/$fd/d;/^$/d;/$boundary/,\$d" <<< "$POST" > "$TMP"
if ! file "$TMP" | grep -q -i "text"; then
  rm -f "$TMP"
  submete-sair-com-erro "Arquivo Corrompido, ou vazio, ou binário. Envie o código fonte"
fi

#testar criar aquivo
if ! touch "/tmp/$DESTINO$FILETYPE"; then
  cat "$TMP" > "$SUBMISSIONDIR/${DESTINO}DESCONHECIDO"
else
  cat "$TMP" > "$SUBMISSIONDIR/$DESTINO$FILETYPE"
  rm -f "/tmp/$DESTINO$FILETYPE"
fi
rm -f "$TMP"

echo "$AGORA:$ID:$PROBLEMA:Not Answered Yet" >> "$CONTESTSDIR/$CONTEST/data/$LOGIN"


printf "Content-type: text/html\n\n"
cat << EOF
<script type="text/javascript">
  top.location.href = "$BASEURL/cgi-bin/contest.sh/$CONTEST"
</script>
EOF
exit 0
