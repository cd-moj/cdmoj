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

POST="$(cat )"

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

if [[ "x$CONTEST" == "x" ]] || [[ ! -d "$CONTESTSDIR/$CONTEST" ]]; then
  tela-erro
  exit 0
fi

#o contest é valido, tem que verificar o login
if verifica-login $CONTEST| grep -q Nao; then
  tela-login $CONTEST
fi
source $CONTESTSDIR/$CONTEST/conf
LOGIN=$(pega-login)

if [[ "x$POST" != "x" ]]; then
  SENHAVELHA="$(grep -A2 'name="senhaantiga"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
  SENHA="$(grep -A2 'name="senha"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
  #escapar coisas perigosas
  SENHAVELHA="$(echo $SENHAVELHA | sed -e 's/\([[\/.*]\|\]\)/\\&/g')"
  SENHA="$(echo $SENHA | sed -e 's/\([[\/.*]\|\]\)/\\&/g')"
  if ! grep -q "^$LOGIN:$SENHAVELHA:" $CONTESTSDIR/$CONTEST/passwd; then
    tela-login $CONTEST
  fi
  #avisa troca de senha
  touch  $SUBMISSIONDIR/$CONTEST:$AGORA:$RANDOM:$LOGIN:passwd:$SENHAVELHA:$SENHA

  printf "Set-Cookie: login=$LOGIN; Path=/;  expires=$(date --date=@$AGORA)\n"
  printf "Set-Cookie: hash=0000; Path=/; expires=$(date --date=@$AGORA)\n"
  printf "Content-type: text/html\n\n"
  cat << EOF
  <script type="text/javascript">
    window.alert("Senha Trocada com Sucesso");
    top.location.href = "$BASEURL/cgi-bin/contest.sh/$CONTEST"
  </script>

EOF
  exit 0
fi

#estamos logados
cabecalho-html
printf "<h1>Trocar SENHA de $(pega-nome $CONTEST) em \"<em>$CONTEST_NAME</em>\"</h1>\n"

if [[ "x$PASSWD" == "x1" ]]; then
#formulário para trocar a senha
  cat << EOF
<form enctype="multipart/form-data" action="$BASEURL/cgi-bin/passwd.sh/$CONTEST" method="post">
  Senha Antiga: <input name="senhaantiga" type="password"><br/>
  Nova Senha: <input name="senha" type="password"><br/>
  <br/>
  <input type="submit" value="Trocar">
  <br/>
</form>
EOF
else
  printf "<h2>Troca de senha desabilitada</h2>"
  printf "<p>O administrador deste contest desabilitou a troca de senhas</p>"
fi

cat ../footer.html
exit 0
