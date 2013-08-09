#!/bin/bash

source common.sh
AGORA=$(date +%s)


#limpar caminho, exemplo
#www.brunoribas.com.br/~ribas/moj/cgi-bin/contest.sh/contest-teste/oi
#vira 'contest-teste/oi'
CAMINHO="$PATH_INFO"
#TESTE="$0"
#CAMINHO="$(sed -e 's#.*/contest.sh/##' <<< "$CAMINHO")"

#contest é a base do caminho
CONTEST=$(cut -d'/' -f2 <<< "$CAMINHO")

if [[ "x$CONTEST" == "x" ]] || [[ ! -d "$CONTESTSDIR/$CONTEST" ]] || 
  [[ "$CONTEST" == "admin" ]]; then
  tela-erro
  exit 0
fi

source $CONTESTSDIR/$CONTEST/conf
cabecalho-html
printf "<h1>Estatísticas de \"<em>$CONTEST_NAME</em>\"</h1>\n"

printf "<ul><li>Início: $(date --date=@$CONTEST_START)</li>"
printf "<li>Término:  $(date --date=@$CONTEST_END)</li>"

if (( AGORA < CONTEST_END )); then
  printf "<p>O Contest ainda <b>NÃO</b> encerrou. Aguarde</p>\n"
  cat ../footer.html
  exit 0
fi

#mostrar exercicios
printf "<br/><br/><h2>Problems</h2>\n"
TOTPROBS=${#PROBS[@]}
#((TOTPROBS=TOTPROBS/5))
echo "<table border=1><tr><td>ID</td><td>Full Name</td><td>Local Description</td><td>OJ Link</td></tr>"
for ((i=0;i<TOTPROBS;i+=5)); do
  printf "<tr><td>${PROBS[$((i+3))]}</td><td>${PROBS[$((i+2))]}</td>"
  LINK="${PROBS[$((i+4))]}"

  if [[ "$LINK" =~ "http://" ]]; then
    printf "<td><a href=\"$LINK\" target=\"_blank\">desc</a></td>"
  elif [[ "$LINK" != "none" ]]; then
    printf "<td><a href=\"$BASEURL/contests/$CONTEST_ID/$LINK\" target=\"_blank\">desc</a></td>"
  else
    printf "<td> - - </td>"
  fi
  LINK="$(link-prob-${PROBS[i]} ${PROBS[$((i+1))]})"
  printf "<td> <a href='$LINK'>${PROBS[$((i+1))]}</td></tr>\n"
done
echo "</table>"

#Gerar Tabela com pontuacao
printf "<br/><br/><h2>Runs by Problems</h2>\n"
echo "<table border=1>"
echo "<tr><td>#</td><td>Total</td><td>Accepted</td></tr>"
for ((i=0;i<TOTPROBS;i+=5)); do
  ID=$i
  TOTALRUNS="$(cut -d: -f3 $CONTESTSDIR/$CONTEST/controle/history|grep -c "^$ID$")"
  TOTALAC="$(cut -d: -f3,5 $CONTESTSDIR/$CONTEST/controle/history|grep -c "^$ID:Accepted$")"
  ACPER=""
  if ((TOTALRUNS > 0)); then
    ACPER="($((TOTALAC*100/TOTALRUNS))%%)"
  fi
  printf "<td>${PROBS[$((i+3))]}</td><td>$TOTALRUNS</td><td>$TOTALAC ${ACPER}</td></tr>"
done
echo "</table>"

printf "<br/><br/><h2>Runs by User and Problem</h2>\n"
echo "<table border=1>"
echo "<tr><td>Users x Problems</td>"
for ((i=0;i<TOTPROBS;i+=5)); do
  printf "<td>${PROBS[$((i+3))]}</td>"
done
echo "<td>Total</td><td>Accepted</td></tr>"

for LOGIN in $CONTESTSDIR/$CONTEST/controle/*.d; do
  LOGINN="$(basename $LOGIN .d)"
  NOME=$(grep "^$LOGINN:" $CONTESTSDIR/$CONTEST/passwd |cut -d':' -f3)
  TOTALRUNS="$(cut -d: -f2 $CONTESTSDIR/$CONTEST/controle/history|grep -c "^$LOGINN$")"
  AC=0
  printf "<td>$NOME</td>"
  for ((i=0;i<TOTPROBS;i+=5)); do
    JAACERTOU=0
    TENTATIVAS=0
    source $LOGIN/$i 2>/dev/null
    COR=lightgreen
    if (( JAACERTOU == 0 ));then
      COR=white
    else
      ((AC++))
    fi

    if (( TENTATIVAS != 0 )) && ((TOTALRUNS!=0)); then
      TENTATIVAS="$TENTATIVAS ( $((TENTATIVAS*100/TOTALRUNS))%%)"
    fi
    printf "<td bgcolor=$COR>$TENTATIVAS</td>"
  done

  ACO=$AC
  if ((AC!=0)); then
    AC="$AC ( $((AC*100/TOTALRUNS))%)"
  fi
  echo "<td>$TOTALRUNS</td><td>$AC</td></tr>:$ACO"
done|sort -n -r -t':' -k2|cut -d: -f1
echo "</table>"

cat ../footer.html