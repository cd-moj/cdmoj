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

if [[ "x$CONTEST" == "x" ]] || [[ ! -d "$CONTESTSDIR/$CONTEST" ]]; then
  tela-erro
  exit 0
fi

if [[ "$CONTEST" == "admin" ]]; then
  bash admin.sh
  exit 0
fi


#o contest é valido, tem que verificar o login
if verifica-login $CONTEST| grep -q Nao; then
  tela-login $CONTEST
fi

source $CONTESTSDIR/$CONTEST/conf
#estamos logados
incontest-cabecalho-html $CONTEST
#printf "<h1>$(pega-nome $CONTEST) em \"<em>$CONTEST_NAME</em>\"</h1>\n"

if (( AGORA < CONTEST_START )) && is-admin|grep -q Nao; then
  ((FALTA = CONTEST_START - AGORA))
  MSG=
  if (( FALTA >= 60 )); then
    MSG="$((FALTA/60)) minutos"
  fi
  ((FALTA=FALTA%60))
  if ((FALTA > 0 )); then
    MSG="$MSG e $FALTA segundos"
  fi
  printf "<p>O Contest ainda <b>NÃO</b> está em execução</p>\n"
  printf "<center>Aguarde $MSG</center>"
  incontest-footer
  exit 0
fi

#Mostra alguma mensagem Geral do CD-MOJ, caso exista
if [[ -e "../motd" ]]; then
  cat "../motd"
fi

#Mostra alguma mensagem para o contest caso ela exista
if [[ -e "$CONTESTSDIR/$CONTEST_ID/motd" ]]; then
  cat "$CONTESTSDIR/$CONTEST_ID/motd"
fi

#mostrar exercicios
printf "<h2>Problemas</h2>\n"
TOTPROBS=${#PROBS[@]}
#((TOTPROBS=TOTPROBS/5))
SELETOR=
echo "<ul>"
for ((i=0;i<TOTPROBS;i+=5)); do
  SELETOR="$SELETOR <option value=\"$i\">${PROBS[$((i+3))]}</option>"
  printf "<li>&emsp;&emsp;&emsp;&emsp;<b>${PROBS[$((i+3))]}</b> - ${PROBS[$((i+2))]}"
  LINK="${PROBS[$((i+4))]}"
  if [[ "${PROBS[$((i+4))]}" == "site" ]]; then
    LINK="$(link-prob-${PROBS[i]} ${PROBS[$((i+1))]})"
  elif [[ "${PROBS[$((i+4))]}" == "sitepdf" ]]; then
    LINK="$(link-prob-${PROBS[i]}-pdf ${PROBS[$((i+1))]})"
  fi

  if [[ "$LINK" =~ "http://" ]]; then
    printf " - [<a href=\"$LINK\" target=\"_blank\">LINK</a>]</li>\n"
  elif [[ "$LINK" != "none" ]]; then
    LOOKDIR="/home/html/moj.naquadah.com.br/contests/$CONTEST_ID/"
    #printf " - problem description"
    printf " -"
    [[ -e "$LOOKDIR/$LINK.html" ]] && printf " [<a href=\"$BASEURL/contests/$CONTEST_ID/$LINK.html\" target=\"_blank\">HTML</a>]"
    [[ -e "$LOOKDIR/$LINK.pdf" ]] && printf " [<a href=\"$BASEURL/contests/$CONTEST_ID/$LINK.pdf\" target=\"_blank\">PDF</a>]"
    [[ -e "$LOOKDIR/$LINK" ]] && printf " [<a href=\"$BASEURL/contests/$CONTEST_ID/$LINK\" target=\"_blank\">LINK</a>]</li>\n"
    printf "</li>\n"
  else
    printf "</li>\n"
  fi
done
echo "</ul>"

echo "<br/><br/>"
printf "<h2>Minhas Submissões</h2>\n"
cat << EOF
<table border="1" width="100%"> <tr><th>Problema</th><th>Resposta</th><th>Submissão em</th><th>Tempo de Prova</th></tr>
EOF

LOGIN=$(pega-login)

while read LINE; do
  PROB="$(cut -d ':' -f3 <<< "$LINE")"
  RESP="$(cut -d ':' -f4 <<< "$LINE")"
  TIME="$(cut -d ':' -f1 <<< "$LINE")"
  TIMEE="$(date --date=@$TIME)"
  PROBSHORTNAME=${PROBS[$((PROB+3))]}
  PROBFULLNAME="${PROBS[$((PROB+2))]}"
  ((TEMPODEPROVA= (TIME - CONTEST_START)/60 ))
  echo "<tr><td>$PROBSHORTNAME - $PROBFULLNAME</td><td>$RESP</td><td>$TIMEE</td><td>$TEMPODEPROVA</td></tr>"
done < $CONTESTSDIR/$CONTEST/data/$LOGIN

echo "</table>"

echo "<br/><br/>"
printf "<h2>Enviar uma Solução</h2>\n"

if (( AGORA > CONTEST_END )) && is-admin |grep -q Nao ; then
  echo "<p> O contest não está mais em andamento</p>"
else
cat << EOF
<form enctype="multipart/form-data" action="$BASEURL/cgi-bin/submete.sh/$CONTEST" method="post">
  <input type="hidden" name="MAX_FILE_SIZE" value="30000">
  Problem: <select name=problem>$SELETOR</select>
  File: <input name="myfile" type="file">
  <br/>
  <input type="submit" value="Submit">
  <br/>
</form>
EOF
fi

incontest-footer
