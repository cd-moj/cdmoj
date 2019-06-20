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
if (verifica-login $CONTEST| grep -q Sim) && (is-admin |grep -q Sim); then
  incontest-cabecalho-html $CONTEST
else
  cabecalho-html
fi
printf "<h1>Estatísticas de \"<em>$CONTEST_NAME</em>\"</h1>\n"

printf "<ul><li>Início: $(date --date=@$CONTEST_START)</li>"
printf "<li>Término:  $(date --date=@$CONTEST_END)</li>"

if (( AGORA < CONTEST_END )) && (is-admin | grep -q Nao); then
  printf "<p>O Contest ainda <b>NÃO</b> encerrou.</p>\n"
  if [[ "$PARTIALSTATISTIC" == "1" ]]; then
    printf "<p> As estatísticas disponibilizadas aqui são PARCIAIS e são "
    printf "atualizadas a cada submissão</p>\n"
  else
    printf "<p> Este contest NÃO permite estatísticas parciais, aguarde!</p>\n"
    cat ../footer.html
    exit 0
  fi
fi

if (( AGORA > CONTEST_END )) && ( is-admin |grep -q Nao ) && [[ "$STATISTICS" == "0" ]]; then
  printf "<p> Este contest NÃO permite estatísticas!</p>\n"
  cat ../footer.html
  exit 0
fi

