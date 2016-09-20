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
  cabecalho-html
else
  incontest-cabecalho-html $CONTEST
fi
printf "<h1>SCORE de \"<em>$CONTEST_NAME</em>\"</h1>\n"

printf "<ul><li>Início: $(date --date=@$CONTEST_START)</li>"
printf "<li>Término:  $(date --date=@$CONTEST_END)</li>"

if (( AGORA < CONTEST_START )); then
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
  if verifica-login $CONTEST| grep -q Nao; then
    cat ../footer.html
  else
    incontest-footer
  fi
  exit 0
fi

if (( AGORA > CONTEST_END )); then
  printf "<li><i>Contest Encerrado</i></li>"
else
  ((FALTA= (CONTEST_END-AGORA)/60 ))
  printf "<li>Faltam $FALTA minutos para o encerramento</li>"
fi
printf "</ul><br/><br/>"


#Gerar Tabela com pontuacao
TOTPROBS=${#PROBS[@]}
#((TOTPROBS=TOTPROBS/5))
SELETOR=
echo "<table border=1 width=100%>"
echo "<tr><td><b>#</b></td><td><b>Nome</b></td>"
for ((i=0;i<TOTPROBS;i+=5)); do
  printf "<td><b>${PROBS[$((i+3))]}</b></td>"
done
echo "<td><b>Total</b></td></tr>"
cat $CONTESTSDIR/$CONTEST/controle/SCORE
echo "</table>"

if verifica-login $CONTEST| grep -q Nao; then
  cat ../footer.html
else
  incontest-footer
fi
