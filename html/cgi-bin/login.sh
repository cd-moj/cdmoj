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

POST="$(cat)"
AGORA="$(date +%s)"
CAMINHO="$PATH_INFO"
CONTEST="$(cut -d'/' -f2 <<<"$CAMINHO")"
CONTEST="${CONTEST// /}"

QUESTAO=$(basename $CAMINHO)
# escapar o "#" do no me da questao -> ${nome_questao//#/%23}
QUESTAO=${QUESTAO//#/%23}
if [[ "$CONTEST" == "treino" ]]; then
  if [[ "$QUESTAO" == "conquistas.usuario" ]]; then
    HREF="$BASEURL/cgi-bin/conquistas.sh"
  else
    HREF="$BASEURL/cgi-bin/questao.sh/$QUESTAO"
  fi
else
  HREF="$BASEURL/cgi-bin/contest.sh/$CONTEST"
fi

if [[ "x$POST" != "x" ]]; then
  LOGIN="$(grep -A2 'name="login"' <<<"$POST" | tail -n1 | tr -d '\n' | tr -d '\r')"
  SENHA="$(grep -A2 'name="senha"' <<<"$POST" | tail -n1 | tr -d '\n' | tr -d '\r')"
  #escapar coisa perigosa
  LOGIN="$(echo $LOGIN | sed -e 's/\([[\/*]\|\]\)/\\&/g')"
  SENHA="$(echo $SENHA | sed -e 's/\([[\/.*]\|\]\)/\\&/g')"
  if ! (grep -qF "$LOGIN:$SENHA:" $CONTESTSDIR/$CONTEST/passwd && grep -q "^$LOGIN:$SENHA:" $CONTESTSDIR/$CONTEST/passwd); then
    #invalida qualquer hash
    env &>$SUBMISSIONDIR/$CONTEST:$AGORA:$RAND:$LOGIN:tentativadelogin:dummy
    NOVAHASHI=$(echo "$(date +%s)$RANDOM$RANDOM" | md5sum | awk '{print $1}')
    printf "$NOVAHASHI" >"$CACHEDIR/$LOGIN-$CONTEST"
    cabecalho-html
    cat <<EOF
  <script type="text/javascript">
    window.alert("Senha Incorreta");
    top.location.href = "$HREF"
  </script>
EOF
    exit 0
  fi
  NOVAHASH=$(echo "$(date +%s)$RANDOM$LOGIN" | md5sum | awk '{print $1}')
  printf "$NOVAHASH" >"$CACHEDIR/$LOGIN-$CONTEST"

  #avisa do login
  env &>$SUBMISSIONDIR/$CONTEST:$AGORA:$RAND:$LOGIN:login:dummy

  #enviar cookie
  ((ESPIRA = AGORA + 36000))
  printf "Content-type: text/html\n\n"
  cat <<EOF
  <script type="text/javascript">
    document.cookie="login=$LOGIN; expires=$(date --utc --date=@$ESPIRA); Path=/"
    document.cookie="hash=$NOVAHASH; expires=$(date --utc --date=@$ESPIRA); Path=/"
    top.location.href = "$HREF"
  </script>

EOF
  exit 0

elif verifica-login $CONTEST | grep -q Nao; then
  if [[ "$CONTEST" == "treino" ]]; then
    tela-login $CONTEST/$QUESTAO
  else
    tela-login $CONTEST
  fi
fi

#printf "Location: /~moj/cgi-bin/contest.sh/$CONTEST\n\n"
printf "Content-type: text/html\n\n"
cat <<EOF
  <script type="text/javascript">
    top.location.href = "$HREF"
  </script>

EOF
exit 0
