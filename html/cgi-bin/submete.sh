#!/bin/bash

source common.sh

POST="$(cat |tr -d '\r' )"
AGORA="$(date +%s)"
CAMINHO="$PATH_INFO"
CONTEST=$(cut -d'/' -f2 <<< "$CAMINHO")
AGORA="$(date +%s)"
source $CONTESTSDIR/$CONTEST/conf

if (( AGORA > CONTEST_END )); then
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
FILENAME="$(grep 'filename' <<< "$POST" |sed -e 's/.*filename="\(.*\)".*/\1/g')"
FILETYPE="$(awk -F'.' '{print $NF}' <<< "$FILENAME"|tr '[a-z]' '[A-Z]')"
ID="$(echo "$AGORA $LOGIN $POST $RANDOM"|md5sum |awk '{print $1}')"

fd='Content-Type: '
boundary="$(head -n1 <<< "$POST")"
sed -e "1,/$fd/d;/^$/d;/$boundary/,\$d" <<< "$POST" > $SUBMISSIONDIR/$CONTEST:$AGORA:$ID:$LOGIN:submit:$PROBLEMA:$FILETYPE

echo "$AGORA:$ID:$PROBLEMA:Not Answered Yet" >> $CONTESTSDIR/$CONTEST/data/$LOGIN

#printf "Location: /~moj/cgi-bin/contest.sh/$CONTEST\n\n"
  printf "Content-type: text/html\n\n"
  cat << EOF
  <script type="text/javascript">
    top.location.href = "$BASEURL/cgi-bin/contest.sh/$CONTEST"
  </script>

EOF
exit 0