declare -A APOIO
#mostrar exercicios
printf "<br/><br/><h2>Problems</h2>\n"
TOTPROBS=${#PROBS[@]}
#((TOTPROBS=TOTPROBS/5))
LINHA=1
printf "<table border=1><tr><th>ID</th><th>Full Name</th><th>Local Description</th><th>OJ Link</th></tr>"
for ((i=0;i<TOTPROBS;i+=5)); do
  APOIO[acerto,$i]=0
  APOIO[errado,$i]=0
  BGCOLOR=
  if (( LINHA%2 == 0 )); then
    BGCOLOR="bgcolor='#00EEEE'"
  fi
  printf "<tr $BGCOLOR><td>${PROBS[$((i+3))]}</td><td>${PROBS[$((i+2))]}</td>"
  LINK="${PROBS[$((i+4))]}"

  if [[ "$LINK" =~ "http://" ]]; then
    printf "<td><a href=\"$LINK\" target=\"_blank\">desc</a></td>"
  elif [[ "$LINK" != "none" && "$LINK" != "site" && "$LINK" != "sitepdf" ]]; then
    printf "<td><a href=\"$BASEURL/contests/$CONTEST_ID/$LINK\" target=\"_blank\">desc</a></td>"
  else
    printf "<td> - - </td>"
  fi
  LINK="$(link-prob-${PROBS[i]} ${PROBS[$((i+1))]})"
  printf "<td> <a href='$LINK'>${PROBS[$((i+1))]}</td></tr>\n"
  ((LINHA++))
done
printf "</table>"

declare -A MAPAUSUARIO
while read l; do
	MAPAUSUARIO[${l%%:*}]="$(cut -d: -f3 <<< "$l")"
done < $CONTESTSDIR/$CONTEST/passwd

#6979:ingridcarvalhoisc30:0:C:Presentation Error:
RUNLIST=""
while read l; do
  readarray -t -d: TMP <<< "$l"
  ((APOIO[runs,${TMP[1]}]++))
  ((APOIO[run,${TMP[1]},${TMP[2]},tentativas]++))
  if [[ "${TMP[4]}" =~ "Accepted" ]]; then
    (( APOIO[acerto,${TMP[2]}]++ ))
    APOIO[run,${TMP[1]},${TMP[2]},acerto]=${TMP[0]}
  else
    (( APOIO[errado,${TMP[2]}]++ ))
  fi

  #RUN LIST
  ((TEMPOMIN= TMP[0]/60 ))
  ((LOCALTIME= CONTEST_START + TMP[0]))
  LOCALTIME="$(date --date=@$LOCALTIME)"
  BGCOLOR=
  if (( CONT%2 == 0 )); then
    BGCOLOR="bgcolor='#00EEEE'"
  fi
  RUNLIST+="<tr $BGCOLOR><td>$CONT</td><td>${MAPAUSUARIO[${TMP[1]}]}</td><td>$TMPOMIN</td>"
  RUNLIST+="<td>${PROBS[$((${TMP[2]}+3))]}</td><td>${TMP[3]}</td>"
  RUNLIST+="<td>$LOCALTIME</td><td>${TMP[4]}</td></tr>"

  ((CONT++))
done < $CONTESTSDIR/$CONTEST/controle/history


#Gerar Tabela com pontuacao
LINHA=0
printf "<br/><br/><h2>Runs by Problems</h2>\n"
printf "<table border=1>"
printf "<tr><th>#</th><th>Total</th><th>Accepted</th></tr>"
for ((i=0;i<TOTPROBS;i+=5)); do
  ID=$i
  ((TOTALRUNS=APOIO[acerto,$ID]+APOIO[errado,$ID]))
  TOTALAC="${APOIO[acerto,$ID]}"
  ACPER=""
  if ((TOTALRUNS > 0)); then
    ACPER="($((TOTALAC*100/TOTALRUNS))%%)"
  fi
  BGCOLOR=
  if (( LINHA%2 == 0 )); then
    BGCOLOR="bgcolor='#00EEEE'"
  fi
  printf "<tr $BGCOLOR><td>${PROBS[$((i+3))]}</td><td>$TOTALRUNS</td><td>$TOTALAC ${ACPER}</td></tr>"
  ((LINHA++))
done
printf "</table>"

printf "<br/><br/><h2>Runs by User and Problem</h2>\n"
printf "<table border=1>"
printf "<tr><th>Users x Problems</th>"
for ((i=0;i<TOTPROBS;i+=5)); do
  printf "<th>${PROBS[$((i+3))]}</th>"
done
printf "<th>Total</th><th>Accepted</th></tr>"

#for LOGIN in $CONTESTSDIR/$CONTEST/controle/*.d; do
for LOGINN in ${!MAPAUSUARIO[@]}; do
  #LOGINN="$(basename $LOGIN .d)"
  if [[ "$LOGINN" =~ ".admin" ]] ||  [[ "$LOGINN" =~ ".mon" ]]; then
    continue
  fi
  NOME="${MAPAUSUARIO[$LOGINN]}"
  TOTALRUNS="${APOIO[runs,$LOGINN]}"
  [[ -z "$TOTALRUNS" ]] && TOTALRUNS=0
  AC=0
  printf "<td>$NOME</td>"
  for ((i=0;i<TOTPROBS;i+=5)); do
    JAACERTOU="${APOIO[run,$LOGINN,$i,acerto]}"
    TENTATIVAS="${APOIO[run,$LOGINN,$i,tentativas]}"
    COR=lightgreen
    if [[ -z "$JAACERTOU" ]];then
      COR=white
    else
      ((AC++))
    fi

    if [[ -n "$TENTATIVAS" ]] && ((TOTALRUNS!=0)); then
      TENTATIVAS+=" ( $((TENTATIVAS*100/TOTALRUNS))%%)"
    elif [[ -z "$TENTATIVAS" ]]; then
      TENTATIVAS=0
    fi
    printf "<td bgcolor=$COR>$TENTATIVAS</td>"
  done

  ACO=$AC
  if ((AC!=0)); then
    AC="$AC ( $((AC*100/TOTALRUNS))%)"
  fi
  echo "<td>$TOTALRUNS</td><td>$AC</td></tr>:$ACO"
done|sort -n -r -t':' -k2|cut -d: -f1
printf "</table>"

CONT=1
printf "<br/><br/><h2>Runs</h2>\n"
printf "<table border=1 width=100%>"
printf "<tr><th>#</th><th>User</th><th>Time</th><th>Problem</th>"
printf "<th>Language</th><th>Local Time</th><th>Answer</th></tr>\n"
printf "$RUNLIST"
printf "</table>"


if (verifica-login $CONTEST| grep -q Sim) && (is-admin |grep -q Sim); then
  incontest-footer
else
  cat ../footer.html
fi
