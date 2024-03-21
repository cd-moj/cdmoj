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
HREF="$BASEURL/cgi-bin/contest.sh/$CONTEST"

source $CONTESTSDIR/$CONTEST/conf

function submete-sair-com-erro()
{
  MSG="$1"
  printf "Content-type: text/html\n\n"
  cat << EOF
  <script type="text/javascript">
    window.alert("$MSG");
    top.location.href = "$HREF"
  </script>
EOF
exit 0
}

if ((DISABLESUBMIT==1)) && is-admin |grep -q Nao ; then
  cabecalho-html
  echo "<h1>O contest \"$CONTEST_NAME\" está com as submissões suspensas temporariamente</h1>"
  echo "<p> A sua submissão não foi armazenada</p>"
  cat ../footer.html
  exit 0
fi
if (( AGORA > CONTEST_END )) && DISABLESUBMIT!=1 && is-admin |grep -q Nao ; then
  cabecalho-html
  echo "<h1>O contest \"$CONTEST_NAME\" não está mais em execução</h1>"
  echo "<p> A sua submissão não foi armazenada</p>"
  cat ../footer.html
  exit 0
fi

# verifica-treino
if [[ "$CONTEST" == "treino" ]]; then
  PROBLEMA="$(cut -d'/' -f3 <<< "$CAMINHO")"
  PROBLEMA="${PROBLEMA// }"
  HREF="$BASEURL/cgi-bin/questao.sh/$PROBLEMA"
fi

if [[ "x$POST" == "x" ]]; then
  tela-erro
  exit 0

elif verifica-login $CONTEST |grep -q Nao; then
  if [[ "$CONTEST" == "treino" ]]; then
    tela-login treino/$PROBLEMA
  else
    tela-login $CONTEST
  fi
fi
LOGIN=$(pega-login)

if [[ "x$PROBLEMA" == "x" ]]; then # look up "verifica-treino" session
  PROBLEMA="$(grep -A2 'name="problem"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
fi
FILENAME="$(grep 'filename' <<< "$POST" |sed -e 's/.*filename="\(.*\)".*/\1/g'|head -n1|sed -e 's/\([[\/?*]\|\]\)/\\&/g')"
FILETYPE="$(awk -F'.' '{print $NF}' <<< "$FILENAME"|tr '[a-z]' '[A-Z]')"
FILETYPE="${FILETYPE// }"
ID="$(echo "$AGORA $LOGIN $POST $RANDOM"|md5sum |awk '{print $1}')"

fd='Content-Type: '
boundary="$(head -n1 <<< "$POST")"
DESTINO="$CONTEST:$AGORA:$ID:$LOGIN:submit:$PROBLEMA:"
TMP="$(mktemp)"

sed -e "1,/$fd/d;/^$/d;/$boundary/,\$d" <<< "$POST" > "$TMP"
if ! file "$TMP" | egrep -q -i "(text|compressed)"; then
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

# if [[ "$CONTEST" == "treino" ]]; then
#   echo "$AGORA:$ID:$PROBLEMA:Not Answered Yet" >> "$CONTESTSDIR/$CONTEST/data/$PROBLEMA/$LOGIN"
# else
#   echo "$AGORA:$ID:$PROBLEMA:Not Answered Yet" >> "$CONTESTSDIR/$CONTEST/data/$LOGIN"
# fi

echo "$AGORA:$ID:$PROBLEMA:Not Answered Yet" >> "$CONTESTSDIR/$CONTEST/data/$LOGIN"

if [[ -d "$CONTESTSDIR/$CONTEST/log" ]]; then
	mkdir -p  "$CONTESTDIR/$CONTEST/log/$LOGIN"
	env > "$CONTESTDIR/$CONTEST/log/$LOGIN/$AGORA:$ID:$PROBLEMA"
fi

mkdir -p "/tmp/$CONTEST/log/$LOGIN"
env > "/tmp/$CONTEST/log/$LOGIN/$AGORA-$ID-$PROBLEMA"

printf "Content-type: text/html\n\n"
cat << EOF
<script type="text/javascript">
  top.location.href = "$HREF"
</script>
EOF
exit 0
