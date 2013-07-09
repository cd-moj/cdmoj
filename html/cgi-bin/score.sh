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
printf "<h1>SCORE de \"<em>$CONTEST_NAME</em>\"</h1>\n"

printf "<ul><li>Início: $(date --date=@$CONTEST_START)</li>"
printf "<li>Término:  $(date --date=@$CONTEST_END)</li>"

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
echo "<tr><td>Nome</td>"
for ((i=0;i<TOTPROBS;i+=5)); do
    printf "<td>${PROBS[$((i+3))]}</td>"
done
echo "<td>Total</td></tr>"
cat $CONTESTSDIR/$CONTEST/controle/SCORE
echo "</table>"

cat ../footer.html
