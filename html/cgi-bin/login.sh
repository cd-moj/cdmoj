#!/bin/bash

source common.sh

POST="$(cat )"
AGORA="$(date +%s)"
CAMINHO="$PATH_INFO"
CONTEST="$(cut -d'/' -f2 <<< "$CAMINHO")"
CONTEST="${CONTEST// }"

if [[ "x$POST" != "x" ]]; then
  LOGIN="$(grep -A2 'name="login"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
  SENHA="$(grep -A2 'name="senha"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
  #escapar coisa perigosa
  LOGIN="$(echo $LOGIN | sed -e 's/\([[\/*]\|\]\)/\\&/g')"
  SENHA="$(echo $SENHA | sed -e 's/\([[\/.*]\|\]\)/\\&/g')"
  if ! grep -q "^$LOGIN:$SENHA:" $CONTESTSDIR/$CONTEST/passwd; then
    cabecalho-html
    cat << EOF
  <script type="text/javascript">
    window.alert("Senha Incorreta");
    top.location.href = "$BASEURL/cgi-bin/contest.sh/$CONTEST"
  </script>
EOF
    exit 0
  fi
  NOVAHASH=$(echo "$(date +%s)$RANDOM$LOGIN" |md5sum |awk '{print $1}')
  printf "$NOVAHASH" > "$CACHEDIR/$LOGIN-$CONTEST"

  #avisa do login
  touch  $SUBMISSIONDIR/$CONTEST:$AGORA:$RAND:$LOGIN:login:dummy

  #enviar cookie
  ((ESPIRA= AGORA + 36000))
  printf "Set-Cookie: login=$LOGIN; Path=/;  expires=$(date --date=@$ESPIRA)\n"
  printf "Set-Cookie: hash=$NOVAHASH; Path=/; expires=$(date --date=@$ESPIRA)\n"
  printf "Content-type: text/html\n\n"
  cat << EOF
  <script type="text/javascript">
    top.location.href = "$BASEURL/cgi-bin/contest.sh/$CONTEST"
  </script>

EOF
  exit 0

elif verifica-login $CONTEST |grep -q Nao; then
  tela-login $CONTEST
fi

#printf "Location: /~moj/cgi-bin/contest.sh/$CONTEST\n\n"
  printf "Content-type: text/html\n\n"
  cat << EOF
  <script type="text/javascript">
    top.location.href = "$BASEURL/cgi-bin/contest.sh/$CONTEST"
  </script>

EOF
exit 0
